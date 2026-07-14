-- shared/events.lua — constantes de evento do vhub_df (R9: nomes só aqui)

VHubDF = VHubDF or {}
VHubDF.E = {
    -- cliente → servidor
    -- (criação de cobrança NÃO tem evento de cliente: só via export server-side —
    --  o cliente jamais escolhe valor/produto; o consumidor mapeia pacote→preço)
    CHECK_STATUS    = 'vhub_df:sv:checkStatus',
    CANCEL_PAYMENT  = 'vhub_df:sv:cancelPayment',

    -- servidor → cliente (NUI)
    NUI_OPEN        = 'vhub_df:cl:nuiOpen',
    NUI_UPDATE      = 'vhub_df:cl:nuiUpdate',
    NUI_CLOSE       = 'vhub_df:cl:nuiClose',
    PAYMENT_RESULT  = 'vhub_df:cl:paymentResult',
}
