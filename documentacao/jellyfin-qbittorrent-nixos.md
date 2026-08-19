# Servidor de Mídia NixOS — Jellyfin + qBittorrent

Documentação da configuração declarativa de um servidor de mídia caseiro no NixOS, combinando qBittorrent (download/seed) e Jellyfin (streaming), com aceleração de hardware via NVIDIA GTX 1050 Ti.

---

## Visão geral da arquitetura

```
nixos-config/
├── configuration.nix        # config principal, importa os módulos abaixo
├── flake.nix                 # entrada do flake (nixosConfigurations."nixos")
└── modules/
    ├── torrent.nix            # qBittorrent
    └── jellyfin.nix           # Jellyfin + Seerr + driver NVIDIA
```

**Fluxo de dados:**

```
qBittorrent (categorias com save path automático) → biblioteca do Jellyfin
```

Cada categoria no qBittorrent já aponta pro diretório correto de destino (`/mnt/media/movies`, `/mnt/media/series`, etc), então o próprio cliente de torrent direciona o arquivo pra pasta certa sem precisar de curadoria manual (mover/hardlink) depois do download. A escolha de qual torrent baixar continua manual, por preferência — ver seção 5.

---

## 1. qBittorrent (`modules/torrent.nix`)

```nix
# Qbittorrent
{
  services.qbittorrent = {
    enable = true;
    webuiPort = 8081;       # 8080 colide com o cadvisor já rodando no sistema
    torrentingPort = 6881;
    openFirewall = false;
    profileDir = "/var/lib/qbittorrent";
    user = "qbittorrent";
    group = "media";

    serverConfig = {
      Preferences = {
        Downloads = {
          SavePath = "/mnt/torrents/completed";
          TempPath = "/mnt/torrents/incomplete";
          TempPathEnabled = true;
        };
      };
    };
  };

  users.groups.media = {};
  users.users.qbittorrent.extraGroups = [ "media" ];

  networking.firewall.allowedTCPPorts = [ 8081 6881 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
```

### Pontos-chave

| Item | Valor | Motivo |
|---|---|---|
| `webuiPort` | `8081` | `8080` estava em conflito com o `cadvisor` |
| `torrentingPort` | `6881` | porta padrão de tráfego BitTorrent (TCP+UDP) |
| `openFirewall` | `false` | acesso via SSH tunnel ou rede local restrita, não exposto |
| `group` | `media` | compartilhado com o usuário `jellyfin`, pra permitir leitura cruzada de pastas |

### Categorias com save path (organização automática)

Configuradas direto na WebUI (Tools → Options → Downloads → Categorias), cada categoria tem seu próprio diretório de destino, por exemplo:

| Categoria | Save path |
|---|---|
| `movies` | `/mnt/media/movies` |
| `series` | `/mnt/media/series` |
| `games` | `/mnt/media/games` |
| `comics` | `/mnt/media/comics` |

Ao adicionar um torrent, basta escolher a categoria correspondente — o arquivo já cai direto no destino certo, sem passo manual de mover depois.

---

## 2. Jellyfin + Seerr + GPU (`modules/jellyfin.nix`)

```nix
# Jellyfin + Seerr + GPU
{ config, pkgs, ... }:
{
  services.jellyfin = {
    enable = true;
    group = "media";
    user = "jellyfin";
    openFirewall = true;

    hardwareAcceleration = {
      enable = true;
      type = "nvenc";
      device = "/dev/dri/renderD128";
    };
  };

  # Driver proprietário da NVIDIA
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    modesetting.enable = true;
    open = false;
  };

  # Libera os dispositivos NVIDIA para o serviço systemd do Jellyfin
  # (ver seção 4 — sem isso, o hardening padrão bloqueia o acesso à GPU)
  systemd.services.jellyfin.serviceConfig = {
    DeviceAllow = [
      "/dev/dri/renderD128 rw"
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
    ];
  };

  hardware.graphics.enable = true;

  users.users.jellyfin.extraGroups = [ "video" "render" "media" ];

  services.seerr = {
    enable = true;
    openFirewall = false;
  };
}
```

