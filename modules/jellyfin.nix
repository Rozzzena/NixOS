#Jellyfin + Seerr + GPU

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

  #
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
