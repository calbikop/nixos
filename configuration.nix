{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  persistPath = "/persist";
in
{
  imports = [
    # Importado desde flake.nix: disko, impermanence
  ];

  # ═══════════════════════════════════════════════════════════════════════
  #  SYSTEM IDENTITY
  # ═══════════════════════════════════════════════════════════════════════

  networking.hostName = "msi-nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "es_ES.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ═══════════════════════════════════════════════════════════════════════
  #  KERNEL & SECURITY
  # ═══════════════════════════════════════════════════════════════════════

  # Kernel hardened (⚠ Si los drivers NVIDIA fallan al compilar, cambia a
  #   boot.kernelPackages = pkgs.linuxPackages_latest;)
  boot.kernelPackages = pkgs.linuxPackages_hardened;

  # AppArmor (MAC)
  security.apparmor.enable = true;

  # Firewall estricto: solo lo explícito sale/entra
  networking.firewall.enable = true;
  networking.firewall.allowPing = false;
  networking.firewall.logReversePathDrops = true;
  networking.firewall.checkReversePath = "loose";

  # Mitigaciones CPU
  boot.kernelParams = [
    "mitigations=auto"
    "intel_iommu=on"
    "iommu=pt"
  ];

  # Sin coredumps
  systemd.coredump.enable = false;
  boot.kernel.sysctl = {
    "kernel.core_pattern" = "|/bin/false";
    "fs.suid_dumpable" = "0";
  };

  # Bloquear módulos de kernel innecesarios (reduce superficie)
  boot.blacklistedKernelModules = [
    "firewire-core"
    "thunderbolt"
  ];

  # ── Swap en RAM con zstd ─────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  IMPERMANENCE — Sólo lo necesario sobrevive al reinicio
  # ═══════════════════════════════════════════════════════════════════════

  environment.persistence.${persistPath} = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/log"
      "/var/lib"
      {
        directory = "/home/biko";
        user = "biko";
        group = "users";
        mode = "0755";
      }
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # Asegurar que /persist/home/biko exista antes de montar
  system.activationScripts.ensure-persist-home = {
    text = ''
      mkdir -p ${persistPath}/home/biko
      mkdir -p ${persistPath}/etc/nixos
      mkdir -p ${persistPath}/var/log
      mkdir -p ${persistPath}/var/lib
    '';
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  GPU & CUDA / OLLAMA
  # ═══════════════════════════════════════════════════════════════════════

  # NVIDIA PRIME Offload — configurado en hardware-configuration.nix
  # Aquí añadimos soporte CUDA y Ollama

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Ollama con aceleración CUDA (invocación bajo demanda)
  services.ollama = {
    enable = true;
    acceleration = "cuda";
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  PERIFÉRICOS: Razer Huntsman Mini + Viper V3 HyperSpeed
  # ═══════════════════════════════════════════════════════════════════════

  hardware.openrazer = {
    enable = true;
    users = [ "biko" ];
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  USUARIO biko
  # ═══════════════════════════════════════════════════════════════════════

  users.users.biko = {
    isNormalUser = true;
    initialPassword = "changeme";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
      "docker"
      "openrazer"
      "ollama"
    ];
    shell = pkgs.zsh;
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  DOTFILES RYOKU — Activación automática en primer boot
  # ═══════════════════════════════════════════════════════════════════════

  system.activationScripts.ryoku-dotfiles = {
    text = ''
      DOTFILES_REPO="https://github.com/neur0map/ryoku-arch"
      PERSIST_HOME="${persistPath}/home/biko"

      if [ ! -d "$PERSIST_HOME/.config/hypr" ]; then
        echo "[ryoku] Clonando dotfiles..."
        ${pkgs.git}/bin/git clone --depth 1 "$DOTFILES_REPO" /tmp/ryoku-dots

        mkdir -p "$PERSIST_HOME/.config"
        cp -r /tmp/ryoku-dots/.config/* "$PERSIST_HOME/.config/" 2>/dev/null || true

        echo "[ryoku] Parcheando rutas Arch → NixOS..."
        find "$PERSIST_HOME/.config" -name "*.sh" -type f | while read -r script; do
          ${pkgs.gnused}/bin/sed -i \
            -e 's|/usr/bin/|/run/current-system/sw/bin/|g' \
            -e 's|/bin/|/run/current-system/sw/bin/|g' \
            -e 's|/usr/local/bin/|/run/current-system/sw/bin/|g' \
            "$script"
        done

        find "$PERSIST_HOME/.config" -name "*.sh" -type f -exec chmod +x {} \;
        chown -R biko:users "$PERSIST_HOME/.config"

        rm -rf /tmp/ryoku-dots
        echo "[ryoku] Dotfiles instalados y parcheados."
      fi
    '';
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  PAQUETES DE SISTEMA
  # ═══════════════════════════════════════════════════════════════════════

  environment.systemPackages = with pkgs; [

    # ── Hyprland Ecosystem (Dotfiles Ryoku) ──────────────────────────
    hyprland
    waybar
    rofi-wayland
    kitty
    starship
    dunst
    swww
    grimblast
    slurp
    wl-clipboard
    pamixer
    brightnessctl
    wlroots
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk

    # ── C++ Development ──────────────────────────────────────────────
    clang
    clang-tools
    gdb
    cmake
    ninja
    bear
    gnumake
    pkg-config
    lldb

    # ── System & Utils ───────────────────────────────────────────────
    git
    curl
    wget
    htop
    btop
    neovim
    unzip
    pciutils
    usbutils
    lm_sensors

    # ── NVIDIA / CUDA utils ──────────────────────────────────────────
    nvtopPackages.full
  ];

  # ═══════════════════════════════════════════════════════════════════════
  #  ALIAS — Herramientas de pentesting volátiles vía nix-shell
  # ═══════════════════════════════════════════════════════════════════════

  environment.shellAliases = {
    p-nmap        = "nix-shell -p nmap --command nmap";
    p-burpsuite   = "nix-shell -p burpsuite --command burpsuite";
    p-wireshark   = "nix-shell -p wireshark --command wireshark";
    p-metasploit  = "nix-shell -p metasploit --command msfconsole";
    p-hydra       = "nix-shell -p hydra --command hydra";
    p-john        = "nix-shell -p john --command john";
    p-sqlmap      = "nix-shell -p sqlmap --command sqlmap";
    p-gobuster    = "nix-shell -p gobuster --command gobuster";
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  LOCALE & KEYMAP
  # ═══════════════════════════════════════════════════════════════════════

  console.keyMap = "es";
  services.xserver.xkb = {
    layout = "es";
    variant = "";
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  SSH — Solo bajo demanda
  # ═══════════════════════════════════════════════════════════════════════

  services.openssh = {
    enable = false;  # Activar solo cuando se necesite
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # ═══════════════════════════════════════════════════════════════════════
  #  SYSTEM STATE VERSION
  # ═══════════════════════════════════════════════════════════════════════

  system.stateVersion = "24.11";
}