### Por que o cabeçalho `{ config, pkgs, ... }:`

Diferente do `torrent.nix`, esse arquivo referencia `config.boot.kernelPackages...`. Um arquivo `.nix` só tem acesso a `config`/`pkgs` se for declarado como **função de módulo** (assinatura antes do corpo). Sem isso, o build falha com `undefined variable 'config'`.

---

## 3. O caso específico da GTX 1050 Ti (driver NVIDIA)

### O problema

A NVIDIA descontinuou suporte a GPUs Maxwell/Pascal (GTX 9xx/10xx, incluindo a 1050 Ti) nas branches "modernas" do driver (`stable`/`production`, atualmente na faixa 595.x+). Usando o pacote padrão:

```nix
hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
```

O módulo carrega, mas ignora a placa:

```
NVRM: The NVIDIA NVIDIA GeForce GTX 1050 Ti GPU installed in this system is
NVRM: supported through the NVIDIA 580.xx Legacy drivers.
NVRM: No NVIDIA GPU found.
```

E `nvidia-smi` retorna:
```
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
```

### A solução

Fixar o pacote na branch legacy correta:

```nix
hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
```

Última branch com suporte a Maxwell → Volta (GTX 9xx até GTX 10xx, e Titan V). Confirmado funcionando com driver `580.173.02`.

> ⚠️ Em algumas revisões do canal `unstable`, `legacy_580` pode não estar disponível ainda (bug conhecido no nixpkgs). Se aparecer `attribute 'legacy_580' missing`, tentar `legacy_535` como alternativa — também cobre Pascal.

### `open = false` — por quê

Os drivers de kernel "open source" da NVIDIA (`hardware.nvidia.open = true`) só têm suporte a partir da geração Turing (RTX 20xx+). Pascal precisa do módulo de kernel proprietário fechado.

### `type = "nvenc"` — não confundir com VAAPI

NVIDIA não usa VA-API (isso é Intel/AMD) — usa NVENC/NVDEC via driver proprietário + CUDA.

---

## 4. O problema do systemd bloqueando a GPU (hardening excessivo)

Esse foi o obstáculo mais sutil de todo o setup, porque **todos os sinais "óbvios" indicavam que estava tudo certo**:

- `nvidia-smi` funcionando normalmente ✅
- `sudo -u jellyfin nvidia-smi` funcionando ✅ (confirma que não era permissão Unix comum)
- Dispositivos `/dev/nvidia*` com permissão `rw-rw-rw-` (mundialmente acessíveis) ✅
- Driver carregado, `hardwareAcceleration.type = "nvenc"` configurado corretamente ✅

Mesmo assim, ao tentar transcodificar, o log do Jellyfin mostrava:

```
[AVHWDeviceContext] cu->cuInit(0) failed -> CUDA_ERROR_NO_DEVICE: no CUDA-capable device is detected
Device creation failed: -542398533.
```

### Causa real

O módulo `services.jellyfin` do NixOS roda o serviço com **hardening de systemd** (isolamento via cgroups, incluindo a diretiva `DeviceAllow`, que funciona como uma allowlist de dispositivos que o processo pode acessar). O módulo libera automaticamente `/dev/dri/*` — suficiente para VAAPI (Intel/AMD) — mas **não libera os dispositivos `/dev/nvidia*`** que o CUDA/NVENC precisa.

Resultado: o processo `ffmpeg` iniciado pelo Jellyfin literalmente não conseguia "ver" a GPU, mesmo ela estando acessível para qualquer outro processo do sistema (por isso `sudo -u jellyfin nvidia-smi`, rodado fora do systemd, funcionava normalmente — mas dentro do serviço, não).

Esse é um problema documentado em várias issues abertas no repositório do nixpkgs, sem correção definitiva no módulo até o momento desta documentação.

### A solução

Liberar explicitamente os dispositivos NVIDIA para o serviço:

