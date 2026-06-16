# AdGuard Home: LAN-wide DNS filtering + answers *.mgmt.lan with this host
# so nginx can route by name. Web UI on localhost:3000, reached via
# https://adguard.mgmt.lan through nginx.
#
# Settings below are the *initial* config (mutableSettings = true): once the
# service has started, manage it from the web UI.
{ ... }:

{
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    mutableSettings = true;
    settings = {
      # Admin login is intentionally NOT declared here — a bcrypt hash in a public
      # repo is offline-crackable. With mutableSettings, AdGuard keeps auth in its
      # own config: set/rotate the admin user in the web UI. The seed hash is kept
      # in sops (secrets/mgmt.yaml: adguard_password), out of the tree.
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "9.9.9.9"
          "1.1.1.1"
        ];
        bootstrap_dns = [ "9.9.9.9" "1.1.1.1" ];
      };
      # "enabled" must be explicit — AdGuard defaults a missing field to false
      filtering.rewrites = [
        { domain = "mgmt.lan";   answer = "192.168.1.222"; enabled = true; }
        { domain = "*.mgmt.lan"; answer = "192.168.1.222"; enabled = true; }
      ];
      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
      ];
    };
  };
}
