# Documentação — Servidor de Minecraft 24/7 (NixOS + Docker + Paper)

Registro do progresso da configuração do servidor, incluindo problemas encontrados e soluções aplicadas.

---

## 1. Contexto e objetivo

- Servidor NixOS rodando em máquina separada do PC principal (acessado via SSH).
- Objetivo: servidor de Minecraft 24/7 acessível para amigos de fora da rede doméstica, além de um servidor de mídia (Jellyfin) restrito à rede local (a ser tratado em conversa separada).
- Interface de acesso ao servidor: SSH a partir do PC principal.

---

## 2. Conceitos base

**Nix**: gerenciador de pacotes funcional e determinístico. Cada pacote é isolado em `/nix/store/<hash>-nome-versao/`, permitindo múltiplas versões coexistirem sem conflito e rollback trivial.

**NixOS**: distribuição Linux inteira descrita declarativamente em `/etc/nixos/configuration.nix`. Mudanças são aplicadas com:
```bash
sudo nixos-rebuild switch
```
Se estiver usando flakes:
```bash
sudo nixos-rebuild switch --flake .#nome-do-host
```

---

## 3. Configuração do Docker no NixOS

No `/etc/nixos/configuration.nix`:
```nix
virtualisation.docker.enable = true;
users.users.SEU_USUARIO.extraGroups = [ "docker" ];
environment.systemPackages = with pkgs; [ docker-compose ];

networking.firewall.allowedTCPPorts = [ 25565 ];
```
Aplicar com `sudo nixos-rebuild switch`, depois relogar para o grupo `docker` fazer efeito.

---

## 4. Estrutura do projeto

```
~/minecraft-server/
├── docker-compose.yml
├── data/       (mundo, configs, logs do servidor — persistente)
└── plugins/    (arquivos .jar dos plugins)
```

### `docker-compose.yml` final (funcional, versão Paper)

```yaml
services:
  minecraft:
    image: itzg/minecraft-server:latest
    container_name: minecraft
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "26.2"
      ONLINE_MODE: "FALSE"       # permite contas originais E piratas
      MEMORY: "4G"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "15"
      MOTD: "MBTI Server"
    volumes:
      - ./data:/data
      - ./plugins:/plugins
    restart: unless-stopped
    stdin_open: true
    tty: true

  playit:
    image: ghcr.io/playit-cloud/playit-agent:1.0
    container_name: playit
    restart: unless-stopped
    network_mode: host
    environment:
      - SECRET_KEY=<secret_key>
```

---

## 5. Comandos essenciais do dia a dia

```bash
docker compose up -d          # subir o servidor
docker compose down           # derrubar o servidor
docker compose logs -f        # acompanhar logs (Ctrl+C para sair, não mata o container)
docker compose ps             # ver status e portas mapeadas
```

**Transferir arquivos do PC principal para o servidor** (rodar no PC principal, não no servidor):
```bash
scp caminho/do/arquivo.jar rozena@ip-do-servidor:~/minecraft-server/plugins/
```

**RCON — forma segura de rodar comandos sem risco de matar o servidor:**
```bash
docker exec minecraft rcon-cli whitelist add nick_do_jogador
docker exec minecraft rcon-cli whitelist on
docker exec minecraft rcon-cli op nick_do_jogador       # dar poderes de administrador
docker exec minecraft rcon-cli deop nick_do_jogador     # remover
```

Conferir lista de OPs diretamente no arquivo:
```bash
cat ~/minecraft-server/data/ops.json
```

⚠️ **Atenção**: se usar `docker attach minecraft` para acessar o console, a saída segura é `Ctrl+P` seguido de `Ctrl+Q`. Usar `Ctrl+C` mata o servidor abruptamente (o `restart: unless-stopped` religa sozinho, mas é melhor evitar — prefira sempre RCON).

**Ler logs comprimidos (rotacionados automaticamente pelo servidor):**
```bash
ls -la ~/minecraft-server/data/logs/
zcat 2026-08-XX-N.log.gz                                    # ler log antigo comprimido
zcat 2026-08-XX-N.log.gz | grep -i -E "error|exception|crash"  # buscar erros específicos
cat ~/minecraft-server/data/logs/latest.log                 # log atual (não comprimido)
```