```nix
systemd.services.jellyfin.serviceConfig = {
  DeviceAllow = [
    "/dev/dri/renderD128 rw"
    "/dev/nvidia0 rw"
    "/dev/nvidiactl rw"
    "/dev/nvidia-modeset rw"
    "/dev/nvidia-uvm rw"
    "/dev/nvidia-uvm-tools rw"
  ];
};
```

O NixOS **mescla** essa lista com a já existente no módulo — não é preciso desabilitar o hardening por completo, só estender a allowlist.

### Como validar que funcionou

1. Reiniciar o serviço depois do rebuild: `sudo systemctl restart jellyfin`
2. Conferir se a config foi aplicada de fato (não só escrita no arquivo):
   ```bash
   systemctl show jellyfin -p DeviceAllow
   systemctl show jellyfin -p PrivateDevices   # deve ser "no"
   ```
3. Forçar uma transcodificação (baixar a qualidade manualmente no player) e observar a GPU em tempo real:
   ```bash
   watch -n 1 nvidia-smi
   ```
   Confirmação de sucesso: um processo `ffmpeg` aparece na tabela **Processes**, junto de `GPU-Util` saindo de `0%` e o estado de energia mudando de `P8` (idle) para `P0` (ativo).

---

## 5. Decisão: não adotar a stack *arr (por enquanto)

Considerada, mas descartada por dois motivos específicos — vale registrar para não reabrir a dúvida no futuro:

1. **Espaço em disco limitado (1TB)**: Sonarr, em particular, tende a consumir espaço rápido se os perfis de qualidade não forem bem travados (ex: monitorar uma série inteira sem limite de qualidade pode facilmente encher o disco). Com apenas 1TB disponível, o controle manual atual evita esse risco.
2. **Preferência por escolher torrents manualmente**: a curadoria "à dedo" de releases (grupo de encode, tamanho, confiabilidade da fonte) é uma parte do processo que é feita intencionalmente, não um incômodo a ser automatizado. Sonarr/Radarr existem justamente pra remover essa etapa — o que, nesse caso, remove algo que se quer manter.

**Revisitar essa decisão faz sentido se**: o espaço de armazenamento crescer significativamente (upgrade de disco), ou se a curadoria manual começar a virar um fardo em vez de preferência.

---

## 6. Estrutura de pastas e permissões

```
/mnt/media/
├── movies/
├── series/
├── games/
└── comics/
```

Todas com dono `root`/`rozena` (conforme criação) e grupo `media`, permissão `rwx` para o grupo — assim tanto `jellyfin` quanto `qbittorrent` (ambos membros do grupo `media`) conseguem ler e escrever.

```bash
sudo mkdir -p /mnt/media/{movies,series,games,comics}
sudo chown -R :media /mnt/media/movies /mnt/media/series /mnt/media/games /mnt/media/comics
sudo chmod -R g+rwX /mnt/media/movies /mnt/media/series /mnt/media/games /mnt/media/comics
```

### ⚠️ Armadilha: pastas dentro de `/home`

Se uma biblioteca de mídia ficar dentro de `/home/<usuário>/...`, o Jellyfin pode falhar com `The path could not be found` mesmo com a pasta existindo e dono/grupo corretos — porque `/home/<usuário>` normalmente tem permissão `750`/`700`, bloqueando o usuário `jellyfin` de **atravessar** o caminho até a subpasta.

**Diagnóstico:**
```bash
sudo -u jellyfin ls /home/usuario/Videos/Movies
namei -l /home/usuario/Videos/Movies   # mostra a permissão de cada nível do caminho
```

**Soluções:**
- Abrir passagem nos diretórios intermediários (`chmod o+x`), ou
- (Recomendado para servidor) Manter bibliotecas fora do `/home`, em `/mnt/media/...`

---

## 7. Fluxo de trabalho com flakes

Esse setup usa **flakes**, não canais tradicionais. Diferenças importantes:

- Comando de rebuild: `sudo nixos-rebuild switch --flake .#nixos` (não apenas `nixos-rebuild switch`)
- **Arquivos precisam estar rastreados pelo Git** (`git add`) antes do build — mesmo sem commitar, um `git add` já é suficiente pro Nix enxergar o arquivo. Erro típico se esquecer:
  ```
  error: Path 'modules/jellyfin.nix' in the repository "..." is not tracked by Git.
  ```
