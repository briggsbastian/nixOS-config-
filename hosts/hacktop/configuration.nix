# hosts/hacktop/configuration.nix
#
# hacktop — 11th-gen i / 32 GB / 931 GB NVMe laptop.
# Role: staging + CI/build host for the fleet (Project 1 → Project 5 runner).
#
# Adopted from the stock installer image (NixOS 25.11) rather than re-imaged,
# so this converges the existing box. Shared baseline (SSH key-only, nftables
# firewall with 22 open, flakes, zsh, base tools) comes from ../../modules/common.nix.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader (matches the live install: systemd-boot on the ESP).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hacktop";

  # Wi-Fi-only again (wlp0s20f3 = 192.168.1.26); Colmena targets .26.
  #
  # The USB Ethernet dongle (enp0s13f0u1 = .198) was
  # UNPLUGGED 2026-06-15: its UniFi switch port wasn't forwarding (link up, TX
  # only, no ARP reply from the gateway), so it black-holed the default route AND
  # — being a 2nd NIC on the SAME /24 as Wi-Fi — caused ARP flux that poisoned
  # .26 and knocked the box offline. Pulling it restored clean Wi-Fi WAN.
  # TODO (to make wired primary): fix that switch port / try another port+cable,
  # confirm the dongle pings the gateway AND the internet, set a UniFi DHCP
  # reservation (the dongle's MAC → .198), then either go WIRED-ONLY (turn Wi-Fi
  # autoconnect off — this is a server) or add arp_ignore=1/arp_announce=2 so the
  # two same-subnet NICs don't flux. Until then, do NOT make Ethernet primary.
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # --- User ------------------------------------------------------------------
  # Login user matches the box + ~/.ssh/config alias. Key-only (see common.nix);
  # this is THIS desktop's key, so `ssh hacktop@<hacktop-lan-ip>` and Colmena keep
  # working after the switch. wheel sudo still needs a password (set with passwd).
  users.users.hacktop = {
    isNormalUser = true;
    description = "hacktop";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # --- Staging / CI build tooling -------------------------------------------
  # Just enough to stage fleet configs and drive builds by hand for now; the
  # actual self-hosted runner is stood up in Project 5.
  environment.systemPackages = with pkgs; [
    nix-output-monitor   # nom — readable build output when staging configs
    nixos-rebuild
    jq
    just
  ];

  # Roomier Nix builder: this box exists to build/stage for the rest of the
  # fleet, so let it use its cores and keep more history before GC.
  nix.settings.max-jobs = "auto";
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # --- Secrets (sops-nix) ----------------------------------------------------
  # Smoke-test secret proving the sops-nix → Colmena → /run/secrets pipeline.
  # Decrypts at activation via this host's SSH host key (see common.nix). The
  # owner is set to `hacktop` only so it's verifiable without root — real
  # secrets get their service's user. Replace demo_secret with real ones (CI
  # runner token, cache signing key, …) as they appear.
  sops.defaultSopsFile = ../../secrets/hacktop.yaml;
  sops.secrets.demo_secret = {
    owner = "hacktop";
  };

  # --- Wazuh agent (pre-shared-key enrollment) — agent 006 -------------------
  # client.keys lives in secrets/hacktop.yaml (the defaultSopsFile above),
  # decrypted at activation via this host's SSH host key. Purely additive — a
  # new user + service, nothing touching NetworkManager (safe over Wi-Fi).
  sops.secrets.wazuh_client_keys = {
    owner = "wazuh";
  };
  alcove.wazuhAgent = {
    enable = true;
    clientKeysFile = config.sops.secrets.wazuh_client_keys.path;
  };

  # mgmt's binary cache + root-CA trust now come from modules/internal-ca.nix
  # (alcove.internalCa.enable, set fleet-wide in common.nix).

  # Server power policy (never suspend, ignore lid, Wi-Fi powersave off) now
  # lives in modules/common.nix, so every fleet host inherits it.

  # --- Desktop (inherited from the installer) -------------------------------
  # Disabled: hacktop is a headless staging/CI box. NetworkManager (above) is
  # independent of the desktop, and there's an internal display for console
  # recovery, so dropping GNOME does not affect remote access. Re-enable this
  # block if you want a local GUI on the laptop.
  #
  # services.xserver.enable = true;
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;
  # services.printing.enable = true;
  # services.pipewire = { enable = true; alsa.enable = true; pulse.enable = true; };
  # security.rtkit.enable = true;

  # Reboot picks up the new kernel; this box should auto-recover headless on
  # Wi-Fi after a reboot (NetworkManager autoconnect + powersave off, in common.nix).

  # First install was 25.11 — leave this fixed (it tracks state compat, not
  # package versions).
  system.stateVersion = "25.11";
}
