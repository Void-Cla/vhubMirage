"""Regressões de segurança, frescor, transação e protocolo sem rede/FiveM."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from unittest.mock import patch

import base


class TesteBase(unittest.TestCase):
    def setUp(self):
        self.temporario = tempfile.TemporaryDirectory()
        self.raiz = Path(self.temporario.name).resolve()
        self.fonte = 'resources/[SCRIPTS]/vhub_login/client/main.lua'
        self.escrever(self.fonte, '-- autenticação\nlocal fluxo = "selecao_personagem"\n')
        self.escrever('CLAUDE.md', '# Contrato\nLogin autentica e HSS controla spawn.\n')

    def tearDown(self):
        self.temporario.cleanup()

    def escrever(self, caminho, texto):
        destino = self.raiz / caminho
        destino.parent.mkdir(parents=True, exist_ok=True)
        destino.write_text(texto, encoding='utf-8')

    def test_consulta_citacao_unicode_e_filtro(self):
        base.indexar(self.raiz)
        resultado = base.consultar(self.raiz, 'autenticacao', recurso='vhub_login')
        self.assertEqual(resultado['evidencias'][0]['citacao'], self.fonte + ':1-2')
        self.assertIn('autenticação', resultado['evidencias'][0]['texto'])
        self.assertEqual(base.consultar(self.raiz, 'HSS', recurso='vhub_sims')['evidencias'], [])

    def test_incremental_e_remocao(self):
        self.assertEqual(base.indexar(self.raiz)['alterados'], 2)
        self.assertEqual(base.indexar(self.raiz)['alterados'], 0)
        self.escrever(self.fonte, '-- estado_alterado')
        with self.assertRaisesRegex(ValueError, 'desatualizada'):
            base.consultar(self.raiz, 'login')
        self.assertEqual(base.indexar(self.raiz)['alterados'], 1)
        (self.raiz / self.fonte).unlink()
        self.assertEqual(base.indexar(self.raiz)['removidos'], 1)
        self.assertEqual(base.consultar(self.raiz, 'estado_alterado')['evidencias'], [])

    def test_hash_impede_fonte_obsoleta_com_mesmo_stat(self):
        base.indexar(self.raiz)
        caminho = self.raiz / self.fonte
        anterior = caminho.stat()
        self.escrever(self.fonte, caminho.read_text(encoding='utf-8').replace('fluxo', 'outro'))
        os.utime(caminho, ns=(anterior.st_atime_ns, anterior.st_mtime_ns))
        with self.assertRaisesRegex(ValueError, 'fonte_divergente'):
            base.consultar(self.raiz, 'selecao_personagem')

    def test_segredos_e_fontes_privadas(self):
        segredo = 'cfx' + 'k_' + 'a' * 32
        self.escrever(self.fonte, f'-- fluxo\nlocal valor = "{segredo}"\nlocal senha = "privada"\n-- fim')
        for caminho in ('config/identity.cfg', '.env', '.claude/settings.local.json',
                        'resources/[SCRIPTS]/vhub_login/exemplo/fonte.lua',
                        'resources/[SCRIPTS]/terceiro/fonte.lua'):
            self.escrever(caminho, 'SEGREDO_PRIVADO')
        base.indexar(self.raiz)
        resultado = base.consultar(self.raiz, 'fluxo')
        texto = resultado['evidencias'][0]['texto']
        self.assertNotIn(segredo, texto)
        self.assertNotIn('privada', texto)
        self.assertEqual(texto.splitlines()[3], '-- fim')
        self.assertEqual(base.consultar(self.raiz, 'SEGREDO_PRIVADO')['evidencias'], [])
        self.assertNotIn(segredo.encode(), (self.raiz / '.rag/base.sqlite3').read_bytes())

    def test_rollback_preserva_snapshot(self):
        base.indexar(self.raiz)
        self.escrever('CLAUDE.md', '# Nova versao')
        ler_original = base.ler

        def falhar(raiz, relativo):
            if relativo == self.fonte:
                raise OSError('falha simulada')
            return ler_original(raiz, relativo)

        with patch.object(base, 'ler', side_effect=falhar), self.assertRaises(OSError):
            base.indexar(self.raiz)
        with closing(sqlite3.connect(self.raiz / '.rag/base.sqlite3')) as banco:
            texto = banco.execute("SELECT texto FROM trechos WHERE caminho='CLAUDE.md'").fetchone()[0]
            self.assertIn('# Contrato', texto)

    def test_edicao_durante_leitura_aborta_indexacao(self):
        base.indexar(self.raiz)
        original = base.ler

        def alterar(raiz, relativo):
            resultado = original(raiz, relativo)
            if relativo == self.fonte:
                self.escrever(self.fonte, '-- texto novo durante leitura')
            return resultado

        with patch.object(base, 'ler', side_effect=alterar):
            with self.assertRaisesRegex(ValueError, 'durante_indexacao'):
                base.indexar(self.raiz)
        self.assertEqual(base.status(self.raiz)['desatualizados'], 1)

    def test_consulta_nao_mistura_snapshots(self):
        base.indexar(self.raiz)
        with closing(sqlite3.connect(self.raiz / '.rag/base.sqlite3')) as banco:
            banco.execute('PRAGMA journal_mode=WAL')
        conectar_original = base.conectar
        teste = self

        class Cursor:
            def __init__(self, cursor):
                self.cursor = cursor

            def fetchall(self):
                linhas = self.cursor.fetchall()
                teste.escrever(teste.fonte, '-- selecao_personagem nova implementação')
                base.indexar(teste.raiz)
                return linhas

        class Banco:
            def __init__(self, banco):
                self.banco = banco

            def execute(self, sql, *args):
                cursor = self.banco.execute(sql, *args)
                return Cursor(cursor) if sql.startswith('SELECT caminho,texto') else cursor

            def close(self):
                self.banco.close()

        def conectar(raiz, escrita=False):
            banco = conectar_original(raiz, escrita)
            return banco if escrita else Banco(banco)

        with patch.object(base, 'conectar', side_effect=conectar):
            with self.assertRaisesRegex(ValueError, 'fonte_divergente'):
                base.consultar(self.raiz, 'selecao_personagem')

    def test_entradas_hostis_e_base_ausente(self):
        with self.assertRaisesRegex(ValueError, 'base_ausente'):
            base.status(self.raiz)
        base.indexar(self.raiz)
        for consulta, limite, recurso in [('x' * 501, 6, ''), ('x', True, ''),
                                          ('x', 13, ''), ('x', 6, '../config'), ('???', 6, '')]:
            with self.assertRaises(ValueError):
                base.consultar(self.raiz, consulta, limite, recurso)
        base.consultar(self.raiz, '" OR *; DROP TABLE fontes; --')
        self.assertEqual(base.status(self.raiz)['arquivos'], 2)
        for caminho in ('../CLAUDE.md', '/etc/passwd', 'config/identity.cfg'):
            with self.assertRaises(ValueError):
                base.ler(self.raiz, caminho)

    def test_link_externo_bloqueado(self):
        with tempfile.TemporaryDirectory() as externo:
            alvo = Path(externo) / 'arquivo.lua'
            alvo.write_text('vazamento', encoding='utf-8')
            link = self.raiz / 'resources/[SCRIPTS]/vhub_login/client/link.lua'
            try:
                link.symlink_to(alvo)
            except OSError:
                self.skipTest('Host sem permissão para criar symlink')
            self.assertNotIn(link.relative_to(self.raiz).as_posix(), list(base.arquivos(self.raiz)))
            with self.assertRaises(ValueError):
                base.ler(self.raiz, link.relative_to(self.raiz).as_posix())

    def test_mcp_real_subprocesso(self):
        base.indexar(self.raiz)
        mensagens = [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
             'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                        'clientInfo': {'name': 'teste', 'version': '1'}}},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
             'params': {'name': 'consultar_projeto', 'arguments': {'consulta': 'selecao_personagem'}}},
            {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call',
             'params': {'name': 'consultar_projeto', 'arguments': {'consulta': 'x', 'limite': False}}},
            {'jsonrpc': '2.0', 'id': 5, 'method': 'tools/call',
             'params': {'name': 'indexar', 'arguments': {}}},
        ]
        processo = subprocess.run(
            [sys.executable, str(Path(__file__).with_name('rag.py')), '--raiz', str(self.raiz), 'mcp'],
            input='\n'.join(json.dumps(m) for m in mensagens) + '\n',
            capture_output=True, text=True, encoding='utf-8', timeout=15, check=True)
        respostas = [json.loads(linha) for linha in processo.stdout.splitlines()]
        self.assertEqual(len(respostas), 5)
        self.assertEqual(len(respostas[1]['result']['tools']), 2)
        dados = json.loads(respostas[2]['result']['content'][0]['text'])
        self.assertTrue(dados['evidencias'])
        self.assertTrue(respostas[3]['result']['isError'])
        self.assertTrue(respostas[4]['result']['isError'])
        self.assertEqual(processo.stderr, '')


if __name__ == '__main__':
    unittest.main()
