# vhub_crypto

Biblioteca server-only para derivacao de credenciais com `scrypt` nativo do Node.

- Owner: seguranca/autenticacao.
- Consumidores autorizados: `vhub_login`, `vhub_lspdtool`.
- Sem estado persistente, rede, NUI ou dependencia npm.
- Parametros: `N=32768`, `r=8`, `p=3`, salt aleatorio de 128 bits, digest de 256 bits.
- Concorrencia: quatro derivacoes; fila limitada a 128 pedidos por consumidor.
- Falha: explicita e fechada; nunca rebaixa para SHA-256.

Fontes: OWASP Password Storage Cheat Sheet; Node.js `crypto.scrypt` e
`crypto.timingSafeEqual`.
