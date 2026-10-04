# configuration.nix — biko-msi (MSI Thin GF63 12VF)
#
# Escritorio:  Ryoku (Hyprland + Quickshell). Sesión ÚNICA.
#              KDE Plasma 6 y Niri han sido ELIMINADOS (tarea 6). kwin_wayland
#              se conserva sólo como compositor del greeter de SDDM, porque el
#              tema "ryoku" es QML y necesita layer-shell (Weston no lo habla).
# Hardware:    Intel i7-12650H (Alder Lake, iGPU Iris Xe  0000:00:02.0)
#              NVIDIA RTX 4060 Laptop (AD107, dGPU         0000:01:00.0)
# Pantallas:   DP-1    -> monitor externo Xiaomi "Mi Monitor" 2560x1440@180Hz (dGPU/NVIDIA)
#              eDP-1   -> panel interno 1920x1080 (iGPU/Intel) — APAGADO
#              HDMI-A-1-> sin uso (iGPU)
#
# El módulo de Ryoku (programs.ryoku) fuerza por su cuenta:
#   * programs.hyprland.enable = true  (con SU propio paquete Hyprland, ABI fija)
#   * xdg.portal, PipeWire, NetworkManager, Bluetooth, keyring, fuentes, etc.
#   * el tema "ryoku" de SDDM
# Por eso aquí NO se activa programs.hyprland a mano (se dejaría pisar por
# mkForce) ni se duplican portales.

{ config, lib, pkgs, sonoraInput, ... }:

let
  # ---------------------------------------------------------------
  # freebuff — https://freebuff.com (Codebuff). Se declara aquí, fuera del
  # attrset del módulo, porque es un paquete normal y no una opción de NixOS.
  # ---------------------------------------------------------------
