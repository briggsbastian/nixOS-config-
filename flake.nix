{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak = { url = "github:gmodena/nix-flatpak"; };
    nixvim = { url = "github:nix-community/nixvim"; };
    claude-code = {url = "github:sadjow/claude-code-nix"; };
    # Claude Desktop GUI chat client (community repackage of the official app —
    # no nixpkgs/official Linux build exists). Used ONLY by the gaming host's
    # home configs below; servers never reference it.
    # NOTE: it `follows = "nixpkgs-stable"` (25.11), NOT unstable: the repackage
    # build-depends on `nodePackages.asar`, which nixpkgs-UNSTABLE removed
    # 2026-03-03 (the flake is stale). 25.11 still ships it, and we already fetch
    # that tree for the servers — so this reuses it (no extra nixpkgs in the lock).
    claude-desktop = { url = "github:k3d3/claude-desktop-linux-flake"; inputs.nixpkgs.follows = "nixpkgs-stable"; };
    colmena = { url = "github:zhaofengli/colmena"; inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    # Two-input split: the desktop tracks `nixpkgs` (unstable); the SERVERS track
    # stable (nixos-25.11 — what the boxes already run, so zero version churn).
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    # mgmt is folded in faithfully + GATED: pinned to the EXACT nixpkgs rev it
    # already runs, so the first Colmena cutover is a no-op (no package churn →
    # no DNS/PKI/SIEM restarts). Bump this deliberately, on its own, later.
    nixpkgs-mgmt.url = "github:NixOS/nixpkgs/755f5aa91337890c432639c60b6064bb7fe67769";
  };

  outputs = inputs @ {self, home-manager, nix-flatpak, nixvim, nixpkgs, nixpkgs-stable, nixpkgs-mgmt, claude-code, colmena, sops-nix, ...}:
    let
      mkSystem = { homeFile }: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/gaming/configuration.nix
          home-manager.nixosModules.home-manager
          nix-flatpak.nixosModules.nix-flatpak
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.briggs = import homeFile;
          }
        ];
      };

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Every server = the shared baseline + sops + its own host module. One
      # module list feeds BOTH the nixosConfiguration (nixos-rebuild /
      # nixos-anywhere) and the Colmena node, so the two never drift.
      serverModules = host: [
        ./modules/common.nix
        ./modules/internal-ca.nix
        ./modules/wazuh-agent.nix
        sops-nix.nixosModules.sops
        ./hosts/${host}/configuration.nix
      ];

      # The fleet's servers: host -> deploy metadata. Adding a server is one line
      # here + a hosts/<host>/ dir. targetHost is ALWAYS an IP — the internal
      # domain is served by mgmt's AdGuard, so resolving it here would be a DNS
      # bootstrap deadlock.
      #   mgmt (192.168.1.222) is folded in LAST and gated — it serves the LAN's
      #   DNS + PKI, so a bad deploy takes down the whole house (see Project 1).
      servers = {
        hacktop = { targetHost = "192.168.1.26"; tags = [ "server" "staging" ]; };
        media   = { targetHost = "192.168.1.189"; tags = [ "server" "media" ]; };
        playground   = { targetHost = "192.168.1.217"; tags = [ "server" "lab" ]; };
      };

      # Servers build against STABLE nixpkgs (nixos-25.11) — matching the boxes'
      # current versions, so folding them in is zero version churn. The desktop
      # (mkSystem above) stays on unstable.
      mkServerSystem = host: nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        modules = serverModules host;
      };

      mkColmenaNode = host: meta: { ... }: {
        deployment = {
          targetHost = meta.targetHost;
          targetUser = "deploy";
          tags = meta.tags;
        };
        imports = serverModules host;
      };

      # mgmt — the LAN's DNS + PKI + SIEM box, folded in LAST and GATED. It does
      # NOT take the fleet common.nix (its own base.nix owns SSH/firewall, and
      # step-ca owns ACME — common.nix would fight both); it gets ONLY the deploy
      # identity. Built against its pinned running nixpkgs for a churn-free cut.
      mgmtModules = [
        ./modules/deploy-user.nix
        sops-nix.nixosModules.sops      # mgmt enrolls itself as a Wazuh agent → needs sops
        ./modules/wazuh-agent.nix
        ./hosts/mgmt/configuration.nix
      ];
      mkMgmtSystem = nixpkgs-mgmt.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mgmtModules;
      };
      mkMgmtColmenaNode = { ... }: {
        deployment = {
          targetHost = "192.168.1.222";
          targetUser = "deploy";
          tags = [ "server" "mgmt" "gated" ];
        };
        imports = mgmtModules;
      };
    in {
      nixosConfigurations = {
        nixos-kde = mkSystem { homeFile = ./hosts/gaming/home-kde.nix; };
        mgmt = mkMgmtSystem;
      } // nixpkgs.lib.mapAttrs (host: _: mkServerSystem host) servers;

      # --- Remote deploy from this desktop (the Colmena control node) ----------
      #   nix develop                          # shell with colmena + sops/age
      #   colmena build --on media             # build only
      #   colmena apply --on playground             # build + push + activate (as deploy)
      #   colmena apply --on @server           # everything tagged "server"
      colmenaHive = colmena.lib.makeHive (
        {
          meta = {
            nixpkgs = import nixpkgs-stable { system = "x86_64-linux"; };
            # mgmt builds against its own pinned nixpkgs → churn-free cutover.
            nodeNixpkgs.mgmt = import nixpkgs-mgmt { system = "x86_64-linux"; };
          };
          mgmt = mkMgmtColmenaNode;
        }
        // nixpkgs.lib.mapAttrs mkColmenaNode servers
      );

      devShells.x86_64-linux.default = pkgs.mkShell {
        # colmena (deploy) + the sops/age toolchain (edit + re-key secrets).
        # sops auto-reads your admin key from ~/.config/sops/age/keys.txt.
        packages = [
          colmena.packages.x86_64-linux.colmena
          pkgs.sops
          pkgs.age
          pkgs.ssh-to-age
        ];
      };

      # Out-of-nixpkgs packages, built against stable (where the servers run).
      packages.x86_64-linux.wazuh-agent =
        nixpkgs-stable.legacyPackages.x86_64-linux.callPackage ./pkgs/wazuh-agent { };
    };
}
