# mgmt server (192.168.1.222)

NixOS management/security server: AdGuard Home, nginx reverse proxy,
private ACME CA (step-ca), Wazuh SIEM, Tactical RMM, Prometheus/Grafana,
Uptime Kuma, NetBox, Forgejo, ntopng, Snipe-IT, Harmonia nix cache,
PXE/netboot, Homepage.

All web UIs listen on localhost and are reached through nginx using
`*.mgmt.lan` names, which AdGuard Home resolves to this host. nginx gets
real, auto-renewing certs from the private step-ca via ACME; devices
only need to trust the root once.

## URLs

| Service | URL | Login |
|---|---|---|
| Homepage (landing) | https://mgmt.lan | none |
| AdGuard Home | https://adguard.mgmt.lan | `briggs` / see deploy notes |
| Wazuh dashboard | https://siem.mgmt.lan | `admin` / `grep INDEXER_PASSWORD /var/lib/mgmt-secrets/wazuh.env` |
| Tactical RMM | https://rmm.mgmt.lan | `briggs` / `grep TRMM_PASS /var/lib/mgmt-secrets/trmm.env` |
| MeshCentral | https://mesh.mgmt.lan | created by TRMM init |
| Uptime Kuma | https://status.mgmt.lan | created on first visit |
| Grafana | https://grafana.mgmt.lan | `admin` / `admin` (forces change) |
| ntopng | https://ntop.mgmt.lan | `admin` / `admin` (forces change) |
| NetBox | https://netbox.mgmt.lan | `sudo -u netbox netbox-manage createsuperuser` |
| Forgejo | https://git.mgmt.lan | see header of modules/forgejo.nix |
| Snipe-IT | https://assets.mgmt.lan | setup wizard on first visit |
| step-ca root cert | https://ca.mgmt.lan/root.crt | — |
| Nix binary cache | https://cache.mgmt.lan (pubkey at /pubkey) | — |

## One-time setup after first rebuild

1. **DHCP reservation**: pin 192.168.1.222 to this box on the router,
   then set the router's DHCP DNS server to 192.168.1.222 so every
   client uses AdGuard (and can resolve `*.mgmt.lan`).
2. **Trust the CA on your devices**: download https://ca.mgmt.lan/root.crt
   (or `curl -k`) and install as a trusted root (Windows: certlm →
   Trusted Root CAs; NixOS: `security.pki.certificateFiles`; Firefox:
   Settings → Certificates → Import). Required for browsers and for
   Tactical RMM agents to function.
3. **Wazuh credentials are auto-generated** on first boot into
   `/var/lib/mgmt-secrets/wazuh.env` (random per-deploy, like TRMM). The
   indexer's `internal_users.yml` and the dashboard's `wazuh.yml` are rendered
   host-side with the matching bcrypt hash / API password *before* the stack
   starts, so the SIEM comes up on unique creds with no manual step. Read the
   dashboard login with `grep INDEXER_PASSWORD /var/lib/mgmt-secrets/wazuh.env`.
   To rotate later: delete that file, `systemctl restart wazuh-secrets wazuh-stack`,
   then push the new hashes into the already-initialised indexer security index
   with `securityadmin.sh` (see
   https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html).
4. **Create admin accounts**: Uptime Kuma (first visit), NetBox
   (`createsuperuser`, see above), Forgejo (CLI, see
   modules/forgejo.nix), Snipe-IT (wizard).

## Enrolling machines

- **Wazuh agent**: point at `192.168.1.222` (ports 1514/1515), or use
  the deployment command from the dashboard (Agents → Deploy new).
- **Tactical RMM agent**: create client/site in the UI, generate an
  installer; endpoints must use AdGuard DNS (for `api.mgmt.lan`) and
  trust the root cert.
- **Nix binary cache client** (desktop, playground, ...):
  `nix.settings.substituters = [ "https://cache.mgmt.lan" ];`
  `nix.settings.trusted-public-keys = [ "<https://cache.mgmt.lan/pubkey>" ];`
  (plus the root CA in `security.pki.certificateFiles`).
- **PXE boot**: network-boot any machine on the LAN → netboot.xyz menu
  (pixiecore ProxyDHCP; no router changes needed).
- **Forgejo over SSH**: port 2222 (`git clone ssh://git@git.mgmt.lan:2222/...`).

## Operations

- Wazuh/TRMM are systemd units wrapping docker-compose:
  `systemctl status wazuh-stack trmm-stack`, containers via `docker ps`.
  Compose sources live in `/etc/nixos/hosts/mgmt/stacks/`, copied to
  `/etc/mgmt-stacks/` by the build; edit under `/etc/nixos`, rebuild.
- Everything else is a native NixOS service: `systemctl status
  adguardhome nginx step-ca netbox forgejo ntopng harmonia pixiecore
  grafana prometheus uptime-kuma`.
- Secrets live in `/var/lib/mgmt-secrets/` (TRMM env, NetBox/Snipe-IT
  keys, cache signing key), generated on first boot by oneshot units.
  Public material (root cert, cache pubkey) in `/var/lib/mgmt-public/`.
- **Certs renew automatically** (90-day leases from step-ca, lego renews
  via systemd timers). The CA root/intermediate live 10 years in
  `/var/lib/private/step-ca`.
- TRMM images track `VERSION=latest`; to update:
  `docker-compose -p trmm --env-file /var/lib/mgmt-secrets/trmm.env -f /etc/mgmt-stacks/trmm/docker-compose.yml pull && systemctl restart trmm-stack`.
- Wazuh is pinned at 4.14.5 in `stacks/wazuh/docker-compose.yml`.
- RAM budget: Wazuh ~4G, TRMM ~2.5G, NetBox/Snipe-IT/ntopng ~2G, rest ~1.5G
  → ~10-11G of 15G. zram swap is enabled as a cushion.
