# Arr media stack: Prowlarr, Sonarr, Radarr, Bazarr, Jellyfin, NZBGet
#
# Carried verbatim from the live media box (/etc/nixos/arr.nix). All media data
# lives on the NAS (192.168.1.213), NFS-mounted at /mnt/media. Services run as
# the "media" user and use only that mount:
#
#   /mnt/media/                    (NAS: /srv/media, 916G)
#   ├── data/
#   │   └── nzbget/
#   │       ├── intermediate/      # NZBGet working dir
#   │       ├── completed/         # finished downloads (tv/movies categories)
#   │       ├── nzb/  queue/  tmp/
#   └── Media/
#       ├── TV/                    # Sonarr library / Jellyfin "Shows"
#       ├── Movies/                # Radarr library / Jellyfin "Movies"
#       ├── Books/  Audiobooks/  Comics/  Sports/

{ config, lib, pkgs, ... }:

{
  # ---------- NAS mount ----------
  boot.supportedFilesystems = [ "nfs" ];

  fileSystems."/mnt/media" = {
    device = "192.168.1.213:/srv/media";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noatime"
      # don't hang boot if the NAS is down; mount on first access
      "nofail"
      "x-systemd.automount"
      "_netdev"
    ];
  };

  # ---------- services ----------
  services.prowlarr = {
    enable = true;
    openFirewall = true; # 9696
  };

  services.sonarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 8989
  };

  services.radarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 7878
  };

  services.bazarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 6767
  };

  services.jellyfin = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 8096 (http), 8920 (https), discovery ports
  };

  services.nzbget = {
    enable = true;
    user = "media";
    group = "users";
    settings = {
      # reuse the existing download tree on the NAS
      MainDir = "/mnt/media/data/nzbget";
      DestDir = "/mnt/media/data/nzbget/completed";
      InterDir = "/mnt/media/data/nzbget/intermediate";
      NzbDir = "/mnt/media/data/nzbget/nzb";
      QueueDir = "/mnt/media/data/nzbget/queue";
      TempDir = "/mnt/media/data/nzbget/tmp";
      ControlIP = "0.0.0.0";
      ControlPort = 6789;
      "Category1.Name" = "tv";
      "Category1.DestDir" = "/mnt/media/data/nzbget/completed/tv";
      "Category2.Name" = "movies";
      "Category2.DestDir" = "/mnt/media/data/nzbget/completed/movies";
    };
  };

  # NZBGet's module has no openFirewall option
  networking.firewall.allowedTCPPorts = [ 6789 ];

  # Every service that touches media data must wait for the NAS mount;
  # arrs start after the download client and indexer
  systemd.services = {
    nzbget.unitConfig.RequiresMountsFor = [ "/mnt/media" ];
    jellyfin.unitConfig.RequiresMountsFor = [ "/mnt/media" ];
    sonarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [ "nzbget.service" "prowlarr.service" ];
    };
    radarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [ "nzbget.service" "prowlarr.service" ];
    };
    bazarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [ "sonarr.service" "radarr.service" ];
    };
  };
}
