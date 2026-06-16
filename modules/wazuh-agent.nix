# modules/wazuh-agent.nix
#
# Enroll a fleet host as a Wazuh agent reporting to the manager on mgmt
# (192.168.1.222 — events 1514/tcp, enrollment 1515/tcp). Uses the repackaged
# pkgs/wazuh-agent (no nixpkgs package exists).
#
# Wazuh hardcodes /var/ossec for config + state, so we can't keep it purely in
# the store: the service's preStart builds /var/ossec each start by symlinking
# the read-only tree from the store, creating writable state dirs, dropping in a
# generated ossec.conf, and enrolling (agent-auth) if there's no key yet.
{ config, lib, pkgs, ... }:

let
  cfg = config.alcove.wazuhAgent;
  wazuh = pkgs.callPackage ../pkgs/wazuh-agent { };

  # Auto-enrollment (agentd self-registers with the manager on first start) is
  # only emitted when NO pre-shared key is supplied. With clientKeysFile set, the
  # key is installed directly (see preStart) and we MUST NOT also <enrollment>,
  # or the agent races registration against its own pre-seeded key.
  enrollmentBlock = lib.optionalString (cfg.clientKeysFile == null) ''
        <enrollment>
          <enabled>yes</enabled>
          <manager_address>${cfg.managerAddress}</manager_address>
          <port>1515</port>
          <agent_name>${cfg.agentName}</agent_name>
        </enrollment>
  '';

  ossecConf = pkgs.writeText "ossec.conf" ''
    <ossec_config>
      <client>
        <server>
          <address>${cfg.managerAddress}</address>
          <port>1514</port>
          <protocol>tcp</protocol>
        </server>
        <crypto_method>aes</crypto_method>
        <notify_time>10</notify_time>
        <time-reconnect>60</time-reconnect>
        <auto_restart>yes</auto_restart>
    ${enrollmentBlock}  </client>

      <client_buffer>
        <disabled>no</disabled>
        <queue_size>5000</queue_size>
        <events_per_second>500</events_per_second>
      </client_buffer>

      <!-- File integrity monitoring — /etc is NixOS's mutable config surface -->
      <syscheck>
        <disabled>no</disabled>
        <frequency>43200</frequency>
        <scan_on_start>yes</scan_on_start>
        <directories check_all="yes" realtime="yes">/etc</directories>
        <directories check_all="yes">/root,/home</directories>
        <nodiff>/etc/ssl/private</nodiff>
        <skip_nfs>yes</skip_nfs>
      </syscheck>

      <rootcheck>
        <disabled>no</disabled>
      </rootcheck>

      <sca>
        <enabled>yes</enabled>
        <scan_on_start>yes</scan_on_start>
      </sca>

      <!-- TODO: journald log collection (a <localfile> journald source) makes
           wazuh-logcollector fail to start here; revisit (journal access /
           reader init). FIM + rootcheck + SCA still report to the SIEM. -->
    </ossec_config>
  '';
