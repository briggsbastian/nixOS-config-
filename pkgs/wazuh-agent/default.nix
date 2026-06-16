# pkgs/wazuh-agent/default.nix
#
# Wazuh agent repackaged from the official Debian package — nixpkgs has no
# wazuh-agent (open request since 2023). We dpkg-extract the .deb and
# autoPatchelf the /var/ossec binaries + bundled libs against nixpkgs glibc.
#
# The binaries are compiled with a hardcoded DEFAULTDIR of /var/ossec for
# CONFIG + STATE (ossec.conf, client.keys, queue/, logs/). This package ships
# only the read-only tree to the store (at $out/ossec); modules/wazuh-agent.nix
# stands up the mutable /var/ossec at activation and points the daemons here.
{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, zlib, openssl, elfutils }:

stdenv.mkDerivation (finalAttrs: {
  pname = "wazuh-agent";
  version = "4.14.5-1";

  src = fetchurl {
    url = "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${finalAttrs.version}_amd64.deb";
    hash = "sha256-eNIpMtZVaXT2e9SIQ0FgloHcYy6nRNvXJV1wSl/V1w0=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook ];

  # glibc (rt/dl/m/pthread/c) comes from stdenv; libstdc++/libgcc ship bundled
  # in ossec/lib (autoPatchelf finds them in-tree). zlib/openssl in case the
  # dbsync/sysinfo/ebpf libs reach for them — add more if autoPatchelf complains.
  buildInputs = [ stdenv.cc.cc.lib zlib openssl elfutils ];

  # The eBPF object isn't a normal dynamic ELF; don't fail if a dep can't be met.
  autoPatchelfIgnoreMissingDeps = [ "modern.bpf.o" ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a var/ossec $out/ossec
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Wazuh agent, repackaged from the official Debian package";
    homepage = "https://wazuh.com";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