---

## 6. Escolha do software de servidor: Paper (plugins), não mods

Paper foi escolhido por rodar **plugins** em vez de mods: plugins funcionam só do lado do servidor, e o jogador conecta com o client vanilla puro, sem precisar instalar nada. A troca elimina a fricção de manter mods sincronizados entre servidor e todos os jogadores.

Confirmado no momento da escolha: Paper já tinha build estável disponível para a versão do Minecraft usada (`26.2`, build 84+), sem problema de compatibilidade de versão.

### 6.1 — Mundo criado do zero
Como havia apenas jogadores de teste até então, decidiu-se recomeçar o mundo do zero ao configurar o Paper, sem necessidade de backup.

### 6.2 — Cuidado: tipo de servidor e mundo já gerado precisam ser compatíveis
Em uma tentativa própria de trocar `TYPE` para `SPIGOT` (Bukkit "puro", sem as extensões do Paper) mantendo o mesmo mundo, o servidor entrou em loop de crash:
```
Missing data pack paper
Unable to read or access the world gen settings file!
Failed to load datapacks, can't proceed with server load
Overworld settings missing
```
Causa: o mundo foi gerado pelo Paper, que injeta um data pack interno próprio (`"paper"`) na pasta do mundo. O Spigot puro não reconhece esse data pack, deixando a configuração do Overworld incompleta — o boot travava sempre no mesmo ponto, reiniciando indefinidamente.

**Solução**: reverter `TYPE` de volta para `"PAPER"` resolveu imediatamente, sem necessidade de apagar o mundo novamente.

**Lição**: não trocar o `TYPE` do servidor livremente com um mundo já existente — tipos diferentes de servidor (Paper/Spigot/outros) podem gerar estruturas de mundo incompatíveis entre si.

---

## 7. Plugins testados

| Plugin | Versão | Resultado |
|---|---|---|
| `Graves` (autor Ranull) | 4.9 | ❌ Falhou, abandonado |
| `TreeFeller` | 1.30.2 | ✅ OK |
| `AuthMe` | 6.0.0-b2734 | ✅ OK (intencional) |
| `SkinsRestorer` | 15.12.5 (versão Paper) | ✅ OK |

### 7.1 — `Graves` — incompatibilidade, abandonado
```
Error occurred while enabling Graves v4.9 (Is it up to date?)
java.lang.IllegalArgumentException: Unknown gamerule: keepInventory
```
Causa: versão desatualizada, incompatível com a API do Paper na versão usada. Existe um fork mantido (`GravesX`, com suporte oficial à versão em uso, disponível em Modrinth/SpigotMC/Hangar) que resolveria o problema, mas **decisão final: desistir do plugin de graves** e seguir sem ele. O erro não era fatal — o servidor continuava rodando normalmente mesmo com esse plugin falhando ao ativar.

### 7.2 — `TreeFeller`
Carregou e ativou sem erro. Facilita corte de árvores (derruba a árvore inteira ao cortar a base).

### 7.3 — `AuthMe`
Exige que jogadores rodem `/register <senha> <senha>` no primeiro acesso e `/login <senha>` nas conexões seguintes — camada extra de segurança de login/senha, confirmada como intencional.

Aviso observado (não crítico): `No supported permissions system found! Permissions are disabled!` — não há plugin de permissões avançado (tipo LuckPerms) instalado; o sistema de OP nativo do Minecraft continua funcionando normalmente sem isso (ver seção 5).

**Ajuste de configuração — limite de registros por IP:**
Por padrão, o `AuthMe` limita quantas contas podem se registrar a partir do mesmo IP (proteção antiabuso). Como será detalhado na seção 9, o túnel usado faz todos os jogadores aparecerem com o mesmo IP interno para o servidor, o que gerava o erro `exceeded max number of registrations`. Ajustado em:
```bash
nano ~/minecraft-server/data/plugins/AuthMe/config.yml
```
```yaml
maxRegPerIp: 2
```
Reiniciar após a alteração:
```bash
docker compose down
docker compose up -d
```

