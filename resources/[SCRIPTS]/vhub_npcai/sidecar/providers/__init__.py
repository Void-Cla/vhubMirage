"""
providers — abstração de provedores de IA do vhub_npcai.

Permite trocar de IA (resposta e voz) sem tocar no pipeline:
  • LLM  (resposta):  Gemini | OpenAI | none
  • TTS  (voz):       SAPI   | OpenAI | none

A escolha vem por requisição, no bloco `ai` do payload /converse (autoridade =
config Lua do FiveM). Chaves de API vivem em variável de ambiente, nunca no código.
"""

from .llm import get_llm, reset_llm_registry, LLMProvider
from .tts import get_tts, reset_tts_registry, TTSProvider

__all__ = [
    'get_llm', 'reset_llm_registry', 'LLMProvider',
    'get_tts', 'reset_tts_registry', 'TTSProvider',
]
