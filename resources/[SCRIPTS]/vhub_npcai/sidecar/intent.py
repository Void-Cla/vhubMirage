"""
intent.py — motor de intenção em 3 níveis (N1 keywords, N2 regex, N3 ML)
Pipeline: N1 → N2 → N3 → None (Gemini)
Intents com requires_memory são filtrados quando a memória do player não atende.
"""

from __future__ import annotations
import re
import unicodedata
from typing import Optional


def _strip_accents(text: str) -> str:
    """normaliza texto: minúsculo, sem acento, sem pontuação."""
    nfkd = unicodedata.normalize('NFKD', text.lower())
    ascii_str = ''.join(c for c in nfkd if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9\s]', ' ', ascii_str)


def _tokenize(text: str) -> set[str]:
    return set(_strip_accents(text).split())


class IntentEngine:
    """Reconhece intenção de texto em 3 camadas para um NPC específico."""

    def __init__(self, npc_cfg: dict):
        self._cfg = npc_cfg
        # pré-compila padrões N1 e N2 uma única vez no load do NPC
        # tupla: (intent_name, data, weight, requires_memory)
        self._n1_intents: list[tuple[str, set[str], float, dict]] = []
        self._n2_intents: list[tuple[str, list[re.Pattern], float, dict]] = []
        self._n3_model = None  # carregado via train()
        self._compile_intents()

    def _compile_intents(self):
        """Compila gatilhos, padrões e gates de memória do config do NPC."""
        intencoes = self._cfg.get('intencoes', {})
        for intent_name, cfg in intencoes.items():
            req = cfg.get('requires_memory', {})

            # N1: lista de palavras-chave (intersection ponderada)
            kw = cfg.get('keywords', [])
            if kw:
                self._n1_intents.append((
                    intent_name,
                    set(_strip_accents(w) for w in kw),
                    float(cfg.get('weight', 1.0)),
                    req,
                ))
            # N2: lista de regex
            patterns_raw = cfg.get('patterns', [])
            compiled = []
            for p in patterns_raw:
                try:
                    compiled.append(re.compile(p, re.IGNORECASE | re.UNICODE))
                except re.error:
                    pass
            if compiled:
                self._n2_intents.append((
                    intent_name,
                    compiled,
                    float(cfg.get('weight', 1.0)),
                    req,
                ))

    # ──────────────────────────────────────────────────────────
    # HELPERS
    # ──────────────────────────────────────────────────────────

    @staticmethod
    def _mem_ok(requires: dict, memory: dict) -> bool:
        """Retorna True quando todas as condições de requires_memory são satisfeitas."""
        if not requires:
            return True
        for k, v in requires.items():
            if memory.get(k) != str(v):
                return False
        return True

    # ──────────────────────────────────────────────────────────
    # N1 — keyword intersection ponderada
    # ──────────────────────────────────────────────────────────

    def _n1(self, tokens: set[str], conf_min: float, memory: dict) -> Optional[tuple[str, float]]:
        best_intent = None
        best_score  = 0.0
        for intent_name, kw_set, weight, req in self._n1_intents:
            if not kw_set:
                continue
            if not self._mem_ok(req, memory):
                continue
            intersection = tokens & kw_set
            score = (len(intersection) / len(kw_set)) * weight
            if score > best_score:
                best_score  = score
                best_intent = intent_name
        if best_score >= conf_min and best_intent:
            return best_intent, round(best_score, 3)
        return None

    # ──────────────────────────────────────────────────────────
    # N2 — regex + contexto (primeiro match vence)
    # ──────────────────────────────────────────────────────────

    def _n2(self, text: str, conf_min: float, memory: dict) -> Optional[tuple[str, float]]:
        normalized = _strip_accents(text)
        best_intent = None
        best_score  = 0.0
        for intent_name, patterns, weight, req in self._n2_intents:
            if not self._mem_ok(req, memory):
                continue
            for pat in patterns:
                m = pat.search(normalized)
                if m:
                    score = 0.85 * weight
                    if score > best_score:
                        best_score  = score
                        best_intent = intent_name
                    break
        if best_score >= conf_min and best_intent:
            return best_intent, round(best_score, 3)
        return None

    # ──────────────────────────────────────────────────────────
    # N3 — TF-IDF + LogReg (placeholder — ativa após coleta de dados)
    # ──────────────────────────────────────────────────────────

    def _n3(self, text: str, conf_min: float, memory: dict) -> Optional[tuple[str, float]]:
        if self._n3_model is None:
            return None
        try:
            result = self._n3_model.predict(text)
            intent, conf = result['intent'], result['confidence']
            if conf >= conf_min:
                # verifica gate de memória para o intent classificado pelo N3
                intencoes = self._cfg.get('intencoes', {})
                req = intencoes.get(intent, {}).get('requires_memory', {})
                if self._mem_ok(req, memory):
                    return intent, conf
        except Exception:
            pass
        return None

    def train(self, samples: list[dict]):
        """
        Treina modelo N3 com amostras { text, intent }.
        Ativado automaticamente quando o sistema acumula ≥50 amostras por intenção.
        """
        try:
            from sklearn.pipeline import Pipeline
            from sklearn.feature_extraction.text import TfidfVectorizer
            from sklearn.linear_model import LogisticRegression
            import numpy as np

            texts   = [_strip_accents(s['text']) for s in samples]
            labels  = [s['intent'] for s in samples]
            if len(set(labels)) < 2 or len(texts) < 20:
                return False

            pipeline = Pipeline([
                ('tfidf', TfidfVectorizer(ngram_range=(1, 2), max_features=2000)),
                ('clf',   LogisticRegression(max_iter=500, C=1.0)),
            ])
            pipeline.fit(texts, labels)

            class _Model:
                def __init__(self, p):
                    self._p = p
                def predict(self, text: str) -> dict:
                    proba = self._p.predict_proba([text])[0]
                    idx   = int(np.argmax(proba))
                    return {
                        'intent':     self._p.classes_[idx],
                        'confidence': float(proba[idx]),
                    }

            self._n3_model = _Model(pipeline)
            return True
        except ImportError:
            return False

    # ──────────────────────────────────────────────────────────
    # recognize — cascade N1 → N2 → N3 → None
    # ──────────────────────────────────────────────────────────

    def recognize(self, text: str, memory: dict | None = None) -> tuple[Optional[str], float, str]:
        """
        Retorna (intent, confidence, stage).
        stage = 'n1' | 'n2' | 'n3' | 'gemini'
        Intents com requires_memory não satisfeito pela memória do player são ignorados.
        """
        if memory is None:
            memory = {}

        conf_min = self._cfg.get('conf_min', {})
        tokens   = _tokenize(text)

        r = self._n1(tokens, conf_min.get('n1', 0.75), memory)
        if r:
            return r[0], r[1], 'n1'

        r = self._n2(text, conf_min.get('n2', 0.70), memory)
        if r:
            return r[0], r[1], 'n2'

        r = self._n3(text, conf_min.get('n3', 0.65), memory)
        if r:
            return r[0], r[1], 'n3'

        return None, 0.0, 'gemini'
