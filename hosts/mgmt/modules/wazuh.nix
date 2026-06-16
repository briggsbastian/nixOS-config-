# Wazuh SIEM (manager + indexer + dashboard), single-node docker stack
# vendored from wazuh/wazuh-docker v4.14.5 into ../stacks/wazuh.
# Internal TLS certs are generated once into /var/lib/wazuh-certs.
# Dashboard: https://siem.mgmt.lan (via nginx). Agents enroll directly
# against ports 1515/1514.
{ config, pkgs, ... }:

{
  # required by the wazuh-indexer (OpenSearch)
  boot.kernel.sysctl."vm.max_map_count" = 262144;

  environment.etc."mgmt-stacks/wazuh".source = ../stacks/wazuh;

  systemd.services.wazuh-certs = {
    description = "Generate Wazuh internal TLS certificates";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    path = [ config.virtualisation.docker.package pkgs.docker-compose ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30min";
    };
    script = ''
      if [ ! -f /var/lib/wazuh-certs/root-ca.pem ]; then
        mkdir -p /var/lib/wazuh-certs
        docker-compose -p wazuh-certs \
          -f /etc/mgmt-stacks/wazuh/generate-indexer-certs.yml \
          run --rm generator
      fi
    '';
  };

  # Generate per-deploy random credentials (like trmm-secrets) and render the
  # indexer/dashboard config from the committed templates. Nothing secret is in
  # the repo: docker-compose.yml reads INDEXER/API/DASHBOARD passwords from this
  # env-file, and the bcrypt hashes / API password are substituted into the
  # rendered configs under /var/lib/mgmt-secrets/wazuh/ (which the stack mounts).
  systemd.services.wazuh-secrets = {
    description = "Generate Wazuh credentials + render indexer/dashboard config";
    wantedBy = [ "multi-user.target" ];
    before = [ "wazuh-stack.service" ];
    path = [ pkgs.coreutils pkgs.mkpasswd pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/mgmt-secrets/wazuh
      chmod 711 /var/lib/mgmt-secrets
      chmod 700 /var/lib/mgmt-secrets/wazuh
      env_file=/var/lib/mgmt-secrets/wazuh.env
      if [ -f "$env_file" ]; then exit 0; fi

      rand() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; }
      bhash() { mkpasswd -m bcrypt -R 12 "$1"; }

      indexer_pw="$(rand)"    # admin        (manager/dashboard -> indexer)
      dashboard_pw="$(rand)"  # kibanaserver (dashboard -> indexer)
      api_pw="$(rand)"        # wazuh-wui    (dashboard -> manager API)

      umask 077
      cat > "$env_file" <<EOF
      INDEXER_PASSWORD=$indexer_pw
      DASHBOARD_PASSWORD=$dashboard_pw
      API_PASSWORD=$api_pw
      EOF

      src=/etc/mgmt-stacks/wazuh/config
      out=/var/lib/mgmt-secrets/wazuh

      # bcrypt is in OpenSearch's accepted set ($2a/$2b/$2y). admin + kibanaserver
      # get the env passwords; unused demo accounts get random throwaway hashes.
      sed \
        -e "s|@ADMIN_HASH@|$(bhash "$indexer_pw")|" \
        -e "s|@KIBANASERVER_HASH@|$(bhash "$dashboard_pw")|" \
        -e "s|@KIBANARO_HASH@|$(bhash "$(rand)")|" \
        -e "s|@LOGSTASH_HASH@|$(bhash "$(rand)")|" \
        -e "s|@READALL_HASH@|$(bhash "$(rand)")|" \
        -e "s|@SNAPSHOTRESTORE_HASH@|$(bhash "$(rand)")|" \
        "$src/wazuh_indexer/internal_users.yml" > "$out/internal_users.yml"

      sed -e "s|@API_PASSWORD@|$api_pw|" \
        "$src/wazuh_dashboard/wazuh.yml" > "$out/wazuh.yml"

      chmod 600 "$out"/internal_users.yml "$out"/wazuh.yml
    '';
  };

  systemd.services.wazuh-stack = {
    description = "Wazuh SIEM docker stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "wazuh-certs.service" "wazuh-secrets.service" "network-online.target" ];
    requires = [ "docker.service" "wazuh-certs.service" "wazuh-secrets.service" ];
    wants = [ "network-online.target" ];
    path = [ config.virtualisation.docker.package pkgs.docker-compose ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "60min";  # first start pulls ~3GB of images
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -p wazuh --env-file /var/lib/mgmt-secrets/wazuh.env -f /etc/mgmt-stacks/wazuh/docker-compose.yml up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -p wazuh --env-file /var/lib/mgmt-secrets/wazuh.env -f /etc/mgmt-stacks/wazuh/docker-compose.yml stop";
    };
    restartTriggers = [ config.environment.etc."mgmt-stacks/wazuh".source ];
  };
}
