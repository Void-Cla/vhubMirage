# GUIA_CONFIG - void_mochila_prime

Este guia descreve cada opcao do `config.lua`.

## Sistema geral
- `sistema_ativo`: liga/desliga o recurso.
- `modo_debug`: habilita logs adicionais.
- `versao`: string de versao.

## Mochila (`mochila`)
- `tecla_abertura`: tecla para abrir a mochila.
- `peso_maximo_padrao`: peso maximo default.
- `slots_padrao`: numero de slots base.
- `binds_numpad`: ativa binds no numpad.
- `binds_quantidade`: quantidade de binds.

## Bau veiculo (`bau_veiculo`)
- `tecla_abertura`: tecla para abrir porta-malas.
- `limite_proximidade`: distancia para abrir.
- `webhook_auditoria`: webhook para logs do porta-malas.
- `registrar_todas_acoes`: log completo do porta-malas.
- `cooldown_acao_segundos`: intervalo minimo entre guardar/retirar.
- `peso_padrao_por_veh`: capacidade default.
- `multiplicador_por_classe`: multiplicador por classe do veiculo.

## Baus faccao (`baus_faccao`)
- `capacidade_padrao`: capacidade default do bau.
- `webhook_auditoria`: webhook para logs.
- `registrar_todas_acoes`: log completo.
- `comando`: comando para abrir baus.
- `limite_proximidade`: distancia minima de outros jogadores para abrir.
- `cooldown_acao_segundos`: intervalo minimo entre guardar/retirar.
- `tecla_interacao`: tecla de abertura.
- `distancia_marker`: distancia para exibir marker.
- `distancia_interacao`: distancia para interagir.
- `marker_offset_z`: ajuste vertical do marker.
- `texto_offset_z`: ajuste vertical do texto.
- `marker`: configuracao do marker (tipo/escala/cor).
- `locais`: lista de pontos de bau.
- `permissoes`: permissoes por bau.
- `webhooks`: webhooks por bau (nome -> url).

## Identidade (`identidade`)
- `habilitar`: ativa o comando da identidade.
- `comando`: comando para abrir.
- `tecla`: tecla para key mapping.

## Marketplace (`marketplace`)
- `comando`: comando para abrir.
- `maximo_anuncios_por_jogador`: limite por jogador.
- `tempo_expiracao_anuncio`: tempo para expirar.
- `comissao_percentual`: taxa aplicada na venda.
- `preco_maximo`: limite de preco.
- `quantidade_maxima`: limite de quantidade.
- `caracteres_descricao_max`: limite de descricao.
- `limite_recentes`: quantidade de recentes.
- `limite_itens`: quantidade listada.
- `webhook_vendas`: webhook de vendas.

## Lojas (`lojas`)
- `raio_atuacao_padrao`: distancia de acesso.
- `tecla_interacao`: tecla de abrir.
- `permitir_venda_para_servidor`: liga venda para servidor.
- `webhook_vendas_loja`: webhook de vendas.
- `desconto_progressivo`: descontos por volume.
- `tipos_loja`: definicao visual por tipo.
- `lojas_padrao`: lista de lojas criadas no bootstrap.

## Seguranca (`seguranca`)
- `validar_checksums`: checa integridade.
- `detectar_duplicacao`: busca duplicados.
- `recuperacao_automatica`: auto-recovery.
- `timeout_transacao`: timeout de transacoes pendentes.
- `max_tentativas`: maximo de tentativas.
- `intervalo_retry`: intervalo entre tentativas.
- `drop_ttl`: tempo do drop no mundo.

## Itens bloqueados
- `itens_bloqueados_marketplace`: itens proibidos no marketplace.
- `itens_bloqueados_drop`: itens proibidos no drop.
- `itens_bloqueados_bau`: itens proibidos em bau de faccao.
- `itens_bloqueados_bau_veiculo`: itens proibidos em bau de veiculo.

## NUI (`nui`)
- `tema`: tema visual.
- `animacoes_ativas`: anima a UI.
- `som_ativo`: sons da UI.
- `transicao_velocidade`: tempo das transicoes.

## Notificacoes (`notificacoes`)
- `ativas`: ativa notificacoes.
- `tempo_exibicao`: tempo em ms.
- `posicao`: posicao na tela.




