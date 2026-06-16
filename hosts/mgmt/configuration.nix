# mgmt server — DNS filtering, reverse proxy, SIEM, RMM, monitoring
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base.nix
    ./modules/step-ca.nix
    ./modules/adguard.nix
    ./modules/nginx.nix
    ./modules/monitoring.nix
    ./modules/wazuh.nix
    ./modules/tactical-rmm.nix
    ./modules/netbox.nix
    ./modules/forgejo.nix
    ./modules/ntopng.nix
    ./modules/harmonia.nix
    ./modules/netboot.nix
    ./modules/snipe-it.nix
    ./modules/backup.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  networking.hostName = "mgmt";
  networking.networkmanager.enable = true;

  # This box serves DNS for the whole LAN — it must keep 192.168.1.222.
  # Preferred: add a DHCP reservation on the router. Alternatively go static:
  # networking.networkmanager.enable = lib.mkForce false;
  # networking.interfaces.eno1.ipv4.addresses = [ { address = "192.168.1.222"; prefixLength = 24; } ];
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "127.0.0.1" "9.9.9.9" ];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.mgmt = {
    isNormalUser = true;
    description = "mgmt";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

  # --- Wazuh agent — enroll mgmt itself (agent 007) into its own SIEM ---------
  # mgmt doesn't take common.nix, so it wires sops directly here: decrypt the
  # manager-issued client.keys (secrets/mgmt.yaml) at activation via this host's
  # SSH host key, then the shared wazuh-agent module installs it (pre-shared-key
  # mode, no <enrollment>). Reports FIM (/etc) + rootcheck + SCA to the manager
  # on 192.168.1.222:1514 (this same box).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.wazuh_client_keys = {
    sopsFile = ../../secrets/mgmt.yaml;
    owner = "wazuh";
  };
  alcove.wazuhAgent = {
    enable = true;
    clientKeysFile = config.sops.secrets.wazuh_client_keys.path;
  };

  system.stateVersion = "25.11";
}