# ---- freebuff: el CLI de Codebuff (tarea 11) ----
# El paquete `freebuff` de npm no es el programa en sí: es un lanzador en Node
# que descarga el binario de la plataforma, lo verifica con los sha256 que
# lleva incrustados y lo cachea en ~/.config/manicode. Se empaqueta aquí con
# buildNpmPackage (lock file incluido, build reproducible) y se mete en el PATH
# del sistema, de modo que `freebuff` funciona en cualquier terminal sin que
# haya que tocar npm a mano.
freebuff = pkgs.buildNpmPackage {
  pname = "freebuff";
  version = "0.1.0";
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/freebuff/-/freebuff-0.1.0.tgz";
    hash = "sha256-n8ebInVWlQmpgobP/lEhUk8lB0eQcuRLXq8wB2IPOOQ=";
  };
  sourceRoot = "package";
  # El tarball de npm no trae package-lock.json; se vendoriza para que las
  # dependencias (tar@7 y sus 5 submódulos) queden fijadas.
  postPatch = ''
    cp ${./freebuff/package-lock.json} package-lock.json
  '';
  npmDepsHash = "sha256-orYqbpM06isyiJMTYL72iHFMhxDOlVXgdBYW9tVRoYU=";
  dontNpmBuild = true; # el paquete no tiene script de build
  nativeBuildInputs = [ pkgs.makeWrapper ];

  # El paquete publica sólo 5 ficheros ("files" en package.json) más el `tar@7`
  # que necesita el lanzador para descomprimir el binario real. Se copia la
  # lista exacta en vez de usar el installPhase genérico de buildNpmPackage: ese
  # hace `cp -r node_modules $out/lib/node_modules/freebuff/node_modules` y falla
  # si el bucle anterior de `npm pack --dry-run` no llegó a crear el directorio
  # padre ("cannot create directory ... No such file or directory").
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/freebuff $out/bin
    cp index.js launcher.js http.js package.json $out/libexec/freebuff/
    cp -r node_modules $out/libexec/freebuff/node_modules
    chmod +x $out/libexec/freebuff/index.js
    ln -s $out/libexec/freebuff/index.js $out/bin/freebuff
    runHook postInstall
  '';

  # El lanzador es un script de Node con shebang `#!/usr/bin/env node`: sin node
  # en el PATH no arranca. Se fija nodejs_24 (el mismo que programs.npm usa).
  #
  # Y el binario que descarga (48 MB, en ~/.config/manicode/freebuff) es un
  # ELF enlazado contra la glibc genérica, que NixOS no puede ejecutar tal cual
  # ("Could not start dynamically linked executable"). Se resuelve con nix-ld
  # (programs.nix-ld.enable, más abajo) + NIX_LD_LIBRARY_PATH apuntando a la
  # glibc del store, que es el mecanismo estándar en NixOS para binarios
  # precompilados de terceros.
  postFixup = ''
    wrapProgram $out/bin/freebuff \
      --prefix PATH : ${pkgs.nodejs_24}/bin \
      --set NIX_LD_LIBRARY_PATH "${lib.makeLibraryPath [ pkgs.glibc ]}"
  '';

  meta = {
    description = "Free AI coding agent for the terminal, by Codebuff";
    homepage = "https://freebuff.com";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "freebuff";
  };
};
in
{
  imports = [ ./hardware-configuration.nix ./hardware-tuning.nix ];

  # ============================================================
  # ARRANQUE
  # ============================================================
  # ------------------------------------------------------------
  # Bootloader: Limine, en sustitución de systemd-boot.
  # Limine arranca directamente el kernel EFI-stub de cada generación de
  # NixOS (genera una entrada por generación automáticamente) y hace
  # chainload al Windows Boot Manager para el otro sistema.
  # ------------------------------------------------------------
  boot.loader.limine = {
    enable = true;
    # Sólo la generación actual en el menú de Limine. Para volver atrás: los
    # toplevels siguen en /nix/store (mientras no los borre el GC) y siempre
    # queda el fallback de NVRAM "UEFI OS" (\EFI\BOOT\BOOTX64.EFI).
    maxGenerations = 1;

    # Wallpaper del menú = el wallpaper actual del escritorio (Ryoku/ryogami,
    # ver ~/.cache/ryogami/outputs.json). Se consume como store path.
    style.wallpapers = [
      ./wallpapers/boot-wallpaper.png
    ];
    style.backdrop = "000000";

    # Limine escribe por su cuenta las entradas de NixOS. Aquí sólo se añade
    # la de Windows: chainload al Boot Manager de Microsoft en la ESP.
    # (2026-09-28: el BCD fue regenerado con bcdboot desde un Win11 USB y ya
    # es un store completo y válido; ver HANDOFF §12 para la historia.)
    extraEntries = ''
      /Windows
          protocol: efi_chainload
          path: boot():///EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };

  # Limine también en \EFI\BOOT\BOOTX64.EFI (fallback "UEFI OS" del firmware,
  # primero en BootOrder). Seguro: un rebuild futuro sobreescribe ese mismo
  # fichero, nunca borra la entrada NVRAM de Windows.
  boot.loader.limine.efiInstallAsRemovable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ------------------------------------------------------------
  # Kernel: el de nixpkgs (6.18.x).  NO usar linuxPackages_latest (7.x):
  # el driver NVIDIA empaquetado en nixpkgs no compila contra 7.x y
  # `nixos-rebuild` fallaría construyendo nvidia-open. Si algún día nixpkgs
  # trae un driver que soporte 7.x, se puede volver a `linuxPackages_latest`.
  # ------------------------------------------------------------
  boot.kernelPackages = pkgs.linuxPackages;

  boot.kernelParams = [
    # Modo KMS del driver NVIDIA (obligatorio para el backend Wayland).
    "nvidia_drm.modeset=1"
    # Necesario para suspend/resume correcto con el driver propietario.
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    # Firmware GSP, obligatorio en la dGPU desde la rama 550 (Ada lo exige).
    "nvidia.NVreg_EnableGpuFirmware=1"
    # Tarea 8: en un portátil SIEMPRE enchufado, la gestión dinámica de
    # clock/power de las dGPU móviles (NVreg_MobileEnableGpuPowerManagement)
    # sólo sirve para bajar relojes y recortar potencia. Desactivada: la
    # RTX 4060 se queda en su perfil de máximo rendimiento.
    "nvidia.NVreg_MobileEnableGpuPowerManagement=0"

    # ---- Tarea 2 + 4: la salida por defecto del kernel es el monitor externo ----
    # Fuerza DP-1 (conector de la NVIDIA) a 2560x1440@180Hz y lo marca como
    # salida de consola primaria: Plymouth, el menú de arranque, SDDM y el
    # framebuffer de depuración se dibujan en el monitor externo. La "e" final
    # significa "force enabled": si el EDID fallara, el driver reintenta igual.
    "video=DP-1:2560x1440@180e"

    # ---- Tarea 8: menos latencia de entrada y menos jitter de render ----
    # nohz_full + rcu_nocbs sacan el housekeeping del kernel fuera del camino
    # crítico de la scheduler clock, reduciendo la latencia de teclado y el
    # jitter de fotogramas. Coste: un núcleo de CPU ociosa. En un portátil que
    # NUNCA se desenchufa, ese núcleo se paga sólo en fluidez.
    "nohz_full=1-15"
    "rcu_nocbs=1-15"
  ];

  # Plymouth como pantalla de arranque (tarea 4). Se dibuja sobre la salida
  # forzada arriba, o sea, en el monitor externo.
  boot.plymouth.enable = true;
  boot.plymouth.theme = "spinner";

  # ============================================================
  # GRÁFICAS — híbridas Intel + NVIDIA
  # ============================================================
  hardware.graphics.enable = true;

  # Esta lista es la que realmente enciende el driver propietario.
  # `modesetting` cubre la iGPU Intel y `nvidia` la dGPU (RTX 4060).
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  hardware.nvidia = {
    # Ada (RTX 40xx) usa los módulos de kernel abiertos.
    open = true;

    # KMS: imprescindible para Wayland/Hyprland.
    modesetting.enable = true;

    # Tarea 8: como el portátil nunca se desenchufa, no tiene sentido apagar la
    # dGPU en idle (RTD3). El monitor externo está cableado a la NVIDIA (DP-1),
    # así que la dGPU nunca está realmente inactiva: cada wake costaría más
    # energía y más latencia de lo que ahorra.
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Tarea 3: se conservan los comandos de PRIME para lanzar algo puntual con
    # `nvidia-offload`. El compositor ya lo fija Ryoku a la dGPU (ver gpu.lua).
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";   # 0000:00:02.0 Intel Alder Lake-P
      nvidiaBusId = "PCI:1:0:0";  # 0000:01:00.0 NVIDIA AD107
    };
  };

  # Tarea 3 — "renderizar con la GPU, no con los gráficos integrados".
  # Ryoku lo hace de forma declarativa: su autostart ejecuta `ryoku-gpu persist`,
  # que escribe ~/.config/hypr/gpu.lua con un hl.env("AQ_DRM_DEVICES", ...)
  # fijando la NVIDIA (0000:01:00.0) como renderizador principal y dejando la
  # Intel detrás para el reverse-PRIME de los conectores que no lleva la dGPU.
  # Verificado en caliente: Hyprland tiene cargadas libEGL_nvidia y
  # libnvidia-eglcore, y su render node primario es /dev/dri/renderD128
  # (0000:01:00.0), no el renderD129 de Intel.

  # ============================================================
  # RED
  # ============================================================
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # SSH: imprescindible para administrar la máquina en remoto. NO quitar.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # ============================================================
  # LOCALIZACIÓN / CONSOLA
  # ============================================================
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "es_ES.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_ES.UTF-8";
    LC_IDENTIFICATION = "es_ES.UTF-8";
    LC_MEASUREMENT = "es_ES.UTF-8";
    LC_MONETARY = "es_ES.UTF-8";
    LC_NAME = "es_ES.UTF-8";
    LC_NUMERIC = "es_ES.UTF-8";
    LC_PAPER = "es_ES.UTF-8";
    LC_TELEPHONE = "es_ES.UTF-8";
    LC_TIME = "es_ES.UTF-8";
  };
  console.keyMap = "es";

  # ============================================================
  # SESIONES GRÁFICAS / DISPLAY MANAGER
  # ============================================================
  # X server disponible: lo necesitan XWayland y el driver NVIDIA.
  services.xserver.enable = true;

  # ------------------------------------------------------------
  # TAREA 1 — TECLADO EN ESPAÑOL CON "ñ" Y "ç"
  # ------------------------------------------------------------
  # El mapa XKB "es" (el de España, no el de América) trae ya las dos teclas:
  # "ñ" en su tecla estándar y "ç" en la tecla izquierda del 1 (ISO <BKSL>),
  # más "Ccedilla" con Mayús. No hace falta ninguna variante.
  # Hyprland se configura aparte en ~/.config/hypr/keyboard.lua porque lee las
  # reglas de libinput directamente, no el estado de XKB.
  services.xserver.xkb = {
    layout = "es";
    model = "pc105"; # teclado español: incluye la tecla extra junto a L Shift
    variant = "";
    options = "grp:alt_shift_toggle,terminate:ctrl_alt_bksp";
  };

  # SDDM: es el greeter que Ryoku tematiza (tema "ryoku").
  services.displayManager.sddm.enable = true;

  # Hyprland (Ryoku) por defecto.
  services.displayManager.defaultSession = "hyprland";

  # ------------------------------------------------------------
  # TAREA 6 — KDE PLASMA Y NIRI ELIMINADOS
  # ------------------------------------------------------------
  # Plasma 6 desactivado: desaparece de las sesiones de SDDM y con él se van
  # plasma-workspace, plasma-widgets, dolphin, konsole... y varios GiB del store.
  # IMPORTANTE: en nixpkgs es services.desktopManager.plasma6.enable lo que pone
  # sddm.wayland.compositor = "kwin" (plasma6.nix:319). Si se desactiva sin fijar
  # el compositor aquí, el greeter cae a Weston y el tema QML "ryoku" (que usa
  # layer-shell) se queda en negro, es decir, sin pantalla de inicio. Por eso el
  # compositor del greeter se fija explícitamente a kwin: sólo se conserva el
  # binario kwin_wayland, no el escritorio.
  services.desktopManager.plasma6.enable = false;
  services.displayManager.sddm.wayland = {
    enable = true;
    compositor = "kwin";
  };

  # Niri: el módulo de Ryoku lo activa con un `enable = true` plano (no es una
  # opción de cfg), así que hace falta mkForce para pisarlo.
  programs.niri.enable = lib.mkForce false;

  # ------------------------------------------------------------------------
  # TAREA 6 (bis) — que Niri no aparezca en la lista de sesiones de SDDM
  # ------------------------------------------------------------------------
  # Lo que SÍ se ha eliminado del todo: KDE Plasma. `plasma.desktop` ya no está
  # en el directorio de sesiones y con él se fueron plasmawayland, dolphin,
  # konsole y varios GiB del store.
  #
  # Lo que NO se puede quitar sin tocar el closure: el BINARIO de niri
  # (`niri-26.04`, 771 MiB) y el lanzador `ryoku-wm-niri`. El módulo de Ryoku los
  # mete en dos listas SUYAS y sin condición (nix/modules/ryoku.nix):
  #     runtimePackages = [ … ryokuWmNiri ryokuNiri … ]  -> systemPackages
  #     sessionPackages = [ ryokuNiri ]                   -> sessionPackages
  # Poner `programs.niri.enable = false` de arriba sólo apaga el módulo de
  # nixpkgs, no esas dos listas, así que el binario sigue en el closure.
  #
  # `environment.systemPackages` no se puede limpiar: las opciones de lista de
  # NixOS se CONCATENAN entre módulos, así que no existe forma declarativa de
  # "quitar" una entrada que otro módulo ya añadió (ni mkAfter, ni mkPriority,
  # ni mkOrder). Intentado con lib.mkRenamedOptionModule y no vale: esa función
  # va en el sentido antiguo->nuevo y exige que el nombre de destino YA exista,
  # así que no sirve para capturar una lista ya fusionada. Quitar niri del
  # store exigiría parchear el módulo de Ryoku, y entonces `ryoku update`
  # dejaría de funcionar.
  #
  # `services.displayManager.sessionPackages` sí se puede: es una lista normal
  # con `default = [ ]`, y de ella saca nixpkgs las sesiones que SDDM muestra
  # (sessionData.desktops se construye recorriéndola). Se sustituye entera con
  # mkForce dejando sólo Hyprland, que es el compositor de este equipo.
  # `config.programs.hyprland.package` es el Hyprland de Ryoku (el módulo lo
  # fuerza con mkForce para clavar la ABI de sus plugins), así que se conserva
  # el binario correcto en vez de tirar del Hyprland de nixpkgs.
  services.displayManager.sessionPackages = lib.mkForce [
    config.programs.hyprland.package
  ];


  # Táctil/touchpad (portátil).
  services.libinput.enable = true;

  # ============================================================
  # AUDIO
  # ============================================================
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # OJO: `services.pipewire.config` ya no existe en este nixpkgs (está retirado y
  # lanza una aserción). Las personalizaciones van como drop-in en
  # /etc/pipewire/pipewire.conf.d, y cada clave del attrset es el nombre de uno
  # de esos ficheros.
  services.pipewire.extraConfig.pipewire = {
    # Prefijo 50- para que se cargue DESPUÉS de la configuración de fábrica.
    "50-biko-calidad-audio" = {
      "context.properties" = {
        # 48 kHz es la frecuencia nativa del ALC256 a través de SOF; subirla a
        # 96/192 kHz NO mejora nada y añade diafonía y ruido digital.
        "audio.rate" = 48000;
        # El mezclador del HDA se queda en estéreo real: sin _downmix_ a mono,
        # que es lo que arruina un auricular de verdad.
        "audio.mono" = false;
        # Se anuncia lo que el hardware es capaz de hacer, para que PipeWire no
        # tenga que reescribir formatos a un estándar que nadie usa.
        "audio.allowed-rates" = [
          44100
          48000
          88200
          96000
          192000
        ];
      };
    };

    # ------------------------------------------------------------
    # Sumidero virtual del visualizador de audio (cava)
    # ------------------------------------------------------------
    # Los visualizadores de Ryoku (el de la píldora y el del escritorio) lanzan
    # cava con `method = pipewire` y `source = auto`, y en cava `auto` significa
    # "el monitor del sumidero PREDETERMINADO". No existe ninguna opción de
    # "analiza sólo esta aplicación": lo único que se puede elegir es qué acaba
    # dentro de ese monitor.
    #
    # De ahí este montaje: un loopback que se hace pasar por tarjeta de sonido y
    # pasa a ser el sumidero predeterminado. Todo lo que suena entra en él, su
    # monitor es lo que cava analiza, y la parte de reproducción reenvía la misma
    # señal al jack, así que se sigue oyendo igual. Discord (equibop) queda FUERA
    # del monitor porque sus streams se mueven directamente al hardware con
    # biko-discord-route (hardware-tuning.nix); sin eso las barras bailarían con
    # las notificaciones del chat en lugar de con la música.
    #
    # Se usa `libpipewire-module-loopback` con `media.class = Audio/Sink` (el
    # "virtual sink" de la documentación de PipeWire) y NO un `support.null-audio-
    # sink`, aunque este último sea el patrón habitual para cava: medido en esta
    # máquina, cava se enlaza al monitor del sumidero nulo pero lee SILENCIO
    # (source=auto sobre el nulo => 0.00 de nivel con un tono de prueba sonando,
    # mientras `pw-record -P stream.capture.sink=true` sí leía ~-10 dBFS de ese
    # mismo monitor). Con el loopback, cava lee el tono con exactamente el mismo
    # nivel que leía del monitor del jack.
    #
    # Y hay que crearlo aquí y no con `pactl load-module`: un módulo cargado a
    # mano no sobrevive a un reinicio de PipeWire (ni al que hace cada
    # `nixos-rebuild switch`).
    "60-ryoku-visualizer" = {
      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Ryoku Visualizer";
            # Lado de captura: es el sumidero virtual propiamente dicho. Al
            # declararlo Audio/Sink, cualquier aplicación lo ve como una salida
            # normal y puede elegirlo (y lo hará, porque es el predeterminado).
            # Su volumen es el mando que acaba de tocar el usuario: baja la señal
            # que sale hacia el lado de reproducción, que es la que se oye.
            "capture.props" = {
              "node.name" = "ryoku_visualizer";
              "media.class" = "Audio/Sink";
              "audio.position" = [ "FL" "FR" ];
            };
            # Lado de reproducción: entrega lo capturado al jack, que es lo único
            # que suena de verdad. `node.passive` deja el sumidero de hardware
            # suspendido mientras no haya nada sonando.
            #
            # `node.dont-reconnect = true` fija ese destino: sin él, si el nodo
            # del jack no apareciera, WirePlumber enlazaría el loopback al
            # sumidero PREDETERMINADO -- que es el virtual -- y se realimentaría
            # consigo mismo.
            "playback.props" = {
              "node.name" = "ryoku_visualizer.out";
              "audio.position" = [ "FL" "FR" ];
              "target.object" = "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Headphones__sink";
              "node.dont-reconnect" = true;
              "stream.dont-remix" = true;
              "node.passive" = true;
            };
          };
        }
      ];
    };
  };

  # ------------------------------------------------------------
  # FONDOS DE PANTALLA — dónde los busca el selector de Ryoku
  # ------------------------------------------------------------
  # ryogami-wall (el selector de fondos de Ryoku, detrás de Super+W) resuelve el
  # directorio como `$XDG_PICTURES_DIR/Wallpapers`, que con el locale en español
  # es ~/Imágenes/Wallpapers; el materializador de Ryoku, en cambio, siembra los
  # fondos en ~/Pictures/Wallpapers. Sin unir los dos, el selector construye
  # rutas que no existen y "elegir otro fondo" no hace absolutamente nada (en
  # ~/.cache/ryogami/wall-ui.log se ve "wallpaper apply failed: wallpaper not
  # readable: stat .../Imágenes/Wallpapers/...: no such file or directory").
  # El enlace se recrea en cada arranque (`L+`), así que sobrevive a que Ryoku
  # vuelva a materializar el escritorio en cada login.
  systemd.tmpfiles.rules = [
    "d /home/biko/Imágenes 0755 biko users -"
    "L+ /home/biko/Imágenes/Wallpapers - - - - /home/biko/Pictures/Wallpapers"
  ];

  # No se fuerza ningún "route": la detección de jack del ALC256 (services.pipewire.alsa
  # la deja activa) ya conmuta de altavoz a auriculares y del micro interno al
  # del jack en cuanto se enchufan los cascos.
  #
  # Las ganancias finas de micro y jack, y los sinks/sources por defecto (que
  # necesitan acceso al control ALSA real), están en hardware-tuning.nix.

  # ============================================================
  # IMPRESIÓN
  # ============================================================
  services.printing.enable = true;

  # ============================================================
  # USUARIO
  # ============================================================
  users.users."biko" = {
    isNormalUser = true;
    description = "Biko Flacón Martínez";
    # "video" da acceso a /dev/dri (necesario para hyprctl, drm_info, etc.).
    # "input" da acceso a /dev/input para el control ALSA de bajo nivel.
    extraGroups = [ "networkmanager" "wheel" "video" "input" ];
    packages = with pkgs; [
      kdePackages.kate
      btop
    ];
  };

  # ============================================================
  # TAREA 11 — PROGRAMAS
  # Todo lo de esta lista entra en el PATH del sistema
  # (/run/current-system/sw/bin), así que está disponible para cualquier
  # usuario, para el login de SDDM y para las shells de fish y zsh.
  # ============================================================
  environment.systemPackages = with pkgs; [
    # ---- Automatización de escritorio (para el agente OpenClaw) ----
    # ydotool inyecta eventos de ratón/teclado por /dev/uinput. Es lo que
    # permite al agente hacer clic en coordenadas reales dentro de una app.
    # El daemon lo levanta ~/.config/systemd/user/ydotoold.service.
    ydotool
    # ---- Terminal y diagnóstico ----
    fastfetch
    btop
    nvtopPackages.full # monitor de GPU/NVIDIA
    pciutils
    usbutils
    lm_sensors # temperaturas y ventiladores
    smartmontools # SMART del NVMe (tarea 10)
    nvme-cli
    atop
    htop
    tree
    ripgrep
    fd
    bat
    jq
    curl
    wget
    fzf
    eza
    zoxide
    git
    git-lfs
    github-cli
    direnv
    manix # páginas de man resumidas
    tealdeer # cheat sheets de comandos
    ffmpeg
    yt-dlp
    unzip
    p7zip
    brightnessctl
    ddcutil # brillo de monitores externos por DDC/CI
    imagemagick

    # ---- Editores ----
    neovim
    helix
    kdePackages.kate # tarea 11: KWrite. KWrite ya no es un paquete propio;
    # se compila dentro de `kate` y ambos binarios ($out/bin/kate y
    # $out/bin/kwrite) entran al PATH del sistema al añadirlo aquí.
    marktext

    # ---- Navegador y comunicación ----
    firefox
    discord # tarea 11 (necesita nixpkgs.config.allowUnfree)
    equibop # tarea 11: cliente de Bluesky
    thunderbird

    # ---- Música y vídeo ----
    # Task 11: Sonora no está en nixpkgs, así que se usa el binario oficial
    # publicado por su propio flake. `sonoraInput` lo inyecta el flake.nix vía
    # specialArgs (nada más puede ver los inputs del flake).
    sonoraInput.packages.${pkgs.stdenv.hostPlatform.system}.default
    celluloid

    # ---- Asistentes de código (tarea 11) ----
    # `freebuff` es el binding del `let` de arriba, no un atributo de pkgs: los
    # bindings del `let` tienen prioridad sobre el `with pkgs`, así que aquí
    # sigue resolviéndose al paquete del `let`.
    freebuff

    # ---- Descargas y red ----
    # aria2 también queda como demonio (services.aria2 más abajo); aquí se
    # instala el binario para poder invocarlo a mano desde la terminal.
    aria2
    cloudflare-warp

    # ---- Mensajería ----
    # El atributo de nixpkgs es `ayugram-desktop`, NO `ayugram`. Cliente de
    # Telegram basado en TDesktop, con historial local y funciones extra.
    ayugram-desktop

    # ---- Escritorio ----
    grim
    slurp
    swappy
    papirus-icon-theme
    kdePackages.kdegraphics-thumbnailers
  ];

  programs.npm = {
    enable = true;
    package = pkgs.nodejs_24;
  };

  # nix-ld: hace ejecutables los ELF de terceros que vienen enlazados contra una
  # glibc "genérica" (no contra una ruta del /nix/store). Sin esto, el binario
  # que descarga el lanzador de freebuff no arranca. `libraries` se deja el
  # valor por defecto de nixpkgs, que ya incluye glibc.
  programs.nix-ld.enable = true;

  # Programas de Nix declarativos (crean su propio .desktop).
  programs.firefox.enable = true;
  # btop y kwrite no tienen módulo declarativo (`programs.btop` / `programs.kde`)
  # en este nixpkgs: se instalan como paquetes normales en
  # environment.systemPackages y en el perfil del usuario.
  # OJO: en este nixpkgs el bloque de ajustes de git se llama `config`
  # (antes era `settings`).
  programs.git = {
    enable = true;
    config = {
      color.ui = "auto";
      init.defaultBranch = "main";
      pull.rebase = true;
      core.editor = "kwrite";
    };
  };


  # opencode ya venía instalado por Ryoku; se deja constancia de que forma
  # parte del conjunto solicitado en la tarea 11.
  environment.variables.OPENCODE_DISABLE_AUTOUPDATE = "0";

  # ============================================================
  # AUTOMATIZACIÓN DE ESCRITORIO (ratón para el agente)
  # ============================================================

  # Por defecto /dev/uinput es crw------- root:root, o sea que sólo root puede
  # inyectar eventos de teclado y ratón. Por eso ydotool arrancaba y a la vez
  # fallaba con "Failed to initialize kernel module /dev/uinput: Permission
  # denied". Con `uaccess` el asiento gráfico abre el nodo al usuario con
  # sesión activa, y con GROUP=input+MODE=0660 queda accesible a biko, que ya
  # está en ese grupo.
  #
  # OJO, y es deliberado: esto permite inyectar teclado y ratón en TODO el
  # escritorio. Es la misma capacidad que un keylogger. Está aquí porque el
  # agente (OpenClaw) lo necesita para hacer clic en menús y apps, y el
  # propietario de la máquina lo ha autorizado. Si algún día hay canales
  # externos (Telegram, Discord) conectados a OpenClaw, quitar estas tres
  # líneas: un mensaje de fuera ya podría escribir en la sesión.
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"
  '';

  # ============================================================
  # DESCARGAS (aria2) + WARP + MENSAJERÍA
  # ============================================================

  # aria2 como demonio persistente: así sobrevive a cerrar la terminal, que es
  # justo el motivo de usar aria2 en vez de wget/curl. La función `download` de
  # fish (en ~/.config/fish/functions/download.fish) lo llama por RPC.
  services.aria2 = {
    enable = true;
    # El módulo ya abre el puerto RPC en el firewall y lo pone a escuchar sólo
    # en localhost, así que no hace falta tocar openPorts aquí.
    #
    # El módulo exige un fichero con el secreto (no acepta el ajuste en la
    # configuración, para que no acabe en el store legible por todos). Se
    # genera una vez y se reutiliza; root:biko 0640 para que el usuario pueda
    # leerlo y hablar con el demonio por RPC.
    rpcSecretFile = "/etc/aria2/rpc-secret";
    # NO tocar downloadDirPermission: ese valor va en el `d` de un tmpfiles
    # rule, o sea que es el modo del DIRECTORIO de descargas. Ponerle 0644
    # (que es un modo de fichero) deja el directorio sin bit de ejecución y
    # aria2 falla al crear dentro con
    #   Failed to open the file .../Downloads/x.dat, cause: Permiso denegado
    # El default del módulo, 0770, es lo correcto.
  };

  # Cloudflare WARP (Zero Trust). El módulo trae el cliente y abre el UDP 2408
  # que usa para el túnel.
  #
  # OJO: instalar el servicio NO es lo mismo que estar conectado. La primera
  # vez hay que accepting los términos y registrarse, y eso es interactivo
  # (implica navegador y/o correo), así que no se puede automatizar desde aquí:
  #   sudo warp-cli registration new            # alta de la organización
  #   warp-cli --accept-tos registration new    # si prefieres hacerlo como usuario
  #   warp-cli connect
  # Con eso el servicio queda en modo Warp y el tráfico sale por Cloudflare.
  services.cloudflare-warp.enable = true;

  # ============================================================
  # NIX
  # ============================================================
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "biko" ];

    # Compilación en paralelo completa (reconstrucciones más rápidas).
    max-jobs = "auto";
    cores = 0; # 0 = usa todos los núcleos disponibles
    log-lines = 0;

    # ---- Tarea 5: liberar espacio ----
    # GC automático semanal: borra generaciones y paths del store que no estén
    # en uso y tengan más de 14 días. Sin esto /nix crece sin límite. Las raíces
    # por defecto de NixOS (/nix/var/nix/gcroots + los perfiles) ya cubren el
    # perfil del sistema y los perfiles de usuario.
    warn-dirty = false;
  };

  # OJO: en este nixpkgs el bloque de GC es `nix.gc` (de nivel superior), no
  # `nix.settings.gc` (que aquí sigue siendo un átomo libre y no admite attrsets).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "1h";
    options = "--delete-older-than 14d";
  };

  # El manual HTML de NixOS son ~600 MiB de HTML estático que aquí no se usan.
  # Desactivarlo es de las dos o tres cosas que más espacio liberan en NixOS.
  documentation.nixos.enable = false;
  # Las páginas de man SÍ se dejan: ocupan poco y se consultan de verdad.
  documentation.man.enable = true;

  # ============================================================
  # WORKAROUND — incompatibilidad Ryoku <-> nixpkgs reciente
  # El módulo de Ryoku escribe:
  #   environment.etc."systemd/user/xdg-desktop-portal-gnome.service.d/10-ryoku.conf"
  # pero en nixpkgs reciente /etc/systemd/user es un SYMLINK al store, así que
  # crear un directorio anidado bajo él rompe la construcción de la derivación
  # `etc` con:
  #   mkdir: cannot create directory
  #     '.../etc/systemd/user/xdg-desktop-portal-gnome.service.d': Permission denied
  # Sigue haciendo falta aunque Niri esté eliminado: la entrada la escribe el
  # módulo de Ryoku, no Niri. Con Hyprland la entrada es irrelevante.
  environment.etc."systemd/user/xdg-desktop-portal-gnome.service.d/10-ryoku.conf".enable = false;

  # ============================================================
  # HARDWARE / FIRMWARE
  # ============================================================
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # ---- Tarea 7: drivers ----
  #   i915 + modesetting  -> Intel UHD (controlador interno, PRIME/render-offload)
  #   nvidia-open          -> RTX 4060 (Ada usa los módulos abiertos)
  #   snd_hda_intel + sof_hda_dsp -> Realtek ALC256 (micrófono y jack 3.5 mm)
  #   iwlwifi              -> Intel AX211 Wi-Fi (firmware vía enableRedistributable)
  #   r8169                -> Realtek RTL8111 Ethernet con cable
  #   nvme                 -> SN740 NVMe
  # Todos vienen ya en el initrd y en el sistema por hardware.enableRedistributable
  # + hardware.graphics; lo que se añade aquí es no estorbarles.
  # El firmware de la Intel AX211 (Wi-Fi) y el de la webcam UVC entran solos con
  # hardware.enableRedistributableFirmware: no hay option hardware.wireless que
  # tocar en este nixpkgs.
  hardware.bluetooth.enable = true; # AX211 (CNVi): el Bluetooth va por USB interno

  # NVMe: TRIM periódico (mantiene el rendimiento del SSD a largo plazo).
  services.fstrim.enable = true;

  # ============================================================
  # VERSIÓN DE ESTADO (NO cambiar: es la versión de instalación del sistema)
  # ============================================================
  system.stateVersion = "26.05";
}
