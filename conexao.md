# vHub Mirage - Guia de conexão e publicação do servidor

## Status atual
- O servidor FiveM agora está rodando localmente e ouvindo a porta 30120.
- O processo responsável é o FXServer.exe.
- O firewall do Windows foi ajustado para permitir entrada TCP/UDP na porta 30120.
- O servidor foi configurado para não ser tratado como LAN (`sv_lan 0`).
- O arquivo de configuração de identidade contém a licença (`sv_licenseKey`).

## O que foi feito

### 1. Configuração do FXServer
- O launcher `server.bat` foi ajustado para apontar para a pasta `build` e iniciar o FXServer corretamente.
- O script passou a usar a licença do `config/identity.cfg` quando disponível.
- O servidor foi iniciado com a configuração principal em `config/server.cfg`.

### 2. Firewall do Windows
- Foram criadas regras de firewall para permitir entrada nas portas:
  - TCP 30120
  - UDP 30120
- Comando usado:

```powershell
New-NetFirewallRule -DisplayName "FiveM Server 30120 TCP" -Direction Inbound -Protocol TCP -LocalPort 30120 -Action Allow
New-NetFirewallRule -DisplayName "FiveM Server 30120 UDP" -Direction Inbound -Protocol UDP -LocalPort 30120 -Action Allow
```

### 3. Configuração de rede do servidor
- O arquivo `config/network.cfg` foi ajustado para escutar em `0.0.0.0:30120`.
- O servidor foi marcado como público com:

```cfg
sv_lan 0
```

### 4. Licença do FiveM
- A licença foi colocada em `config/identity.cfg`:

```cfg
sv_licenseKey "..."
```

## Arquivos importantes
- `server.bat` — launcher do servidor
- `config/server.cfg` — configuração principal
- `config/network.cfg` — portas e rede
- `config/identity.cfg` — licença, hostname e identidade pública
- `config/database.cfg` — conexão com MySQL/oxmysql

## Como iniciar o servidor no outro PC
1. Copiar a pasta do projeto inteira para o outro computador.
2. Garantir que a estrutura seja mantida:
   - `build/FXServer.exe`
   - `config/`
   - `resources/`
3. Abrir o Prompt de Comando como Administrador.
4. Entrar na pasta do projeto:

```bat
cd C:\caminho\para\vhubMirage-main
```

5. Executar:

```bat
server.bat
```

## O que precisa fazer no outro PC

### 1. Firewall
- Abrir as portas 30120 TCP/UDP no firewall do Windows.
- Se necessário, repetir os comandos acima.

### 2. Roteador
- Criar o Port Forwarding para:
  - TCP 30120
  - UDP 30120
- Encaminhar para o IP local da máquina que roda o servidor.

### 3. IP local da máquina
- Descobrir o IP local com:

```powershell
ipconfig
```

### 4. IP público
- O servidor só fica realmente acessível se o roteador e a rede permitirem entrada pública na porta 30120.
- Se o provedor usar CGNAT ou bloquear portas, pode ser necessário um VPS ou outra solução de hospedagem.

## Testes recomendados
- Testar localmente:

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 30120
```

- Testar externamente via outro PC ou celular.
- Tentar conectar no FiveM com:

```text
connect SEU_IP_PUBLICO:30120
```

## Observações importantes
- O servidor pode aparecer na lista do FiveM mesmo quando o endpoint público não responde corretamente.
- O aviso de “talvez esteja offline” costuma indicar problema de porteamento público ou de resposta do endpoint.
- Se o servidor não aparecer para outros jogadores, o problema permanece em rede/roteador/ISP.

## Próximo passo
- Se o outro servidor também tiver esse problema, repetir os passos acima e validar se a porta 30120 está aberta externamente.
- Se necessário, atualizar novamente o `server.bat` para refletir o novo ambiente.
