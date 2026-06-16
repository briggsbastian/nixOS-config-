# modules/common.nix
#
# Shared fleet baseline — imported by every server host (and eventually the
# desktop). Keep this host-agnostic: hostname, users, and per-host ports live
# in hosts/<name>/. The foundation tasks in "Project 1 - Nixify the Lab" will
# grow this (internal-CA trust, Wazuh agent, sops) — start small and reusable.
{ lib, pkgs, ... }:

{
  # The Colmena deploy identity (deploy user + trusted-user + scoped sudo) lives
  # in its own module so mgmt can reuse JUST that without the rest of this file.
  imports = [ ./deploy-user.nix ];

  # Flakes everywhere.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- SSH: key-only, no root, no passwords ---------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- Secrets (sops-nix) ---------------------------------------------------
  # Each host decrypts its own secrets at activation using its SSH host key —
  # no separate age key to distribute. (Recipients in .sops.yaml are each box's
  # /etc/ssh/ssh_host_ed25519_key.pub run through ssh-to-age.) Requires the
  # host's module set to also import sops-nix.nixosModules.sops (see flake.nix).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Trust mgmt's step-ca root + use its Harmonia binary cache + ACME endpoint.
  # (Option defined in modules/internal-ca.nix, also in every server's module set.)
  alcove.internalCa.enable = true;
  alcove.internalCa.useCache = true; # cache.mgmt.lan serves a real cert now (2026-06-15)

  # --- Firewall: nftables backend, deny-by-default, SSH open ----------------
  # The stock installer leaves the firewall OFF. Every fleet host should have
  # it on; 22 is the one port we always need (Colmena/SSH deploys).
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # --- Server power policy: never sleep, ignore the lid ----------------------
  # Fleet boxes live on a shelf, and some are laptops with the lid shut. Without
  # a desktop session inhibiting it, logind would suspend on lid-close/idle and
  # drop the host off the LAN. Disable sleep entirely, ignore lid + idle, and
  # keep any Wi-Fi radio from powering down into unreachability.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
  networking.networkmanager.wifi.powersave = false;

  # --- Shell + locale + time (whole fleet is one region) --------------------
  programs.zsh.enable = true;
  time.timeZone = lib.mkDefault "America/Los_Angeles";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # --- Minimal admin toolkit present on every box ---------------------------
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tmux
    curl
    rsync
  ];

  # --- Remote deploy identity (Colmena) -------------------------------------
  # Moved to modules/deploy-user.nix (imported above) so mgmt can share it.
}
