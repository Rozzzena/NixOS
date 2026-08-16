{ config, ... }:
{
  services.prometheus = {
    enable = true;
    port = 9090;

    exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" ];
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ]; }];
      }
      {
        job_name = "cadvisor";
        static_configs = [{ targets = [ "localhost:${toString config.services.cadvisor.port}" ]; }];
      }
    ];
  };

  services.cadvisor = {
    enable = true;
    port = 8080;
  };
}
