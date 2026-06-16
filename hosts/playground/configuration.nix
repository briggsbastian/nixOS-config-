# hosts/playground/configuration.nix
#
# playground — AMD box / NVMe 465G. Role: security lab host (future libvirt host for
# the Kali/Parrot/REMnux/FlareVM lab) + Guacamole remote-desktop gateway.
#
# Adopted from the channel-based install. Shared baseline (key-only SSH, nftables
# firewall with 22, the `deploy` user, sops, flakes, zsh) comes from
# ../../modules/common.nix.
#
# NOTE: Guacamole runs as an IMPERATIVE per-user systemd service (Tomcat 9 + guacd).
# It currently lives in /home/secvm/guacamole under the OLD `secvm` user — when this
# box is bootstrapped to the renamed `playground` user, migrate it to
# /home/playground/guacamole (or just re-set it up — it has no VM connections yet).
# It SHOULD be made declarative (services.guacamole-server / -client) eventually.
# Port 8080 is kept open below so it stays reachable once the firewall comes on.
#
# The libvirt lab is not built yet (libvirtd/virsh/VMs absent today) — that work
# is tracked in "Project 1 - Nixify the Lab".
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./libvirt.nix
    ./bridge.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "playground";
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Headless — the GNOME desktop from the original install is stripped. Remote
  # access is over SSH + Guacamole (the web gateway on :8080, an imperative
  # user service that doesn't need a local X session).

  # --- User ------------------------------------------------------------------
  users.users.playground = {
    isNormalUser = true;
    description = "playground";
    extraGroups = [ "wheel" ]; # networkmanager group is gone once NM is off (see bridge.nix)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # Guacamole web UI (imperative user service on :8080) — keep it LAN-reachable
  # now that common.nix turns the firewall on. Merges with common's [ 22 ].
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # --- Wazuh agent (pre-shared-key enrollment) -------------------------------
  # The manager-issued client.keys line (`004 playground any <key>`) is held in
  # sops and decrypted to /run/secrets at activation via this host's SSH host
  # key. The agent module installs it directly and skips <enrollment>, avoiding
  # the self-registration key-persistence race that parked this earlier.
  sops.secrets.wazuh_client_keys = {
    sopsFile = ../../secrets/playground.yaml;
    owner = "wazuh";
  };
  alcove.wazuhAgent = {
    enable = true;
    clientKeysFile = config.sops.secrets.wazuh_client_keys.path;
  };

  system.stateVersion = "25.11";
}
