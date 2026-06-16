# modules/media-hardening.nix
#
# systemd sandboxing for the *arr + Jellyfin services on `media`. The goal is to
# drive each service's `systemd-analyze security` exposure score down without
# breaking the stack — so this DELIBERATELY omits three otherwise-good options:
#
#   * MemoryDenyWriteExecute  — the *arr apps and Jellyfin are .NET (JIT), which
#                               needs W+X memory; enabling it kills them.
#   * ProtectSystem = "strict"— the *arr WRITE into the NFS mount /mnt/media
#                               (library moves/renames); "full" keeps /var + /mnt
#                               writable. "strict" + ReadWritePaths is a later,
#                               live-tested tightening (watch the NFS automount).
#   * PrivateDevices = true   — Jellyfin needs /dev/dri (Intel QSV/VAAPI) to
#                               hardware-transcode.
#
# Everything below is the safe subset. Values are mkDefault so they never
# conflict with (and never weaken) the hardening the nixpkgs service modules
# already ship — the stricter definition wins.
{ lib, ... }:

let
  hardening = lib.mapAttrs (_: lib.mkDefault) {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "full";
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    LockPersonality = true;
    SystemCallArchitectures = "native";
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    UMask = "0027";
  };

  # The media-stack services (all defined in hosts/media/arr.nix).
  hardenedServices = [ "jellyfin" "radarr" "sonarr" "prowlarr" "bazarr" "nzbget" ];
in
{
  systemd.services = lib.genAttrs hardenedServices (_: {
    serviceConfig = hardening;
  });
}
