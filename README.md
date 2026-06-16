# nixOS fleet

A single [Nix flake](flake.nix) that manages a small homelab fleet — one desktop
and four servers — declaratively. Servers are deployed remotely with
[Colmena](https://github.com/zhaofengli/colmena); secrets use
[sops-nix](https://github.com/Mic92/sops-nix) (each host decrypts its own with its
SSH host key). The desktop tracks `nixpkgs` unstable; the servers track stable
(`nixos-25.11`), so folding existing boxes into the flake is zero version churn.

## Hosts

| Host | Role |
|------|------|
| **gaming** | Daily-driver desktop (KDE Plasma) and the Colmena control node. |
| **mgmt** | LAN infrastructure — AdGuard DNS, nginx reverse proxy, a private ACME CA (step-ca), Wazuh SIEM, Tactical RMM, Prometheus/Grafana, NetBox, Forgejo, a Harmonia binary cache, PXE/netboot. Folded in last and gated, since it serves the LAN's DNS + PKI. See [hosts/mgmt/README.md](hosts/mgmt/README.md). |
| **media** | Jellyfin + the \*arr stack (Sonarr/Radarr/Prowlarr/Bazarr/NZBGet), NAS over NFS. |
| **playground** | libvirt/KVM security lab host + Guacamole gateway. |
| **hacktop** | Staging / CI build host. |

Servers run behind a private internal CA: services are reached over `*.mgmt.lan`
(resolved by AdGuard) with TLS issued by step-ca, and pull from the `mgmt` binary
cache. The shared baseline — key-only SSH, an nftables firewall, the Colmena
`deploy` user, sops, the Wazuh agent, and internal-CA trust — lives in
[modules/](modules).

## Layout

```
flake.nix          # the fleet: nixosConfigurations + Colmena hive + devShell
modules/           # shared, reusable modules (common, internal-ca, wazuh-agent, …)
hosts/<host>/      # per-host config (configuration.nix + hardware-configuration.nix + extras)
pkgs/              # out-of-nixpkgs packages (e.g. the repackaged Wazuh agent)
secrets/           # sops-encrypted per-host secrets (*.yaml)
.sops.yaml         # sops recipients (public age keys only)
```

Per-host secrets are sops-encrypted; runtime service secrets (RMM/NetBox/cache
keys, etc.) are generated on the host, never committed.

## Deploying

```sh
nix develop                     # shell with colmena + the sops/age toolchain
colmena apply --on <host>       # build + push + activate one host
colmena apply --on @server      # everything tagged "server"
```

The desktop rebuilds with the `rebuild-kde` alias defined in
[hosts/gaming/dotfiles/zsh.nix](hosts/gaming/dotfiles/zsh.nix).

Day-to-day operations — updates, garbage collection, secrets, TLS/PKI, backups,
rollback, and troubleshooting — are in **[MAINTENANCE.md](MAINTENANCE.md)**.
