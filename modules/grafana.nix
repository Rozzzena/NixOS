{ config, pkgs, ... }:
{
  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "0.0.0.0";
      http_port = 3000;
    };
    settings.security.secret_key = "$__file{/var/lib/grafana/secret_key}";
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];
    };
  };

  systemd.services.grafana.preStart = ''
    test -f /var/lib/grafana/secret_key || ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/grafana/secret_key
    chmod 600 /var/lib/grafana/secret_key
  '';

  networking.firewall.allowedTCPPorts = [ 3000 ];
}
