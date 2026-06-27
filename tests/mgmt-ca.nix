# tests/mgmt-ca.nix
#
# mgmt-shaped check: a hermetic, single-node NixOS VM test proving the mechanism
# mgmt's whole TLS story rests on -- step-ca issues a cert over ACME and nginx
# serves it on an internal vhost, verifiable against the CA root. If step-ca,
# lego, or the nginx<->ACME wiring breaks, every *.mgmt.lan service silently
# falls back to an untrusted cert; this catches that in CI.
#
# It IMPORTS the real hosts/lan/mgmt/modules/step-ca.nix -- the init script, the
# ACME provisioner + 90-day claims, the lego-trusts-the-private-root wiring, and
# the self-syncing /etc/hosts pin -- rather than copying it, so the test can't
# drift from the module and actually exercises that pin derivation. The module
# pins every ACME domain to mgmt's real IP (192.168.1.222) for on-box HTTP-01
# validation; the one override below re-points that SAME derivation at loopback
# so a single node stays hermetic -- no network, no real DNS.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "mgmt-ca";

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ ../hosts/lan/mgmt/modules/step-ca.nix ];

      environment.systemPackages = [
        pkgs.curl
        pkgs.openssl
      ];

      # One internal HTTPS vhost that wants a cert from step-ca -- the thing under
      # test. forceSSL + enableACME is the same nginx<->ACME wiring the real vhosts
      # use (hosts/lan/mgmt/modules/nginx.nix).
      services.nginx = {
        enable = true;
        virtualHosts."web.mgmt.lan" = {
          forceSSL = true;
          enableACME = true;
          locations."/".return = "200 'hermetic-ca-ok'";
        };
      };

      # step-ca.nix pins every ACME domain to mgmt's real IP (192.168.1.222) so
      # HTTP-01 validates on the real box. Re-point the SAME derivation
      # (attrNames acme.certs) at loopback: drop the prod pin and make the vhost
      # resolve to this node, so the module's self-syncing pin stays under test.
      networking.hosts."192.168.1.222" = lib.mkForce [ ];
      networking.hosts."127.0.0.1" = builtins.attrNames config.security.acme.certs;
    };

  testScript = ''
    machine.start()
    # step-ca.nix orders step-ca after its init oneshot, so this implies the root
    # + intermediate were generated.
    machine.wait_for_unit("step-ca.service")

    # step-ca issues the cert over ACME (lego); the order oneshot completes on success.
    machine.wait_for_unit("acme-web.mgmt.lan.service")
    machine.wait_for_unit("nginx.service")

    # nginx serves TLS with a cert that verifies against the root the module
    # published (/var/lib/mgmt-public/root_ca.crt, from step-ca-init)...
    machine.wait_until_succeeds(
        "curl -sS --cacert /var/lib/mgmt-public/root_ca.crt https://web.mgmt.lan | grep -q hermetic-ca-ok",
        timeout=180,
    )
    # ...and it's the step-ca intermediate that issued it, not nginx's snakeoil fallback.
    machine.succeed(
        "echo | openssl s_client -connect web.mgmt.lan:443 -servername web.mgmt.lan 2>/dev/null "
        "| openssl x509 -noout -issuer | grep -i Intermediate"
    )
  '';
}
