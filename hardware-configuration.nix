{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ── Raíz efímera (Impermanence) ──────────────────────────────────────
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=3G"
      "mode=755"
    ];
  };

  # ── Kernel modules necesarios ────────────────────────────────────────
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "r8169"             # Realtek Ethernet
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
    "iwlwifi"           # Intel WiFi CNVi
  ];
  boot.extraModulePackages = [ ];

  # ── Firmware ─────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # ── NVIDIA PRIME Offload ─────────────────────────────────────────────
  # iGPU Intel (Alder Lake-P UHD Graphics)   → PCI:0:2:0  [8086:46a3]
  # dGPU NVIDIA (AD107M GeForce RTX 4060)    → PCI:1:0:0  [10de:28a0]
  hardware.nvidia = {
    # Usa el driver propietario para CUDA / Ollama
    open = false;

    # Necesario para Wayland
    modesetting.enable = true;

    # Power management
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    # PRIME Offload: iGPU Intel maneja escritorio, dGPU bajo demanda
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # ── Network ──────────────────────────────────────────────────────────
  networking.useDHCP = lib.mkDefault true;

  # ── Platform ─────────────────────────────────────────────────────────
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}