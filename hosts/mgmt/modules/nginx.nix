# Reverse proxy: one TLS entry point routing *.mgmt.lan hostnames to the
# services, which all listen on localhost. Certs come from the private
# step-ca via ACME and renew automatically (see step-ca.nix).
# (Snipe-IT's vhost is declared by its own module in snipe-it.nix.)
{ lib, ... }:

let
  proxy = upstream: extra:
    lib.recursiveUpdate
      {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = true;
        };
      }
      extra;

  # Tactical RMM's bundled nginx terminates TLS itself (self-signed,
  # never seen by clients), so these vhosts re-encrypt to it. Long read
  # timeout keeps agent and mesh websockets alive.
  trmm = proxy "https://127.0.0.1:4443" {
    locations."/".extraConfig = ''
      proxy_ssl_verify off;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    '';
  };
in
{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    clientMaxBodySize = "500m";

    virtualHosts = {
      "mgmt.lan" = proxy "http://127.0.0.1:8082" { default = true; };
      "home.mgmt.lan" = proxy "http://127.0.0.1:8082" { };
      "adguard.mgmt.lan" = proxy "http://127.0.0.1:3000" { };
      "status.mgmt.lan" = proxy "http://127.0.0.1:3001" { };
      "grafana.mgmt.lan" = proxy "http://127.0.0.1:3002" { };
      "ntop.mgmt.lan" = proxy "http://127.0.0.1:3003" { };
      "git.mgmt.lan" = proxy "http://127.0.0.1:3004" { };
      "cache.mgmt.lan" = proxy "http://127.0.0.1:5000" {
        # binary cache pubkey for client configs
        locations."= /pubkey".alias = "/var/lib/mgmt-public/harmonia.pub";
      };
      "netbox.mgmt.lan" = proxy "http://127.0.0.1:8001" {
        locations."/static/".alias = "/var/lib/netbox/static/";
      };
      "siem.mgmt.lan" = proxy "https://127.0.0.1:5601" {
        locations."/".extraConfig = "proxy_ssl_verify off;";
      };
      "ca.mgmt.lan" = proxy "https://127.0.0.1:8443" {
        locations."/".extraConfig = "proxy_ssl_verify off;";
        # the root cert devices need to trust
        locations."= /root.crt".alias = "/var/lib/mgmt-public/root_ca.crt";
      };
      "rmm.mgmt.lan" = trmm;
      "api.mgmt.lan" = trmm;
      "mesh.mgmt.lan" = trmm;
    };
  };
}
