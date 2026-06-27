# Metrics + uptime + landing page: Prometheus scrapes node_exporter,
# Grafana visualizes, Uptime Kuma probes the services, Homepage links it
# all together at https://mgmt.lan.
{ lib, ... }:

let
  # Scrape targets come from the same host map flake.nix uses for Colmena
  # (fleet-hosts.nix), so the deploy list and the metrics list can't drift.
  # `scrape = true` hosts only; mgmt is added separately below because its own
  # exporter binds 127.0.0.1, so it's scraped over localhost, not by IP.
  fleetHosts = import ../../../../fleet-hosts.nix;
  scrapedHosts = lib.filterAttrs (_: h: h.scrape) fleetHosts;
in
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
    # One "node" job covering the whole fleet. instance = hostname (not ip:port)
    # keeps labels low-cardinality and makes alerts read "node media down". mgmt
    # is scraped over localhost; everyone else by IP, derived from fleet-hosts.nix
    # so this list never drifts from the Colmena host map. cloud1 is absent
    # (scrape = false) until it has a private path to mgmt.
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:9100" ];
            labels.instance = "mgmt";
          }
        ]
        ++ lib.mapAttrsToList (name: h: {
          targets = [ "${h.ip}:9100" ];
          labels.instance = name;
        }) scrapedHosts;
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
    settings = {
      title = "mgmt";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      useEqualHeights = true;
      hideVersion = true;
      layout = {
        Security       = { style = "row"; columns = 2; };
        Observability  = { style = "row"; columns = 3; };
        Infrastructure = { style = "row"; columns = 3; };
        Media          = { style = "row"; columns = 3; };
        Lab            = { style = "row"; columns = 2; };
      };
    };
    # header bar: live host resources + a clock
    widgets = [
      {
        resources = {
          label = "mgmt";
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = { dateStyle = "long"; timeStyle = "short"; hour12 = true; };
        };
      }
    ];
    services = [
      {
        "Security" = [
          { "AdGuard Home" = {
              href = "https://adguard.mgmt.lan";
              description = "DNS filtering for the LAN";
            }; }
        ];
      }
      {
        "Observability" = [
          { "Grafana" = {
              href = "https://grafana.mgmt.lan";
              description = "Metrics + log dashboards (Prometheus + Loki)";
            }; }
          { "Logs (Explore)" = {
              href = "https://grafana.mgmt.lan/explore";
              description = "Search the fleet's journals in Loki";
            }; }
          { "Alertmanager" = {
              href = "https://alerts.mgmt.lan";
              description = "Fired alerts - view, silence, routing";
            }; }
          { "ntfy" = {
              href = "https://ntfy.mgmt.lan";
              description = "Push alerts - subscribe to /homelab-alerts";
            }; }
          { "Uptime Kuma" = {
              href = "https://status.mgmt.lan";
              description = "Service uptime monitoring";
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
        # Direct IP:port - these run on the media/lab hosts, not behind mgmt's nginx.
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
          { "Kavita" = {
              href = "http://192.168.1.189:5000";
              description = "Books, comics & manga";
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
