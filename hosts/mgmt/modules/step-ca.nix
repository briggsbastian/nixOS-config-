# Private ACME CA for *.mgmt.lan. step-ca issues 90-day certs that nginx
# renews automatically via ACME (lego) — no manual cert handling.
# Root/intermediate are generated once into /var/lib/step-ca (DynamicUser
# state dir, physically /var/lib/private/step-ca). The root cert is
# published at https://ca.mgmt.lan/root.crt — install it on your devices.
{ config, lib, pkgs, ... }:

{
  services.step-ca = {
    enable = true;
    address = "127.0.0.1";
    port = 8443;
    settings = {
      root = "/var/lib/step-ca/certs/root_ca.crt";
      crt = "/var/lib/step-ca/certs/intermediate_ca.crt";
      key = "/var/lib/step-ca/secrets/intermediate_ca_key";
      dnsNames = [ "ca.mgmt.lan" "localhost" "127.0.0.1" ];
      logger.format = "text";
      db = {
        type = "badgerv2";
        dataSource = "/var/lib/step-ca/db";
      };
      authority.provisioners = [
        {
          type = "ACME";
          name = "acme";
          claims = {
            defaultTLSCertDuration = "2160h"; # 90 days
            maxTLSCertDuration = "2160h";
          };
        }
      ];
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@mgmt.lan";
      server = "https://127.0.0.1:8443/acme/acme/directory";
      # lego must trust our private root when talking to step-ca
      environmentFile = pkgs.writeText "lego-env" ''
        LEGO_CA_CERTIFICATES=/var/lib/mgmt-public/root_ca.crt
      '';
    };
  };

  # --- Make *.mgmt.lan resolve ON THIS BOX so ACME HTTP-01 can validate -------
  # Every ACME order is validated by step-ca fetching
  # http://<domain>/.well-known/acme-challenge/… (and lego does a local
  # pre-check first). mgmt's own resolver is the WAN upstream (1.1.1.1), which
  # doesn't know the internal domain — so resolution returned nothing, every
  # order failed, and nginx fell back to its minica self-signed cert on ALL
  # *.mgmt.lan. Pin every ACME domain to the box's own address in /etc/hosts
  # (nginx listens on 0.0.0.0:80). Surgical on purpose: the DNS/PKI box keeps
  # its upstream resolver for everything else (no dependency on its own AdGuard
  # for general resolution), and this list stays in sync with the nginx vhosts
  # because it's derived from the cert set itself.
  networking.hosts."192.168.1.222" =
    builtins.attrNames config.security.acme.certs;

  systemd.services = {
    step-ca-init = {
      description = "Generate step-ca root and intermediate";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.step-cli ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        dir=/var/lib/private/step-ca
        if [ ! -f "$dir/certs/root_ca.crt" ]; then
          mkdir -p "$dir/certs" "$dir/secrets" "$dir/db"
          step certificate create "mgmt.lan Root CA" \
            "$dir/certs/root_ca.crt" "$dir/secrets/root_ca_key" \
            --profile root-ca --no-password --insecure --not-after 87600h
          step certificate create "mgmt.lan Intermediate CA" \
            "$dir/certs/intermediate_ca.crt" "$dir/secrets/intermediate_ca_key" \
            --profile intermediate-ca --no-password --insecure --not-after 87600h \
            --ca "$dir/certs/root_ca.crt" --ca-key "$dir/secrets/root_ca_key"
        fi
        mkdir -p /var/lib/mgmt-public
        chmod 755 /var/lib/mgmt-public
        install -m 644 "$dir/certs/root_ca.crt" /var/lib/mgmt-public/root_ca.crt
      '';
    };

    step-ca = {
      after = [ "step-ca-init.service" ];
      requires = [ "step-ca-init.service" ];
    };
  }
  # every ACME order needs the CA up first
  // lib.genAttrs
    (map (n: "acme-${n}") (builtins.attrNames config.security.acme.certs))
    (_: {
      after = [ "step-ca.service" ];
      wants = [ "step-ca.service" ];
    });
}