### 7.4 — `SkinsRestorer`
Permite que jogadores customizem skins mesmo em modo offline/pirata. A versão compilada para Paper funcionou sem nenhum erro:
```
[SkinsRestorer] Enabling SkinsRestorer v15.12.5
[SkinsRestorer] Running on Minecraft 26.2.0.
[SkinsRestorer] Using paper join listener!
```

---

## 8. Instalação de plugins — fluxo padrão

1. Baixar o `.jar` do plugin (fontes recomendadas: Modrinth, SpigotMC, Hangar/PaperMC) — confirmar compatibilidade com a versão do servidor antes de baixar.
2. Transferir para o servidor via `scp` (ver seção 5).
3. Reiniciar o container:
```bash
docker compose down
docker compose up -d
docker compose logs -f
```
4. Conferir no log se o plugin aparece na lista `Bukkit plugins (N)` e se ativa sem erro (`Enabling <nome>`).

**Erro comum**: `scp` falhando por causa de nome de pasta incorreto (ex: `plugin/` em vez de `plugins/`, ou lembrar que a pasta local mapeia para `/plugins` dentro do container via `volumes` no compose).

---

## 9. Acesso externo — Port Forwarding, Double NAT e a solução via `playit.gg`

### 9.1 — Levantamento de IPs
```bash
ip a                       # IP interno do servidor: 192.168.x.X
ip route | grep default    # IP do roteador: 192.168.x.x
curl -4 ifconfig.me        # IP público IPv4
```

### 9.2 — Tentativa de Port Forwarding tradicional
Regras criadas no roteador (seção "Encaminhamento de porta"):
| Nome | Protocolo | Porta WAN | LAN Host | Porta LAN |
|---|---|---|---|---|
| Minecraft | TCP | 25565 | 192.168.1.5 | 25565 |

Diagnóstico completo (firewall do NixOS, mapeamento de porta do Docker, conexão local) confirmou que tudo estava configurado corretamente do lado do servidor, mas a porta continuava fechada externamente.

### 9.3 — Causa raiz: Double NAT
No painel do roteador, o campo "Endereço de IP" mostrava um IP **privado** (`192.168.0.2`), não o IP público real. Isso indicou a existência de uma **ONT (aparelho de fibra óptica)** antes do roteador Wi-Fi, fazendo seu próprio NAT:
```
Internet → ONT (operadora) [IP público] → Roteador Wi-Fi [IP privado] → Servidor [192.168.1.5]
```
Resultado: o encaminhamento de porta configurado no roteador Wi-Fi nunca recebe tráfego, porque a ONT antes dele não repassa a conexão adiante.

### 9.4 — Opções avaliadas
1. **Colocar a ONT em modo bridge** — resolveria definitivamente, mas geralmente travado pela operadora.
2. **Port forward também na ONT** — nem sempre configurável pelo usuário final.
3. **Cloudflare Tunnel** — avaliado, mas **descartado**: no plano gratuito, TCP puro (como o do Minecraft) exige que cada jogador que for conectar também instale o `cloudflared` na própria máquina — fricção excessiva.
4. **`playit.gg`** — **opção escolhida**. Roda um agente só no servidor; jogadores conectam normalmente, sem instalar nada.

