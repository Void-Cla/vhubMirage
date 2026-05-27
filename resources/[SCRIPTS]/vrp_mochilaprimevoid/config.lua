local Config = {
    -- Sistema geral
    sistema_ativo = true,
    modo_debug = false,
    versao = '1.0.0-prime',

    -- Mochila
    mochila = {
        tecla_abertura = 243,
        peso_maximo_padrao = 50,
        slots_padrao = 10,
        binds_numpad = true,
        binds_quantidade = 5,
    },

    -- Bau de veiculo
    bau_veiculo = {
        tecla_abertura = 10,
        limite_proximidade = 3,
        webhook_auditoria = '',
        registrar_todas_acoes = true,
        cooldown_acao_segundos = 2,
        peso_padrao_por_veh = 100,
        multiplicador_por_classe = {
            [0] = 0.5,
            [1] = 0.7,
            [2] = 1.0,
            [3] = 1.5,
        }
    },

    -- Baus de faccao/casa
    baus_faccao = {
        capacidade_padrao = 50000,
        webhook_auditoria = '',
        registrar_todas_acoes = true,
        comando = 'chest',
        limite_proximidade = 3,
        cooldown_acao_segundos = 2,
        tecla_interacao = 38,
        distancia_marker = 5.0,
        distancia_interacao = 1.5,
        marker_offset_z = -0.98,
        texto_offset_z = 0.3,
        marker = {
            tipo = 23,
            escala = { x = 1.1, y = 1.1, z = 0.5 },
            cor = { r = 120, g = 80, b = 255, a = 100 }
        },
        locais = {
            { nome = 'amarelo', x = 3197.59, y = 5180.84, z = 42.94 },
            { nome = 'vermelho', x = 1444.52, y = -764.84, z = 87.69 },
            { nome = 'mecanico', x = -340.05, y = -160.44, z = 44.58 },
            { nome = 'policia', x = -1088.00, y = -819.01, z = 11.03 },
            { nome = 'policiab', x = -1102.30, y = -819.78, z = 14.28 },
            { nome = 'verdes', x = 1907.28, y = 6452.92, z = 83.84 },
            { nome = 'motoclub', x = 977.00, y = -103.83, z = 74.84 },
            { nome = 'vanilla', x = -571.67, y = 290.05, z = 79.17 },
            { nome = 'evidencias', x = 487.74, y = -998.89, z = 30.69 },
            { nome = 'triade', x = -3219.17, y = 785.09, z = 14.09 },
            { nome = 'bennys', x = -196.08, y = -1340.02, z = 34.89 },
            { nome = 'nomade', x = 984.35, y = -1530.05, z = 37.50 },
            { nome = 'vanilla', x = 93.23, y = -1291.37, z = 29.26 },
            { nome = 'mafia', x = 391.71, y = -14.14, z = 86.67 },
            { nome = 'bahamas', x = -1368.76, y = -623.78, z = 30.31 },
            { nome = 'azul', x = 1858.37, y = 3462.01, z = 45.96 },
            { nome = 'laranjas', x = -151.28, y = 2127.95, z = 170.14 },
        },
        permissoes = {
            amarelo = { capacidade = 50000, permissao = 'familiamonstro.permissao' },
            vermelho = { capacidade = 50000, permissao = 'cv.permissao' },
            mecanico = { capacidade = 50000, permissao = 'mecanico.permissao' },
            policia = { capacidade = 50000, permissao = 'policia.permissao' },
            policiab = { capacidade = 50000, permissao = 'policia.permissao' },
            verdes = { capacidade = 50000, permissao = 'ada.permissao' },
            motoclub = { capacidade = 50000, permissao = 'motoclub.permissao' },
            vanilla = { capacidade = 50000, permissao = 'vanilla.permissao' },
            triade = { capacidade = 50000, permissao = 'cali.permissao' },
            mafia = { capacidade = 50000, permissao = 'carteldemedelin.permissao' },
            evidencias = { capacidade = 50000, permissao = 'policia.permissao' },
            bennys = { capacidade = 50000, permissao = 'desmanche.permissao' },
            nomade = { capacidade = 50000, permissao = 'mecanico.permissao' },
            bahamas = { capacidade = 50000, permissao = 'bahamas.permissao' },
            azul = { capacidade = 50000, permissao = 'pcc.permissao' },
            laranjas = { capacidade = 50000, permissao = 'tcp.permissao' },
            amarelos = { capacidade = 50000, permissao = 'familiamonstro.permissao' },
            exercito = { capacidade = 50000, permissao = 'eb.permissao' },
            milicia = { capacidade = 50000, permissao = 'bahamas.permissao' },
        },
        webhooks = {
            vermelho = 'https://discord.com/api/webhooks/828366836302086185/aQ-2LVF973tZ_RM0iXmyEF78KPGQIuMsH4dALC53J5jCJYx_gXWeLVhxnGTJ1yvcBloW',
            amarelo = 'https://discord.com/api/webhooks/828367039613239296/FEl5uN8zbvmPTSLCiLVhESgcPUMaxmRV9Rr_BH4CkxyrlkeF4vWBuFD875crYWEbGyvu',
            amarelos = 'https://discord.com/api/webhooks/828367039613239296/FEl5uN8zbvmPTSLCiLVhESgcPUMaxmRV9Rr_BH4CkxyrlkeF4vWBuFD875crYWEbGyvu',
            motoclub = 'https://discordapp.com/api/webhooks/828368763296415765/nl7ARg7DEnlM3Hn9uHSMRb_XW9Wn7_f4yf7OPY9LiNMXESQ0LR9bjJs-TbtIP6fDQpYT',
            mecanico = 'https://discordapp.com/api/webhooks/828368763296415765/nl7ARg7DEnlM3Hn9uHSMRb_XW9Wn7_f4yf7OPY9LiNMXESQ0LR9bjJs-TbtIP6fDQpYT',
            mafia = 'https://discord.com/api/webhooks/828368349247045664/G1cLBzTeslaje3yXT-rZWnyoM-7zQTrysnoiFJ4lxLAsflu9n5pLcgHmuFy8sw_-GoSx',
            triade = 'https://discord.com/api/webhooks/828368563714523166/Zp_NqdIStMSPzbBmgrd0rPiCA55anQVa8AN6hQzzvpNQbSh0MewQdIVWm0Xf8V2wXu01',
            evidencias = 'https://discord.com/api/webhooks/828365984268025936/-0JkyGWEhACP4-_r0bix-3ap7GIxwG8-Ln96ROQMcye4pjI7qT_cCQH5qbtcuoaHQ4uH',
            policia = 'https://discord.com/api/webhooks/828366351865217094/vbuetzyodGm9p5YZarIRl3U1_x78ZaSPRiMCyafHW2dOLjrlTJfHDW8Zd06_vrfql_-q',
            policiab = 'https://discord.com/api/webhooks/828365984268025936/-0JkyGWEhACP4-_r0bix-3ap7GIxwG8-Ln96ROQMcye4pjI7qT_cCQH5qbtcuoaHQ4uH',
            bahamas = 'https://discord.com/api/webhooks/828368115695747093/7AP_RCZRNAtswEcNWYPfuV83khPuwnfJiXLp2-ebycwD6j_YA12_5g8QLbd5EewY-mwj',
            azul = 'https://discord.com/api/webhooks/828367641961037845/aBxuILWcXrPgSkzvHqsxgroADYbz5FIPt2cJ0ptH089IN-kd6OB07pXkjmnKnO8YsS2g',
            verdes = 'https://discord.com/api/webhooks/828367901258022913/WXtIFkJebgcsfOYnTg_o9jwVyY6LuxEWOi6lfUwLnMx4A_detAEXjWnWW5Et7ItFt9ZU',
            vanilla = 'https://discord.com/api/webhooks/828369127659798561/PldY5lTGYoKuOBNKHhcrrfq2zvDGoCIS_3ni3n9cucoEW0cy5KTzF9vpXFQavjFycvCn',
            laranjas = 'https://discord.com/api/webhooks/828367441046142976/DKAoOfDNHRQvDsYvdx0DGc-GMn2K6r8NKWihqVNpbEwtiNvZU2sRR7qYjsbwp1R4J0vt',
        }
    },
    -- Identidade
    identidade = {
        habilitar = true,
        comando = 'identidade',
        tecla = 'F11',
    },
    -- Marketplace
    marketplace = {
        comando = 'market',
        maximo_anuncios_por_jogador = 10,
        tempo_expiracao_anuncio = 604800,
        comissao_percentual = 0,
        preco_maximo = 500000,
        quantidade_maxima = 100,
        caracteres_descricao_max = 160,
        limite_recentes = 15,
        limite_itens = 200,
        webhook_vendas = '',
    },

    -- Lojas NPC (server)
    lojas = {
        raio_atuacao_padrao = 3,
        tecla_interacao = 38,
        permitir_venda_para_servidor = true,
        webhook_vendas_loja = '',
        desconto_progressivo = {
            [1] = 0,
            [11] = 5,
            [51] = 10,
        },
        tipos_loja = {
            mercearia = { nome = 'Mercearia', cor = '#FF6B6B', icone = 'M' },
            farmacia = { nome = 'Farmacia', cor = '#4ECDC4', icone = 'F' },
            armas = { nome = 'Armaria', cor = '#A8E6CF', icone = 'A' },
            veiculo = { nome = 'Concessionaria', cor = '#FFD93D', icone = 'V' },
            roupa = { nome = 'Loja de Roupas', cor = '#FF99CC', icone = 'R' },
            bar = { nome = 'Bar', cor = '#FFB6C1', icone = 'B' },
            padaria = { nome = 'Padaria', cor = '#D4A574', icone = 'P' },
            general = { nome = 'Loja Geral', cor = '#95E1D3', icone = 'G' },
        },
        lojas_padrao = {
            {
                loja_id = 'mercearia_centro',
                nome = 'Mercearia Central',
                tipo_loja = 'mercearia',
                x = 25.4, y = -934.5, z = 29.4,
                proprietario = 'SERVER',
                itens = {
                    { item = 'maca', preco = 50, estoque = 100 },
                    { item = 'pao', preco = 30, estoque = 200 },
                    { item = 'agua', preco = 10, estoque = 500 },
                    { item = 'cerveja', preco = 80, estoque = 150 },
                }
            },
            {
                loja_id = 'farmacia_centro',
                nome = 'Farmacia Central',
                tipo_loja = 'farmacia',
                x = 442.3, y = -981.5, z = 29.4,
                proprietario = 'SERVER',
                itens = {
                    { item = 'bandagem', preco = 100, estoque = 50 },
                    { item = 'remedio', preco = 200, estoque = 30 },
                    { item = 'antidoto', preco = 300, estoque = 20 },
                }
            },
            {
                loja_id = 'bar_vanilla',
                nome = 'Vanilla Unicorn Bar',
                tipo_loja = 'bar',
                x = 127.2, y = -1298.4, z = 29.4,
                proprietario = 'SERVER',
                itens = {
                    { item = 'cerveja', preco = 100, estoque = 200 },
                    { item = 'vodka', preco = 150, estoque = 100 },
                    { item = 'whisky', preco = 200, estoque = 80 },
                    { item = 'agua', preco = 20, estoque = 300 },
                }
            },
        }
    },

    -- Seguranca
    seguranca = {
        validar_checksums = true,
        detectar_duplicacao = true,
        recuperacao_automatica = true,
        timeout_transacao = 3600,
        max_tentativas = 3,
        intervalo_retry = 5000,
        drop_ttl = 300,
    },

    -- Compatibilidade com scripts vRP existentes
    compat = {
        habilitar = true,
        sincronizar_spawn = true,
        sincronizar_online = true,
    },    -- Player (port do vrp_player)
    player = {
        habilitar = true,
        afk = {
            habilitar = true,
            tempo_limite = 1800,
            aviso_segundos = 60,
            permissao_imune = 'dono.permissao',
        },
        salario = {
            habilitar = true,
            intervalo_minutos = 45,
            grupos = {
                { permissao = 'bronze.permissao', nome = 'BRONZE', pagamento = 3250 },
                { permissao = 'prata.permissao', nome = 'PRATA', pagamento = 5500 },
                { permissao = 'ouro.permissao', nome = 'OURO', pagamento = 9000 },
                { permissao = 'platina.permissao', nome = 'PLATINA', pagamento = 15000 },
                { permissao = 'black.permissao', nome = 'BLACK', pagamento = 25780 },
                { permissao = 'girafalis.permissao', nome = 'ESMERALDA', pagamento = 20000 },
                { permissao = 'chaves.permissao', nome = 'SUPREME', pagamento = 40732 },
                { permissao = 'seubarriga.permissao', nome = 'DELTA', pagamento = 50989 },
                { permissao = 'recruta.servico', nome = 'RECRUTA', pagamento = 4000 },
                { permissao = 'soldado.servico', nome = 'SOLDADO', pagamento = 6500 },
                { permissao = 'sargento.servico', nome = 'SARGENTO', pagamento = 8500 },
                { permissao = 'tenente.servico', nome = 'TENENTE', pagamento = 10500 },
                { permissao = 'capitao.servico', nome = 'CAPITAO', pagamento = 11500 },
                { permissao = 'tencoronel.servico', nome = 'TENCORONEL', pagamento = 13000 },
                { permissao = 'coronel.servico', nome = 'CORONEL', pagamento = 20000 },
                { permissao = 'sargentortm.servico', nome = 'SARGENTO_RT', pagamento = 8500 },
                { permissao = 'tenentertm.servico', nome = 'TENENTE_RT', pagamento = 10500 },
                { permissao = 'capitaortm.servico', nome = 'CAPITAO_RT', pagamento = 11500 },
                { permissao = 'tencoronelrtm.servico', nome = 'TENCORONEL_RT', pagamento = 13000 },
                { permissao = 'coronelrtm.servico', nome = 'CORONEL_RT', pagamento = 20000 },
                { permissao = 'pf.servico', nome = 'POLICIAL_FEDERAL', pagamento = 13000 },
                { permissao = 'tor1.servico', nome = 'TATICO_RODOVIARIO', pagamento = 12000 },
                { permissao = 'delegado.permissao', nome = 'DELEGADO', pagamento = 12000 },
                { permissao = 'agente.permissao', nome = 'AGENTE', pagamento = 12000 },
                { permissao = 'perito.permissao', nome = 'PERITO_CRIMINAL', pagamento = 15000 },
                { permissao = 'investigador.permissao', nome = 'INVESTIGADOR', pagamento = 10000 },
                { permissao = 'enfermeiro.servico', nome = 'ENFERMEIRO', pagamento = 6500 },
                { permissao = 'paramedico.servico', nome = 'PARAMEDICO', pagamento = 9000 },
                { permissao = 'medico.servico', nome = 'MEDICO', pagamento = 13500 },
                { permissao = 'diretor.servico', nome = 'DIRETOR', pagamento = 16000 },
                { permissao = 'mecanico.permissao', nome = 'MECANICO', pagamento = 3200 },
                { permissao = 'juiza.permissao', nome = 'JUIZA', pagamento = 3500 },
                { permissao = 'news.permissao', nome = 'NEWS', pagamento = 6300 },
                { permissao = 'taxistalider.permissao', nome = 'TAXI_LIDER', pagamento = 6300 },
                { permissao = 'taxista.permissao', nome = 'TAXISTA', pagamento = 5300 },
                { permissao = 'advogado.permissao', nome = 'ADVOGADO', pagamento = 4500 },
                { permissao = 'salario1.servico', nome = 'SALARIO_1', pagamento = 4000 },
                { permissao = 'salario2.servico', nome = 'SALARIO_2', pagamento = 3000 },
                { permissao = 'salario3.servico', nome = 'SALARIO_3', pagamento = 2000 },
            }
        },
        hud = {
            esconder_componentes = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 17, 18, 20, 21, 22 },
            desativar_wanted = true,
            ignorar_policia = true,
        },
        densidade = {
            ped = 0.5,
            scenario = 0.5,
            parked = 0.5,
            vehicles = 0.5,
            random = 0.5,
            garbage_trucks = true,
            random_boats = true,
        },
        placas = {
            habilitar = false,
            imagem_url = 'https://cdn.discordapp.com/attachments/683792195530260608/764909905827463168/mercosul.png',
            modelo_url = 'https://i.imgur.com/Q3uw6V7.png',
            largura = 540,
            altura = 300,
        },
        stamina = {
            infinito = true,
            intervalo_ms = 4000,
        },
        energetico = {
            multiplicador = 1.15,
            duracao_ms = 60000,
        },
        lockpick = {
            policia_minima = 5,
            chance_sucesso = 20,
            tempo_ms = 30000,
        },
        masterpick = {
            policia_minima = 5,
            chance_sucesso = 50,
            tempo_ms = 20000,
        },
        garmas = {
            cooldown = 10,
            aviso_segundos = 14,
            banir = true,
        },
        webhooks = {
            give = '',
            equipar = '',
            dropar = '',
            enviar_item = '',
            enviar_dinheiro = '',
            paypal = '',
            saquear = '',
            bancocentral_bug = '',
            garmas_ban = '',
            garmas_tentativa = '',
        },
    },
    -- Itens bloqueados
    itens_bloqueados_marketplace = {
        'dinheirosujo',
        'rg',
        'cnh',
        'coin',
    },

    itens_bloqueados_drop = {
        'rg',
        'cnh',
        'coin',
        'carteira_vip',
    },
    itens_bloqueados_bau = {
        'identidade',
    },
    itens_bloqueados_bau_veiculo = {
        'dinheirosujo',
        'identidade',
    },

    -- NUI
    nui = {
        tema = 'dark',
        animacoes_ativas = true,
        som_ativo = true,
        transicao_velocidade = 300,
    },

    -- Notificacoes
    notificacoes = {
        ativas = true,
        tempo_exibicao = 5000,
        posicao = 'top-right',
    },
}

return Config



