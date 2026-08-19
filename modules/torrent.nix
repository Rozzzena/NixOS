# Qbittorrent
{
  services.qbittorrent = {
    enable = true;
    webuiPort = 8081;
    torrentingPort = 6881;
    openFirewall = false;
    profileDir = "/var/lib/qbittorrent";
    user = "qbittorrent";
    group = "media";

    # path de download
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

  # Portas usadas
  networking.firewall.allowedTCPPorts = [ 8081 6881 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
}
