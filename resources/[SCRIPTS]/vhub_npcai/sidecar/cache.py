"""
cache.py — cache de áudio LRU por NPC + intenção + variante.

Duas camadas:
  • RAM (OrderedDict LRU) — resposta imediata.
  • Disco (audio_cache/<npc>/<key>.wav) — biblioteca reutilizável que SOBREVIVE a
    restart do sidecar. Segmentos determinísticos (intenção×variante×voz) são
    gravados uma vez e reusados para sempre → o sistema "evolui sozinho" e o custo
    de TTS cai a cada gameplay. Chaves dinâmicas (llm_*, nomes) NÃO vão ao disco.
"""

from __future__ import annotations
import re
import struct
import threading
from collections import OrderedDict
from pathlib import Path
from typing import Optional


_SAFE = re.compile(r'[^a-z0-9_.-]+')


class AudioCache:
    """Cache de WAV em memória (LRU) com camada opcional de persistência em disco."""

    def __init__(self, capacity: int = 256, persist_dir: Optional[Path] = None,
                 name_capacity: int = 1024):
        self._cap   = capacity
        self._cache: OrderedDict[str, bytes] = OrderedDict()
        self._lock  = threading.Lock()

        # cache de nome TTS — LRU global capado (evita crescimento ilimitado)
        self._name_cap = name_capacity
        self._names: OrderedDict[str, bytes] = OrderedDict()

        # camada de disco (biblioteca reutilizável)
        self._persist_dir = persist_dir
        if self._persist_dir:
            try:
                self._persist_dir.mkdir(parents=True, exist_ok=True)
            except OSError:
                self._persist_dir = None

    # ──────────────────────────────────────────────────────────
    # CHAVE
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def _key(npc_id: str, intent: str, variant: int = 0) -> str:
        return f'{npc_id}:{intent}:{variant}'

    def _disk_path(self, npc_id: str, intent: str, variant: int) -> Optional[Path]:
        if not self._persist_dir:
            return None
        safe_npc = _SAFE.sub('_', str(npc_id).lower())[:48] or 'npc'
        safe_key = _SAFE.sub('_', f'{intent}_{variant}'.lower())[:96] or 'seg'
        return self._persist_dir / safe_npc / f'{safe_key}.wav'

    # chaves dinâmicas não pertencem à biblioteca reutilizável
    @staticmethod
    def _persistable(intent: str) -> bool:
        return not str(intent).startswith('llm_')

    # ──────────────────────────────────────────────────────────
    # GET / PUT (LRU + disco)
    # ──────────────────────────────────────────────────────────

    def get(self, npc_id: str, intent: str, variant: int = 0) -> Optional[bytes]:
        k = self._key(npc_id, intent, variant)
        with self._lock:
            if k in self._cache:
                self._cache.move_to_end(k)
                return self._cache[k]

        # miss em RAM → tenta a biblioteca em disco (warm lazy)
        if self._persist_dir and self._persistable(intent):
            path = self._disk_path(npc_id, intent, variant)
            if path and path.exists():
                data = self.load_file(str(path))
                if data:
                    self._put_mem(k, data)
                    return data
        return None

    def _put_mem(self, k: str, data: bytes):
        with self._lock:
            if k in self._cache:
                self._cache.move_to_end(k)
            self._cache[k] = data
            if len(self._cache) > self._cap:
                self._cache.popitem(last=False)  # evict LRU

    def put(self, npc_id: str, intent: str, data: bytes, variant: int = 0):
        self._put_mem(self._key(npc_id, intent, variant), data)
        # grava na biblioteca de disco (best-effort, só segmentos determinísticos)
        if self._persist_dir and self._persistable(intent):
            path = self._disk_path(npc_id, intent, variant)
            if path and not path.exists():
                try:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
                except OSError:
                    pass

    def has(self, npc_id: str, intent: str, variant: int = 0) -> bool:
        return self._key(npc_id, intent, variant) in self._cache

    # ──────────────────────────────────────────────────────────
    # CACHE DE NOME (TTS de nome próprio — LRU capado)
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def _name_key(npc_id: str, name: str) -> str:
        return f'{npc_id}\x00{name}'

    def get_name(self, npc_id: str, name: str) -> Optional[bytes]:
        k = self._name_key(npc_id, name)
        with self._lock:
            if k in self._names:
                self._names.move_to_end(k)
                return self._names[k]
        return None

    def put_name(self, npc_id: str, name: str, data: bytes):
        k = self._name_key(npc_id, name)
        with self._lock:
            if k in self._names:
                self._names.move_to_end(k)
            self._names[k] = data
            if len(self._names) > self._name_cap:
                self._names.popitem(last=False)  # evict LRU

    # ──────────────────────────────────────────────────────────
    # STITCH — concatena segmentos WAV (todos 16kHz mono)
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def _find_chunk(wav: bytes, target: bytes) -> int:
        """Caminha os chunks RIFF e retorna a posição do ID de `target` (ou -1)."""
        pos = 12  # pula 'RIFF'(4) + size(4) + 'WAVE'(4)
        n = len(wav)
        while pos + 8 <= n:
            cid = wav[pos:pos + 4]
            try:
                size = struct.unpack_from('<I', wav, pos + 4)[0]
            except struct.error:
                return -1
            if cid == target:
                return pos
            pos += 8 + size + (size & 1)  # +1 de padding se ímpar
        return -1

    @staticmethod
    def stitch(segments: list[bytes]) -> bytes:
        """
        Concatena múltiplos WAV em um único WAV, sem re-encode.
        Os parâmetros (taxa/canais/bits) são LIDOS do 1º segmento válido via caminhada
        de chunks RIFF (robusto a JUNK/LIST/fact antes do 'data').
        """
        pcm_chunks: list[bytes] = []
        sample_rate = 16000
        num_channels = 1
        bits_per_sample = 16
        _params_read = False

        for wav in segments:
            if not wav:
                continue
            try:
                if wav[:4] == b'RIFF':
                    # lê fmt do 1º segmento válido (taxa/canais/bits reais)
                    if not _params_read:
                        fmt_pos = AudioCache._find_chunk(wav, b'fmt ')
                        if fmt_pos != -1:
                            num_channels    = struct.unpack_from('<H', wav, fmt_pos + 10)[0]
                            sample_rate     = struct.unpack_from('<I', wav, fmt_pos + 12)[0]
                            bits_per_sample = struct.unpack_from('<H', wav, fmt_pos + 22)[0]
                            _params_read = True
                    # extrai o chunk PCM via caminhada de chunks (não offset fixo 36)
                    data_pos = AudioCache._find_chunk(wav, b'data')
                    if data_pos == -1:
                        continue  # WAV sem chunk data → ignora (não corrompe o stitch)
                    chunk_size = struct.unpack_from('<I', wav, data_pos + 4)[0]
                    start = data_pos + 8
                    pcm_chunks.append(wav[start: start + chunk_size])
                else:
                    pcm_chunks.append(wav)
            except Exception:
                continue

        pcm_data = b''.join(pcm_chunks)
        byte_rate = sample_rate * num_channels * (bits_per_sample // 8)
        block_align = num_channels * (bits_per_sample // 8)
        data_size = len(pcm_data)
        riff_size = 36 + data_size

        header = struct.pack(
            '<4sI4s4sIHHIIHH4sI',
            b'RIFF', riff_size, b'WAVE',
            b'fmt ', 16, 1, num_channels,
            sample_rate, byte_rate, block_align, bits_per_sample,
            b'data', data_size,
        )
        return header + pcm_data

    # ──────────────────────────────────────────────────────────
    # CARREGA WAV DE ARQUIVO
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def load_file(path: str) -> Optional[bytes]:
        try:
            with open(path, 'rb') as f:
                return f.read()
        except OSError:
            return None

    # ──────────────────────────────────────────────────────────
    # ESTATÍSTICAS
    # ──────────────────────────────────────────────────────────

    def stats(self) -> dict:
        with self._lock:
            return {
                'entries':  len(self._cache),
                'capacity': self._cap,
                'names':    len(self._names),
                'persist':  bool(self._persist_dir),
            }
