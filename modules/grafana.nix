{ config, ... }:
{
  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "0.0.0.0";
      http_port = 3000;
    };
    settings.security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
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

  networking.firewall.allowedTCPPorts = [ 3000 ];
}