### 9.5 — Configuração do `playit.gg`
1. Criar conta em [playit.gg](https://playit.gg) e confirmar o e-mail (o agente fica em loop de reconexão até o e-mail ser verificado — status aparece como `account_status="email_not_verified"` no log até então).
2. Gerar um agente Docker no painel (`Agents` → `Setup a Docker Base Agent`), copiando a `SECRET_KEY` gerada.
3. Adicionar o serviço `playit` ao `docker-compose.yml` (ver seção 4), usando `network_mode: host` para o agente enxergar a rede da máquina diretamente.
4. Criar o túnel no painel (`Tunnels` → tipo Minecraft Java, endereço local `127.0.0.1`, porta `25565`) — o agente só sai do estado de espera (`tunnel_count=0`) depois que um túnel existe.
5. O endereço público gerado (formato `algumacoisa.playit.gg` ou similar) é o que os jogadores usam para conectar, no lugar do IP.

**Confirmado**: o túnel persiste entre reinicializações do container (`docker compose down/up`), sem precisar ser recriado toda vez.

### 9.6 — Efeito colateral do túnel: todos os jogadores aparecem com o mesmo IP
Como o `playit` conecta ao Minecraft localmente, o servidor enxerga todas as conexões vindas do IP interno do túnel/Docker (ex: `172.18.0.1`), não o IP real de cada jogador. Isso:
- Fez o `AuthMe` acusar `exceeded max number of registrations` (limite de registros por IP) — resolvido ajustando `maxRegPerIp` (ver seção 7.3).
- Faz o `AuthMe` listar múltiplos nicks como "contas do mesmo usuário" (mensagem informativa, não bloqueia o jogo):
```
[AuthMe] The user X has 4 accounts:
[AuthMe] nick1, nick2, nick3, nick4
```

**Solução oficial existente, mas não aplicada**: o `playit.gg` documenta um recurso de "Proxy Protocol" que repassa o IP real de cada jogador ao servidor. **Decisão tomada: não ativar**, porque o Proxy Protocol desabilita conexões diretas locais (inclusive testes via `localhost` na própria máquina do servidor), e o ajuste do `maxRegPerIp` já resolve o sintoma prático sem esse trade-off.

### 9.7 — Problema conhecido em aberto: instabilidade do túnel gratuito
Foi observada ao menos uma queda de conexão afetando todos os jogadores simultaneamente. Diagnóstico:
```bash
docker compose ps                              # minecraft com uptime alto e estável; playit com uptime bem menor (reiniciou)
docker compose logs playit --since 24h | grep -iE "error|reconnect"
```
Log revelou uma rajada de erros do agente `playit` no momento da queda:
```
control session expired; reconnecting reason=SessionNotSetup
ERROR ... failed to write data ... "Broken pipe"
ERROR ... failed to read data ... "Connection reset by peer"
```
Confirmado também pelo crash report do lado do cliente (Minecraft), mostrando `java.net.SocketException: Connection reset`, `Flow: CLIENTBOUND`, `Is Local: false` — a queda se originou entre o servidor/túnel e o cliente, não no computador do jogador nem no processo do Minecraft em si (que permaneceu de pé o tempo todo, `Up ... (healthy)`).

**Causa**: instabilidade inerente ao plano gratuito do `playit.gg` — a sessão de controle entre o agente e os servidores deles pode cair periodicamente, derrubando todas as conexões de jogadores que dependem daquele túnel no momento. O `restart: unless-stopped` do Docker religa o agente automaticamente, mas jogadores que estavam conectados no momento da queda precisam reconectar manualmente.

**Mitigações possíveis (não implementadas)**:
- Resolver o Double NAT na raiz (contato com a operadora pedindo IP público, ou ONT em modo bridge) eliminaria a dependência do túnel.
- Testar um plano pago do `playit.gg`, presumivelmente mais estável.
- Por ora, não há ação corretiva — o comportamento esperado é reconectar quando a queda acontecer.

---

## 10. Status final: servidor de Minecraft concluído, com problema conhecido em monitoramento ⚠️

Servidor rodando em Paper, 24/7, acessível externamente via `playit.gg` (contornando Double NAT), aceitando contas originais e piratas (`ONLINE_MODE: FALSE`). Login protegido por senha via `AuthMe`, skins customizáveis via `SkinsRestorer`, corte de árvores facilitado via `TreeFeller`. Testado de ponta a ponta com jogadores reais: conexão externa, registro/login, aplicação de skin, e concessão de poderes de administrador (OP).

**Pendência ativa**: instabilidade ocasional do túnel `playit.gg` derruba todos os jogadores simultaneamente (ver seção 9.7) — sem solução definitiva aplicada até o momento, apenas mitigações identificadas.


**Próxima etapa (fora deste documento)**: configuração do servidor de mídia Jellyfin.