in
{
  options.alcove.wazuhAgent = {
    enable = lib.mkEnableOption "Wazuh agent enrolled to the homelab SIEM on mgmt";

    managerAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.222";
      description = "Wazuh manager address (events 1514/tcp, enrollment 1515/tcp).";
    };

    agentName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Agent name registered with the manager.";
    };

    enrollmentPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/wazuh_enrollment";
      description = "File with the manager's authd enrollment password. Null = open enrollment.";
    };

    clientKeysFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/wazuh_client_keys";
      description = ''
        Path to a pre-shared `client.keys` (the line `ID NAME any KEY` issued by
        `manage_agents` on the manager). When set, the key is installed directly
        and auto-<enrollment> is disabled — this sidesteps the self-enrollment
        key-persistence race. Typically a sops secret's `.path`. Null = auto-enroll.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The agent runs its daemons as the `wazuh` user (with internal priv-sep);
    # needs journal access for log collection.
    users.users.wazuh = {
      isSystemUser = true;
      group = "wazuh";
      extraGroups = [ "systemd-journal" ];
      description = "Wazuh agent";
      home = "/var/ossec";
    };
    users.groups.wazuh = { };

    # Let the deploy/ops user read /var/ossec logs for remote debugging.
    users.users.deploy.extraGroups = [ "wazuh" ];

    # wazuh-control / agent-auth on PATH for debugging.
    environment.systemPackages = [ wazuh ];

    systemd.services.wazuh-agent = {
      description = "Wazuh agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # wazuh-control is a POSIX-sh script that shells out to these.
      path = [ pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.procps ];

      preStart = ''
        set -eu
        OSSEC=/var/ossec
        PKG=${wazuh}/ossec

        # mutable state root (the binaries hardcode /var/ossec)
        install -d -m 0750 -o root -g wazuh "$OSSEC"

        # writable state dirs. NOTE logs/wazuh + logs/ossec: at 00:00 the agent
        # rotates its logs into logs/{wazuh,ossec}/<year>/ and does NOT mkdir the
        # parent — a missing logs/wazuh makes the daily rotation crash CRITICAL
        # (1107) and the agent stops sending keepalives (manager → Disconnected).
        for d in etc etc/shared logs logs/wazuh logs/ossec \
                 queue queue/diff queue/rids \
                 queue/fim queue/fim/db queue/syscollector queue/sockets \
                 var var/run var/db var/wodles tmp ruleset/sca; do
          install -d -m 0750 -o wazuh -g wazuh "$OSSEC/$d"
        done

        # The daemons resolve their base dir from their OWN on-disk location, so
        # the binaries must be REAL files under /var/ossec — a symlink resolves
        # back to the read-only store and makes them read the store's DEFAULT
        # ossec.conf (address = MANAGER_IP). Libs/rulesets are data and can stay
        # symlinked (binaries find libs via their absolute store rpath).
        for d in bin active-response wodles agentless; do
          if [ -e "$PKG/$d" ]; then
            rm -rf "$OSSEC/$d"
            cp -a "$PKG/$d" "$OSSEC/$d"
            chmod -R u+rwX "$OSSEC/$d"
          fi
        done
        for d in lib ruleset/rootcheck; do
          if [ -e "$PKG/$d" ]; then ln -sfn "$PKG/$d" "$OSSEC/$d"; fi
        done

        # config: our generated ossec.conf + the package's option defaults
        install -m 0640 -o root -g wazuh ${ossecConf} "$OSSEC/etc/ossec.conf"
        for f in internal_options.conf local_internal_options.conf; do
          [ -e "$OSSEC/etc/$f" ] || install -m 0640 -o root -g wazuh "$PKG/etc/$f" "$OSSEC/etc/$f" 2>/dev/null || true
        done
        ${if cfg.clientKeysFile != null then ''
          # Pre-shared key: install the manager-issued client.keys directly and
          # authoritatively (idempotent — re-copied every start from the sops
          # secret so it can't drift). No <enrollment> is emitted in this mode,
          # so there's no self-registration race to lose the key to.
          install -m 0640 -o wazuh -g wazuh ${cfg.clientKeysFile} "$OSSEC/etc/client.keys"
        '' else ''
          [ -e "$OSSEC/etc/client.keys" ] || install -m 0640 -o root -g wazuh /dev/null "$OSSEC/etc/client.keys"

          # Enrollment is automatic: wazuh-agentd self-registers via the
          # <enrollment> block in ossec.conf on first start (no client.keys yet),
          # which avoids running agent-auth as a separate privileged step.
        ''}

        chown -R root:wazuh "$OSSEC/etc"
        # /var/ossec/etc must be GROUP-writable by wazuh: the agent (runs as
        # wazuh) persists client.keys at enrollment via temp-file + rename, which
        # needs write on the DIR. A root:wazuh 0750 etc let enrollment register on
        # the manager but the key never stuck locally → endless re-enroll →
        # "Duplicate agent name". client.keys itself is wazuh-owned + writable.
        chmod 0770 "$OSSEC/etc"
        # The manager pushes its shared agent config to etc/shared/merged.mg;
        # wazuh-agentd (running as wazuh) writes it via temp-file + rename, so the
        # DIR must be group-writable too — else: "(1103) Could not open file
        # 'etc/shared/merged.mg' ... Permission denied" on every manager push.
        chmod 0770 "$OSSEC/etc/shared"
        chown wazuh:wazuh "$OSSEC/etc/client.keys"
        chmod 0640 "$OSSEC/etc/client.keys"
      '';

      serviceConfig = {
        Type = "forking";
        # Run via the /var/ossec symlink, NOT the store path: wazuh-control
        # derives its install dir from `dirname $0` (logical pwd), so this makes
        # it operate on /var/ossec (writable) instead of the read-only store.
        ExecStart = "/var/ossec/bin/wazuh-control start";
        ExecStop = "/var/ossec/bin/wazuh-control stop";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
