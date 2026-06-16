# hosts/media/configuration.nix
#
# media — *arr stack + Jellyfin server (SATA 477G). The core stack is declared
# in ./arr.nix (carried verbatim from the live box); the NAS is NFS-mounted there.
#
# Adopted from the channel-based install. Shared baseline (key-only SSH, nftables
# firewall, the `deploy` user, sops, flakes, zsh) comes from ../../modules/common.nix.
#
# Enabling that firewall is SAFE here: every *arr service in arr.nix already sets
# `openFirewall = true`, so the right ports (8096/8920, 7878, 8989, 9696, 6767,
# 6789, + Jellyfin discovery) open automatically — they were no-ops while the
# stock install left the firewall off. (NFS to the NAS is outbound, unaffected.)
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./arr.nix
    ../../modules/media-hardening.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "media";
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Headless server — the GNOME desktop from the original install is stripped.
  # The *arr stack + Jellyfin are reached over the network, not a local screen.

  # --- User ------------------------------------------------------------------
  users.users.media = {
    isNormalUser = true;
    description = "media";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ neovim ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # --- Wazuh agent (pre-shared-key enrollment) -------------------------------
  # Same pattern proven on playground: the manager-issued client.keys line is
  # held in sops (secrets/media.yaml → agent 005), decrypted at activation via
  # this host's SSH host key; the module installs it directly and skips
  # <enrollment>. Reports FIM (/etc) + rootcheck + SCA to the SIEM on mgmt.
  sops.secrets.wazuh_client_keys = {
    sopsFile = ../../secrets/media.yaml;
    owner = "wazuh";
  };
  alcove.wazuhAgent = {
    enable = true;
    clientKeysFile = config.sops.secrets.wazuh_client_keys.path;
  };

  system.stateVersion = "25.11";
}
