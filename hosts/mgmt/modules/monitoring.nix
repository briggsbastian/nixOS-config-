# Metrics + uptime + landing page: Prometheus scrapes node_exporter,
# Grafana visualizes, Uptime Kuma probes the services, Homepage links it
# all together at https://mgmt.lan.
{ ... }:

{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      enabledCollectors = [ "systemd" ];
    };
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "127.0.0.1";
      http_port = 3002;
      domain = "grafana.mgmt.lan";
      root_url = "https://grafana.mgmt.lan/";
    };
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }
    ];
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "mgmt.lan,home.mgmt.lan";
    settings.title = "mgmt";
    services = [
      {
        "Security" = [
          { "Wazuh SIEM" = {
              href = "https://siem.mgmt.lan";
              description = "SIEM — agents, FIM, vulnerability detection";
            }; }
          { "AdGuard Home" = {
              href = "https://adguard.mgmt.lan";
              description = "DNS filtering for the LAN";
            }; }
        ];
      }
      {
        "Management" = [
          { "Tactical RMM" = {
              href = "https://rmm.mgmt.lan";
              description = "Remote monitoring & management";
            }; }
          { "Uptime Kuma" = {
              href = "https://status.mgmt.lan";
              description = "Service uptime monitoring";
            }; }
          { "Grafana" = {
              href = "https://grafana.mgmt.lan";
              description = "Metrics dashboards";
            }; }
          { "ntopng" = {
              href = "https://ntop.mgmt.lan";
              description = "Network traffic analysis";
            }; }
        ];
      }
      {
        "Infrastructure" = [
          { "NetBox" = {
              href = "https://netbox.mgmt.lan";
              description = "IPAM & network documentation";
            }; }
          { "Forgejo" = {
              href = "https://git.mgmt.lan";
              description = "Git hosting";
            }; }
          { "Snipe-IT" = {
              href = "https://assets.mgmt.lan";
              description = "Asset inventory";
            }; }
          { "Root CA cert" = {
              href = "https://ca.mgmt.lan/root.crt";
              description = "Install on devices to trust *.mgmt.lan";
            }; }
          { "Nix cache pubkey" = {
              href = "https://cache.mgmt.lan/pubkey";
              description = "Binary cache at https://cache.mgmt.lan";
            }; }
        ];
      }
      {
        # Direct IP:port — these run on the media/lab hosts, not behind mgmt's nginx.
        "Media" = [
          { "Jellyfin" = {
              href = "http://192.168.1.189:8096";
              description = "Media streaming";
            }; }
          { "Radarr" = {
              href = "http://192.168.1.189:7878";
              description = "Movies";
            }; }
          { "Sonarr" = {
              href = "http://192.168.1.189:8989";
              description = "TV shows";
            }; }
          { "Prowlarr" = {
              href = "http://192.168.1.189:9696";
              description = "Indexer manager";
            }; }
          { "Bazarr" = {
              href = "http://192.168.1.189:6767";
              description = "Subtitles";
            }; }
          { "NZBGet" = {
              href = "http://192.168.1.189:6789";
              description = "Usenet downloader";
            }; }
        ];
      }
      {
        "Lab" = [
          { "Guacamole" = {
              href = "http://192.168.1.217:8080/guacamole/";
              description = "Browser remote-desktop gateway (RDP/VNC/SSH)";
            }; }
        ];
      }
    ];
  };
}
