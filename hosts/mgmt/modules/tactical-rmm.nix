# Tactical RMM docker stack (vendored from amidaware/tacticalrmm) at
# https://rmm.mgmt.lan / api.mgmt.lan / mesh.mgmt.lan.
# Secrets (db passwords, admin creds) are generated once into
# /var/lib/mgmt-secrets/trmm.env — read the admin password from there for
# first login. Its bundled nginx self-signs internally; clients only ever
# see the host nginx's step-ca certs.
{ config, pkgs, ... }:

{
  environment.etc."mgmt-stacks/trmm".source = ../stacks/trmm;

  systemd.services.trmm-secrets = {
    description = "Generate Tactical RMM env file (passwords)";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/mgmt-secrets
      chmod 711 /var/lib/mgmt-secrets
      env_file=/var/lib/mgmt-secrets/trmm.env
      if [ -f "$env_file" ]; then exit 0; fi

      rand() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; }

      umask 077
      cat > "$env_file" <<EOF
      IMAGE_REPO=tacticalrmm/
      VERSION=latest

      TRMM_USER=briggs
      TRMM_PASS=$(rand)

      APP_HOST=rmm.mgmt.lan
      API_HOST=api.mgmt.lan
      MESH_HOST=mesh.mgmt.lan

      MESH_USER=meshadmin
      MESH_PASS=$(rand)
      MONGODB_USER=mongouser
      MONGODB_PASSWORD=$(rand)
      MESH_PERSISTENT_CONFIG=0

      POSTGRES_USER=postgres
      POSTGRES_PASS=$(rand)

      TRMM_DISABLE_WEB_TERMINAL=False
      TRMM_DISABLE_SERVER_SCRIPTS=False
      TRMM_DISABLE_SSO=False
      EOF
    '';
  };

  systemd.services.trmm-stack = {
    description = "Tactical RMM docker stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "trmm-secrets.service" "network-online.target" ];
    requires = [ "docker.service" "trmm-secrets.service" ];
    wants = [ "network-online.target" ];
    path = [ config.virtualisation.docker.package pkgs.docker-compose ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "60min";  # first start pulls images
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -p trmm --env-file /var/lib/mgmt-secrets/trmm.env -f /etc/mgmt-stacks/trmm/docker-compose.yml up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -p trmm --env-file /var/lib/mgmt-secrets/trmm.env -f /etc/mgmt-stacks/trmm/docker-compose.yml stop";
    };
    restartTriggers = [ config.environment.etc."mgmt-stacks/trmm".source ];
  };
}
