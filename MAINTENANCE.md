# Fleet maintenance runbook

Operational guide for the homelab fleet defined in this repo. Everything is
deployed declaratively with **Colmena** from the desktop (the control node); you
almost never touch a server directly. See [`README.md`](README.md) for the
architecture and [`hosts/mgmt/README.md`](hosts/mgmt/README.md) for mgmt's service
inventory.

> **Golden rule:** change the config in this repo, then `colmena apply`. Don't
> hand-edit a server — the next deploy reverts it. The only state that lives on a
> box (not in the repo) is listed under [Backups](#backups).

## Fleet at a glance

| Host | Role | Deploy target | Notes |
|---|---|---|---|
| **mgmt** (.222) | DNS / PKI / SIEM / RMM / monitoring | `--on mgmt` (tag `gated`) | **Critical — serves the LAN's DNS+PKI.** Pinned to its own nixpkgs. Deploy deliberately. |
| **media** (.189) | Jellyfin + *arr | `--on media` | Depends on the NAS NFS mount (`192.168.1.213`). |
| **playground** (.217) | libvirt/KVM lab + Guacamole | `--on playground` | Single NIC on a `br0` bridge — network changes need care (see its host comments). |
| **hacktop** (.26) | staging / CI build | `--on hacktop` | **Wi-Fi only** — a deploy that restarts NetworkManager can drop it; it won't auto-reconnect. |
| **gaming** (desktop) | daily driver + Colmena control node | local `rebuild-kde` | Not a Colmena target; rebuilds itself. |

`@server` = all four servers. `@gated` = mgmt only.

---

## Routine deploys

From the desktop, in the repo:

```sh
nix develop                                  # shell with colmena + sops/age
colmena apply --on <host>                    # build + push + activate one host
colmena apply --on @server                   # all four servers
colmena apply dry-activate --on <host>       # show what WOULD change, no activation
colmena exec --on @server -- uptime          # run a command across hosts
```

**The desktop** uses its own aliases (defined in `hosts/gaming/dotfiles/zsh.nix`):

```sh
rebuild-kde         # rebuild from the current flake.lock (no input bumps)
rebuild-test-kde    # activate now, NO bootloader change (trial; reboot reverts)
rebuild-boot-kde    # stage for next boot only
```

**Deploying to mgmt is gated.** A bad deploy takes DNS+PKI down for the house.
Always `dry-activate` first, deploy in a window, and keep a rollback ready (see
[Rollback](#rollback--recovery)). mgmt is churn-free by design (pinned nixpkgs), so
a normal `colmena apply --on mgmt` should show no service restarts.

---

## Updates & upgrades

The flake uses **three nixpkgs inputs** on purpose:
- `nixpkgs` (unstable) → the **desktop** only.
- `nixpkgs-stable` (`nixos-25.11`) → the **servers** (matches what they run = zero churn).
- `nixpkgs-mgmt` (pinned rev) → **mgmt** only (churn-free).

```sh
nix flake update                 # bump ALL inputs in flake.lock
nix flake update nixpkgs-stable  # bump just the servers' channel
colmena apply --on @server       # roll the bump to the servers
rebuild-kde                       # roll the desktop (or: `upgrade` = bump+build+diff+confirm+switch)
```

- **Review before you switch.** The desktop's `upgrade` alias (`hosts/gaming/scripts/upgrade.sh`)
  bumps the lock, builds, prints the **closure diff**, and asks before activating —
  use it (or `nix store diff-closures`) so you see what's changing, especially the kernel.
- **mgmt is intentionally frozen** at `nixpkgs-mgmt`. To update it, bump that input
  **deliberately and alone** (`nix flake update nixpkgs-mgmt`), diff the closure, and
  apply in a window — never let a routine fleet bump churn mgmt's DNS/PKI/SIEM.

---

## Garbage collection & disk

```sh
colmena exec --on @server -- 'df -h /'                       # check disk per host
sudo nix-collect-garbage --delete-older-than 30d            # on a host (or via the desktop `nix-gc` alias for the desktop)
sudo nix store optimise                                     # dedupe the store (hardlinks)
```

hacktop auto-GCs weekly (`nix.gc`, >30d) — see `hosts/hacktop/configuration.nix`.
Consider adding the same `nix.gc` block to `modules/common.nix` so every server
self-maintains. Generations: `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system`.

---

## Secrets (sops-nix)

Each host decrypts its own secrets at activation using its **SSH host key** (no
extra key to distribute). The admin age key on the desktop edits everything.

```sh
nix develop                          # ships sops / age / ssh-to-age
sops secrets/<host>.yaml             # edit (decrypts in $EDITOR, re-encrypts on save)
sops set secrets/<host>.yaml '["key"]' '"value"'   # set one value non-interactively
```

- **Add a host's secrets:** derive its recipient — `ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age` — add it to `.sops.yaml` (`keys:` + a `creation_rule`), then `sops updatekeys secrets/<host>.yaml`.
- **Caveat:** a host's age identity *is* its `/etc/ssh/ssh_host_ed25519_key`. **Re-imaging a box loses access to its secrets** unless you preserve/inject that host key or re-key the files afterward.
- Runtime service secrets on mgmt (`/var/lib/mgmt-secrets/*`) are still generated on-host, not sops — migrating them is an open item.

---

## TLS / internal PKI

mgmt's **step-ca** issues 90-day certs for `*.mgmt.lan`; nginx auto-renews them via
lego (systemd timers) ~30 days before expiry. The root CA lives 10 years in
`/var/lib/private/step-ca`. Hosts trust it via `alcove.internalCa.enable`
(`modules/internal-ca.nix`).

```sh
# Check what a service is actually serving (run from a host that resolves *.mgmt.lan):
nix shell nixpkgs#openssl -c bash -c \
  'echo | openssl s_client -connect 192.168.1.222:443 -servername ca.mgmt.lan 2>/dev/null | openssl x509 -noout -issuer -enddate'
# Want: issuer=CN=mgmt.lan Intermediate CA.  If it says "minica" -> see Troubleshooting.
```

- **Trust the root on a new device:** download `https://ca.mgmt.lan/root.crt` and add
  it as a trusted root (the committed `modules/certs/mgmt-root.crt` is the same public cert).
  NixOS hosts: import `internal-ca.nix`. Firefox also needs
  `programs.firefox.policies.Certificates.ImportEnterpriseRoots = true`.
- **Known failure mode (fixed — keep it fixed):** ACME validation needs the box to
  resolve `*.mgmt.lan` *itself*. mgmt and the consumers don't use AdGuard as their
  resolver, so `step-ca.nix` / `internal-ca.nix` pin the ACME + cache hostnames to
  `192.168.1.222` in `/etc/hosts`. **Don't remove those pins** or certs silently fall
  back to the untrusted `minica` self-signed cert.

---

## Monitoring & health

```sh
colmena exec --on @server -- systemctl is-system-running    # running / degraded?
colmena exec --on @server -- 'systemctl --failed --no-legend'
```

- **Wazuh SIEM** — `https://siem.mgmt.lan` → Agents should show **004 playground /
  005 media / 006 hacktop / 007 mgmt all Active** with realtime FIM on `/etc`.
- **Grafana / Prometheus** — `https://grafana.mgmt.lan`. **Uptime Kuma** — `https://status.mgmt.lan`.
- **ntopng** — `https://ntop.mgmt.lan`. Landing page — `https://mgmt.lan`.
- A Wazuh agent showing **Disconnected** is usually the midnight log-rotation /
  FIM-db bug class — already fixed in `modules/wazuh-agent.nix` (pre-creates
  `logs/{wazuh,ossec}` + `queue/fim/db`); redeploy the agent if it recurs.

---

## Backups

State that is **not** in this repo and would be lost on a reinstall — back these up:

| What | Where | Notes |
|---|---|---|
| Media library | NAS `192.168.1.213:/srv/media` | The NAS is the system of record; back the NAS up. |
| mgmt service secrets | `mgmt:/var/lib/mgmt-secrets/` | TRMM/NetBox/Snipe-IT/cache keys. **Auto-backed-up daily** (see below). |
| step-ca root + intermediate | `mgmt:/var/lib/private/step-ca/` | Lose this = re-trust every device. **Auto-backed-up daily** (see below). |
| Docker stack volumes | `mgmt` (wazuh, trmm) | SIEM history, RMM/MeshCentral state. |
| SSH **host keys** | each box `/etc/ssh/ssh_host_*` | = the sops identity; preserve across re-images. |
| sops-encrypted secrets | `secrets/*.yaml` in git | Safe in the repo (encrypted). |

**Automated:** `hosts/mgmt/modules/backup.nix` runs daily (03:30) — it streams
`/var/lib/{private/step-ca,mgmt-secrets}` through `age` (encrypted to the admin
key; no plaintext on disk) to `192.168.1.213:/srv/media/_backups/mgmt/`, keeping
the newest 14. Restore on the desktop (which holds the admin key):

```sh
age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | sudo tar -C / -xv
```

Still **not** automated: the docker stack volumes (Wazuh/TRMM history) — back those
up separately if you want SIEM/RMM state to survive a rebuild.

---

## Rollback & recovery

```sh
# On the affected host (needs root/console — the deploy user can't roll back):
sudo nixos-rebuild switch --rollback
# Or pick the previous generation at the systemd-boot menu on reboot.
```

- A **`rebuild-test-*` / `switch-to-configuration test`** activation never changes the
  boot default, so a power-cycle auto-reverts — the safe way to trial a risky change
  (this is how the playground `br0` cutover was done; see `git log` / `log.md`).
- **hacktop / playground are remote-recovery-limited** (Wi-Fi-only / single-NIC):
  prefer `test` activations + console access for anything touching their networking.
- If a deploy half-applied and you're locked out, reboot to the last good generation
  at the boot menu, then fix the config and redeploy.

---

## Adding a host

1. `hosts/<name>/{configuration,hardware-configuration}.nix`.
2. One line in `flake.nix`'s `servers` map: `<name> = { targetHost = "<IP>"; tags = [ "server" … ]; };`.
3. Add its age recipient to `.sops.yaml` + a `creation_rule`; create `secrets/<name>.yaml`.
4. Bootstrap the `deploy` user once (manual `sudo nixos-rebuild switch` on the box),
   then it's Colmena-managed. `nix flake check` before deploying.

---

## Per-host runbooks

- **mgmt** — full service/URL/port inventory + one-time setup in [`hosts/mgmt/README.md`](hosts/mgmt/README.md). Ports that must stay open: 22/53/80/443/1514/1515/2222 + PXE 69/4011/8088. Never break DNS.
- **playground lab VMs** — build runbook in [`hosts/playground/domains/README.md`](hosts/playground/domains/README.md).
- **media** — services wait on the NFS mount; if `/mnt/media` is down the *arr units stay in `RequiresMountsFor`. Check the NAS first.
- **hacktop** — Wi-Fi-only; wire it to ethernet + a DHCP reservation before treating it as CI prod (see its host comments).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `*.mgmt.lan` serves a cert warning / `minica` issuer | the `/etc/hosts` ACME pin missing, or step-ca down | confirm the pins in `step-ca.nix`/`internal-ca.nix`; `systemctl restart step-ca`; `reset-failed` + start the `acme-order-renew-*` units |
| Binary cache not used / falls back to cache.nixos.org | consumer can't resolve/trust `cache.mgmt.lan` | check `getent hosts cache.mgmt.lan` → .222 and that `internal-ca.enable` is on |
| A host is unreachable after a deploy | NetworkManager restart dropped Wi-Fi (hacktop), or a bad network change | console + reboot to last-good generation; redeploy |
| Wazuh agent **Disconnected** | log-rotation/FIM-db dir miss | already fixed in the module; `colmena apply --on <host>` to re-converge |
| media *arr services not starting | NFS mount (`/mnt/media`) unavailable | check the NAS / `systemctl status mnt-media.automount` |
| `colmena apply` fails on a dirty tree | unlocked input in pure mode | the repo uses the `colmenaHive` output (`makeHive`) which handles this — make sure you're not invoking the legacy `colmena` output |
| `nix copy` to a host rejects unsigned paths | the `deploy` user isn't a Nix trusted-user for manual copies | use `colmena apply`/`dry-activate`, which handles the push |