- Validar sintaxe antes do rebuild completo (mais rápido que esperar o build inteiro):
  ```bash
  nix-instantiate --parse modules/jellyfin.nix > /dev/null
  ```
- Rollback em caso de problema após o switch:
  ```bash
  sudo nixos-rebuild switch --rollback
  ```

---

## 8. Troubleshooting — erros encontrados nesse setup

| Erro | Causa | Solução |
|---|---|---|
| `error: syntax error, unexpected ';', expecting end of file` | Chave `}` sobrando/faltando em algum bloco | Conferir balanceamento de `{ }` no arquivo indicado |
| `error: syntax error, unexpected ':'` | Cabeçalho de função (`{ config, pkgs, ... }:`) inserido no meio do arquivo em vez de no topo | Mover o cabeçalho pra primeira linha do arquivo |
| `has conflicting definition values` | Mesma opção definida em dois arquivos diferentes (ex: `openFirewall` tanto no módulo novo quanto sobrando no `configuration.nix` antigo) | Remover a definição duplicada, manter uma única fonte de verdade por serviço |
| `NVRM: No NVIDIA GPU found` / `nvidia-smi` falha | Driver `stable`/`production` não suporta mais Pascal | Trocar para `nvidiaPackages.legacy_580` |
| `CUDA_ERROR_NO_DEVICE` só dentro do serviço Jellyfin (mas `nvidia-smi` funciona manualmente) | Hardening do systemd (`DeviceAllow`) não libera `/dev/nvidia*` por padrão | Adicionar `systemd.services.jellyfin.serviceConfig.DeviceAllow` com os dispositivos NVIDIA — ver seção 4 |
| `bind: address already in use` (ex: `cadvisor.service`) | Duas portas configuradas com o mesmo número | Trocar a porta de um dos serviços |
| `The path could not be found` no Jellyfin | Pasta de mídia dentro de `/home`, sem permissão de travessia pro usuário `jellyfin` | `chmod o+x` nos diretórios intermediários, ou mover pra fora de `/home` |
| `Path ... is not tracked by Git` | Flake não enxerga arquivos novos sem `git add` | `git add <arquivo>` antes do rebuild |

---

## 9. Comandos úteis de referência

```bash
# Validar sintaxe de um arquivo .nix isoladamente
nix-instantiate --parse modules/jellyfin.nix > /dev/null

# Simular o build sem aplicar
sudo nixos-rebuild dry-build --flake .#nixos

# Aplicar de fato
sudo nixos-rebuild switch --flake .#nixos

# Confirmar driver NVIDIA carregado
nvidia-smi
lsmod | grep nvidia

# Ver logs do kernel relacionados à GPU
journalctl -b | grep -i nvidia

# Status dos serviços
systemctl status jellyfin qbittorrent seerr

# Conferir config de hardening realmente aplicada ao serviço
systemctl show jellyfin -p DeviceAllow
systemctl show jellyfin -p PrivateDevices

# Observar a GPU em tempo real durante um teste de transcodificação
watch -n 1 nvidia-smi

# Portas escutando
sudo ss -tlnp | grep -E "8096|8081|5055"

# Testar acesso HTTP local
curl -I http://localhost:8096
```

---

## 10. Pendências / próximos passos

- [x] Definir estrutura final de pastas de mídia (`/mnt/media/{movies,series,games,comics}`)
- [x] Organizar curadoria de downloads via categorias no qBittorrent (save path automático)
- [x] Validar NVENC funcionando de fato na transcodificação (GPU confirmada em uso via `nvidia-smi`)
- [x] Decidir sobre a stack *arr — não adotar por enquanto (ver seção 5)
- [ ] Decidir se `services.seerr` fica exposto na rede (`openFirewall`) ou só acesso local/VPN
- [ ] Commitar as mudanças no Git (`git add -A && git commit -m "..."`) para ter histórico de versões
