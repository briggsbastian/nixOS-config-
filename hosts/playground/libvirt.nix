# hosts/playground/libvirt.nix
#
# playground as the libvirt/KVM host for the security lab (Kali, Parrot, REMnux,
# FlareVM). This module is HOST ENABLEMENT only: libvirtd + TPM 2.0 (swtpm) so the
# Windows FlareVM can boot. UEFI/OVMF firmware is auto-discovered from QEMU on
# 25.11 (the old qemu.ovmf option was removed). AMD-V + /dev/kvm are present.
#
# Companion modules (imported alongside this): ./bridge.nix is the br0 bridge that
# puts guests on the LAN; ./lan-br0.xml is the libvirt network that attaches them
# to it. Still to come: the four VM domains — built from official images
# (REMnux / Kali / Parrot) plus a manual FlareVM — with their XMLs under ./domains/.
{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    # Don't auto-start guests at boot until each domain is vetted; flip per-VM
    # with `virsh autostart <dom>` once it boots cleanly on the bridge.
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu.swtpm.enable = true; # TPM 2.0 — FlareVM (Win11) requires it
  };

  # Manage as the `playground` user (virsh against qemu:///system), or remotely
  # via `virt-manager -c qemu+ssh://playground/system`.
  users.users.playground.extraGroups = [ "libvirtd" ];

  # VM-import tooling: qemu-img (qcow2 convert), p7zip (Kali ships its prebuilt
  # QEMU image as a .7z). tar/xz/gzip for OVAs are already in the base system.
  environment.systemPackages = with pkgs; [ qemu-utils p7zip ];
}
