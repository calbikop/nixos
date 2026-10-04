# hardware-tuning.nix — ajustes de hardware para el MSI Thin GF63 12VF
#
# Recopila TODO lo que es específico de esta máquina y que no es "configuración
# de escritorio". Está separado de configuration.nix a propósito: así se puede
# revisar o revertir el bloque de rendimiento de un vistazo.
#
# Premisa del usuario: el portátil NUNCA se desconecta de la corriente. Eso
# cambia por completo el cálculo energía/latencia: casi todos los trucos de
# "ahorro de energía" de un portátil sólo sirven para hacer el sistema más lento
# sin ahorrar nada que nadie valores. Aquí se prioriza latencia y fluidez.
#
# Contenido:
#   1. Tarea 2 + 4: panel interno (eDP-1) apagado de verdad, desde el arranque.
#   2. Tarea 3: la NVIDIA como GPU principal ya la fija Ryoku (gpu.lua); aquí se
#      dejan las herramientas de ofload y se limpia lo que estorba.
#   3. Tarea 7: carga de los módulos que faltan (sensores, ALSA utils, ethtool).
#   4. Tarea 8: rendimiento (CPU, GPU, disco) sin ahorro de energía.
#   5. Tarea 9: calidad de audio (micrófono y jack 3.5 mm).
#   6. Tarea 10: lo que hace falta para poder diagnosticar (SMART, sensores).

{ config, lib, pkgs, ... }:

let
  inherit (lib) mkIf;

  # Nombres de las rutas sysfs del panel interno y del NVMe en ESTA máquina.
  internalPanelBacklight = "/sys/class/backlight/intel_backlight";

  audioTuning = pkgs.writeShellScript "biko-audio-quality" ''
    set -euo pipefail

    AMIXER=${pkgs.alsa-utils}/bin/amixer
    CARD=1 # sof-hda-dsp -> Realtek ALC256 (la Intel UHD no tiene codec de audio)

    # El codec puede tardar un instante en aparecer tras cargar el SOF.
    for _ in $(seq 1 30); do
      [ -e "/dev/snd/controlC''${CARD}" ] && break
      sleep 0.2
    done

    # ------------------------------------------------------------------
    # AURICULARES DEL JACK 3.5 mm  (pines 0x03214020 "HP Out at Ext Left")
    # ------------------------------------------------------------------
    # El amplificador de auriculares del ALC256 venía a -23.25 dB (64 %) y el
    # software de PipeWire bajaba el volumen al 40 %: es el peor reparto posible,
    # porque se pierde señal por las dos etapas y además se recorta rango
    # dinámico. Se sube el hardware a -6.75 dB (78/87, "90 %") y se deja el
    # software al 100 %: el pipeline queda con ~7 dB de recorrido antes de tocar
    # el CODEC, que es donde el amplificador empieza a distorsionar.
    $AMIXER -q -c "$CARD" sset Headphone 90% unmute || true
    $AMIXER -q -c "$CARD" sset Headphone immute || true

    # Los PGA de salida se quedan en 0 dB: son ganancia previa, no volumen.
    $AMIXER -q -c "$CARD" sset 'PGA1.0 1 Master' 0% || true
    $AMIXER -q -c "$CARD" sset 'PGA30.0 30' 0% || true
    $AMIXER -q -c "$CARD" sset 'PGA31.0 31' 0% || true

    # ------------------------------------------------------------------
    # MICRÓFONO
    # ------------------------------------------------------------------
    # Dos micros: Mic1 = el del jack analógico (cádec pin 0x03a19030
    # "Mic at Ext Left"), Mic2 = el array digital interno (DMIC, Dmic0).
    #
    # Rangos reales del ALC256 de esta máquina (leídos con `amixer get`):
    #   Mic Boost : pasos 0-3   -> 0 / 10 / 20 / 30 dB
    #   Capture   : pasos 0-63  -> -30 dB .. +30 dB aprox. (21 = -1.50 dB,
    #                              42 = +14.25 dB, 63 = ~+30 dB)
    #   Dmic0     : pasos 0-70  -> 0 .. +20 dB (60 = +10 dB, 70 = +20 dB)
    #
    # La cadena venía en Mic Boost 30 dB + Capture 30 dB = 60 dB de ganancia
    # analógica. Con hablar normal a 10-20 cm eso satura el preamp y el micro
    # clipea, que se oye PEOR que un micro con menos ganancia.
    #
    # Se reparte a 20 dB (Mic Boost) + 14.25 dB (Capture) = 34.25 dB, que es el
    # punto dulce para un micro de auriculares analógico (micros de capacidades
    # reales necesitan 30-35 dB) y sigue con ~26 dB de margen antes de saturar.
    $AMIXER -q -c "$CARD" sset 'Mic Boost' 2 unmute || true    # paso 2 = 20.00 dB
    $AMIXER -q -c "$CARD" sset Capture 42 unmute || true       # 67 % = +14.25 dB
    $AMIXER -q -c "$CARD" sset 'PGA2.0 2 Master' 0% || true

    # El array digital interno (DMIC) es bastante más silencioso que un micro de
    # jack, así que va a su máximo útil: 70 = +20 dB. Con 60 (+10 dB) se oye
    # apagado; con 70 hay voz clara sin llegar a saturar.
    $AMIXER -q -c "$CARD" sset Dmic0 70 || true

    # Auto-Mute: el ALC256 corta la salida cuando se desenchufa el jack. Es lo
    # que evita el "pop" y el zumbido de la salida al insertar el conector.
    #
    # OJO: es un control ENUM, no booleano. Por eso:
    #   * `cset 'Auto-Mute Mode' on` falla con "Wrong control identifier"
    #     (los enums de amixer no aceptan on/off, hay que pasar el Item tal cual);
    #   * el valor válido es 'Enabled' en mayúscula, no 'enabled' ni 'on'.
    $AMIXER -q -c "$CARD" sset 'Auto-Mute Mode' Enabled || true

    # ------------------------------------------------------------------
    # aquí NO se toca wpctl, y es deliberado (ver comentario en los servicios)
    # ------------------------------------------------------------------
  '';

  pipewireDefaults = pkgs.writeShellScript "biko-audio-defaults" ''
    set -uo pipefail

    # Espera a que la sesión de audio del usuario exista (la levanta WirePlumber
    # al hacer login gráfico). Reintenta durante un minuto por si el arranque va
    # lento o el compositor tarda en arrancar.
    for _ in $(seq 1 120); do
      wpctl status >/dev/null 2>&1 && break
      sleep 0.5
    done

    # `wpctl status` imprime el árbol de la sección Audio con este formato:
    #   ├─ Sinks:
    #   │  *   50. <descripción> [vol: 1.00]
    # Elegir por DESCRIPCIÓN y no por índice es legible y sobrevive a que
    # aparezca o desaparezca otro dispositivo.
    #
    #   $1 = sección (sink|source), $2 = texto buscado, $3 = texto a evitar
    pick() {
      wpctl status 2>/dev/null | awk -v sect_want="$1" -v want="$2" -v avoid="$3" '
        /Sinks:/   { sect = "sink";   next }
        /Sources:/ { sect = "source"; next }
        /^Video/   { sect = "";       next }
        sect != sect_want { next }
        match($0, /[0-9]+\./) {
          id = substr($0, RSTART, RLENGTH - 1)
          if (index($0, want) > 0 && (avoid == "" || index($0, avoid) == 0)) {
            print id
            exit
          }
        }'
    }

    # Auriculares del jack analógico.
    hp="$(pick sink Headphones)"
    # Micrófono del jack analógico: en el UCM del ALC256 es "Stereo Microphone"
    # (Mic1); el array interno digital es "Digital Microphone" (Mic2).
    mic="$(pick source 'Stereo Microphone' Digital)"
    dmic="$(pick source 'Digital Microphone' none)"

    # OJO: aquí NO se toca el volumen, a propósito.
    #
    # En el ALC256 el volumen de PipeWire y el control del mezclador de ALSA son
    # el mismo mando (no hay atenuación software aparte del hardware), así que
    # `wpctl set-volume <source> 1.0` ESCRIBE en Mic Boost y Capture y los manda a
    # 30 dB, que es la saturación de 60 dB de ganancia que la tarea 9 viene a
    # eliminar. El reparto de ganancia lo pone biko-audio-gain con amixer, que sí
    # distingue Mic Boost (pasos de 10 dB) de Capture (continuo).
    #
    # Si algún día se quiere el sink a tope, el mando correcto es el de
    # auriculares del CODEC, que fija biko-audio-gain al 90 % (-6.75 dB): dejar
    # el volumen de PipeWire al 100 % y que el CODEC Sea el que atenúa es
    # justamente lo contrario de lo advisable aquí.

    # Sumidero virtual del visualizador de audio (drop-in 60-ryoku-visualizer en
    # configuration.nix). Cuando existe ES el predeterminado: cava analiza su
    # monitor (source=auto => monitor del sumidero predeterminado) y su parte de
    # reproducción reenvía la misma señal al jack, así que el audio se sigue
    # oyendo igual.
    #
    # Se fija con `pactl set-default-sink` y no con wpctl por dos motivos:
    #   * el sumidero virtual no es una tarjeta, así que wpctl lo lista bajo
    #     "Filters" y no bajo "Sinks": pick() no lo encontraría nunca;
    #   * `wpctl set-default` sólo acepta un ID numérico, mientras que pactl
    #     acepta el nombre del nodo.
    # Si no existiera (por ejemplo porque el drop-in no cargó), se cae al de
    # auriculares de siempre en vez de quedarse sin salida.
    if ! pactl set-default-sink ryoku_visualizer 2>/dev/null; then
      if [ -n "''${hp:-}" ]; then
        wpctl set-default "$hp"
      fi
    fi

    if [ -n "''${mic:-}" ]; then
      wpctl set-default "$mic"
    elif [ -n "''${dmic:-}" ]; then
      wpctl set-default "$dmic"
    fi

    exit 0
  '';

  # Discord tiene que sonar por el hardware y NO por el sumidero virtual del
  # visualizador: si sonara ahí, cava lo analizaría y las barras reaccionarían a
  # las notificaciones del chat en lugar de a la música de Sonora.
  #
  # Esto no se puede declarar con una regla `stream.rules` de WirePlumber. En
  # 0.5 esa regla sólo alimenta la lógica de estado (volumen y destino
  # recordados), no reescribe las propiedades del nodo, así que un `target.object`
  # puesto ahí no cambia el enlace. Comprobado en esta máquina: con una regla que
  # forzaba `application.name = "pw-play"` a los auriculares y el sumidero virtual
  # como predeterminado, el stream seguía enlazándose al virtual. Por eso se
  # vigila el grafo con `pactl subscribe` y se mueve cada stream de Discord al
  # sumidero de hardware en cuanto aparece; a partir de ahí WirePlumber ya
  # recuerda ese destino para las siguientes veces.
  discordRoute = pkgs.writeShellScript "biko-discord-route" ''
    set -uo pipefail
    # LC_ALL=C porque la salida de pactl se parsea, no se muestra.
    export LC_ALL=C

    HW="alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Headphones__sink"

    # Mueve al hardware los streams de Discord que sigan en el sumidero por
    # defecto. Es idempotente: si ya están en el hardware, mover otra vez no
    # cambia nada.
    route() {
      pactl -f json list sink-inputs 2>/dev/null |
        jq -r '.[]
          | select((.properties["application.name"] // "") == "equibop"
                or (.properties["application.name"] // "") == "discord")
          | .index' 2>/dev/null |
        while read -r idx; do
          [ -n "$idx" ] && pactl move-sink-input "$idx" "$HW" 2>/dev/null || true
        done
    }

    # Discord ya podía estar sonando cuando arranca la sesión.
    route

    # Y cada vez que aparece un stream nuevo se reencamina. El segundo intento, en
    # segundo plano, cubre la carrera con el enlazado por defecto de WirePlumber
    # (que puede enlazar el stream después del primer aviso).
    pactl subscribe 2>/dev/null | while read -r event; do
      case "$event" in
        *"'new' on sink-input"*)
          route
          ( sleep 2; route ) &
          ;;
      esac
    done
  '';
in
{
  # ============================================================
  # TAREA 11: herramientas de diagnóstico de audio (comandos de abajo)
  # ============================================================
  environment.systemPackages = with pkgs; [
    alsa-utils # amixer/alsamixer: control fino del ALC256 (tarea 9)
    wireplumber # wpctl y herramientas de PipeWire
    libpulseaudio
    pavucontrol # control gráfico de sinks y volúmenes
    easyeffects # ecualizador de sistema: la vía para "el mejor audio" del PC
  ];

  # ============================================================
  # TAREA 8: nada de gestión de energía dinámica
  # ============================================================
  # power-profiles-daemon (lo activa Ryoku con mkDefault) reescribe por D-Bus la
  # la política de energía de la CPU y pone la GPU en "balanced", que es
  # justo lo contrario de lo que se pide aquí. Se desactiva: el plano de
  # rendimiento se aplica directamente sobre sysfs (servicio biko-cpu-performance).
  services.power-profiles-daemon.enable = lib.mkForce false;

  # El portátil nunca se desenchufa: ni reposo por inactividad, ni al cerrar la
  # tapa, ni al pulsar la tecla de suspensión. Un escritorio que se queda en suspend con
  # un monitor de 180 Hz es una fuente de latencia y de bugs al reanudar.
  # OJO: las claves van bajo settings.Login, no en settings a secas.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchInternalBattery = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    HandlePowerKey = "poweroff";
  };

  # Desactiva las unidades de suspensión/hibernación por completo.
  systemd.services = {
    "sleep.target".enable = false;
    "suspend.target".enable = false;
    "hibernate.target".enable = false;
    "suspend-then-hibernate.target".enable = false;
    "hybrid-sleep.target".enable = false;
    "systemd-suspend.service".enable = false;
    "systemd-hibernate.service".enable = false;
    "systemd-hybrid-sleep.service".enable = false;
    "systemd-suspend-then-hibernate.service".enable = false;
  };

  # ============================================================
  # TAREA 7 + 10: NVIDIA al máximo
  # ============================================================
  hardware.nvidia.nvidiaPersistenced = lib.mkForce true;

  systemd.services.biko-gpu-performance = {
    description = "NVIDIA RTX 4060: límite de potencia al máximo del panel";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # El límite por defecto de esta tarjeta es 35 W y el panel permite 45 W.
    # Con NVreg_MobileEnableGpuPowerManagement=0 (configuration.nix) la tarjeta
    # ya no se recorta sola, pero el límite de potencia se fija una vez y punto.
    script = ''
      set -uo pipefail
      for _ in $(seq 1 60); do
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
          break
        fi
        sleep 0.5
      done

      max=$(nvidia-smi --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
      cur=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
      if [ -n "''${max:-}" ] && [ -n "''${cur:-}" ]; then
        if awk "BEGIN{exit !(''$max' > ''$cur')}" 2>/dev/null; then
          nvidia-smi -pl "$max" >/dev/null 2>&1 || true
        fi
      fi
    '';
  };

  # ============================================================
  # TAREA 8: CPU en modo rendimiento
  # ============================================================
  systemd.services.biko-cpu-performance = {
    description = "CPU en modo rendimiento: governor, EPP yurbo dinámico al máximo";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -uo pipefail

      # intel_pstate puede aparecer un momento después del arranque.
      for _ in $(seq 1 30); do
        [ -d /sys/devices/system/cpu/intel_pstate ] && break
        sleep 0.2
      done

      # 1) Governor "performance" en todas las políticas de cada CPU.
      #    Con intel_pstate esto fija la CPU en P0: sin transiciones de P-state
      #    hacia abajo, que es de donde salía el tirón al hacer scroll o al
      #    mover el ratón.
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        echo performance > "$p/scaling_governor" 2>/dev/null || true
        # energy_performance_preference: "performance" le dice al hardware
        # que prefiera rendimiento a ahorro, por mucho que el governor lo fuerce.
        echo performance > "$p/energy_performance_preference" 2>/dev/null || true
      done

      # 2) intel_pstate: turbo dinámico activado y techo de turbo sin tocar.
      #    hwp_dynamic_boost estaba a 0: el boost de la turbo ya no se usaba.
      [ -e /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ] &&
        echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost 2>/dev/null || true
      [ -e /sys/devices/system/cpu/intel_pstate/no_turbo ] &&
        echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
      [ -e /sys/devices/system/cpu/intel_pstate/max_perf_pct ] &&
        echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null || true
    '';
  };

  # ============================================================
  # TAREA 8: NVMe sin gestión de energía (APST)
  # ============================================================
  # El WD SN740 estaba en power/control = "auto", es decir, APST activo: el
  # disco baja a un estado de bajo consumo y tarda cientos de microsegundos en
  # volver a estar listo. Con "on" el NVMe se queda siempre despierto; en un
  # portátil que no se desenchufa, el ahorro es irrelevante y la latencia de
  # E/S se nota al abrir cosas.
  systemd.services.biko-nvme-performance = {
    description = "NVMe: desactiva APST para quitar la latencia de despertar";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -uo pipefail
      for d in /sys/block/nvme*; do
        [ -d "$d/device" ] || continue
        [ -w "$d/device/power/control" ] && echo on > "$d/device/power/control" 2>/dev/null || true
      done
    '';
  };

  # ============================================================
  # TAREA 2 + 4: el panel interno APAGADO, y apagado desde el arranque
  # ============================================================
  # Hyprland ya desactiva eDP-1 (monitors.lua) y eso cubre el escritorio. Pero
  # la pantalla de inicio (Plymouth + SDDM) corre antes del compositor, y ahí el
  # panel interno se enciende: el resultado es "arrancar con la mitad de la
  # pantalla iluminada y la otra en negro".
  #
  # La solución robusta no es depender del compositor, sino dejar el panel en
  # negro antes de que arranque el display manager:
  #   * el brillo del panel se pone a 0,
  #   * y max_brightness se baja a 1, de modo que ni una tecla de brillo ni un
  #     cliente de DDC/CI pueda volver a encenderlo por error.
  # El panel sigue funcionando: basta con subir max_brightness a 96000 otra vez.
  systemd.services.biko-blank-internal-panel = {
    description = "Deja el panel interno (eDP-1) apagado y bloqueado";
    wantedBy = [ "multi-user.target" ];
    # Crítico: tiene que correr ANTES de que SDDM encienda nada.
    before = [ "display-manager.service" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -uo pipefail

      # El panel aparece cuando el driver i915 termina de sondear el EDID.
      for _ in $(seq 1 100); do
        [ -e "${internalPanelBacklight}/max_brightness" ] && break
        sleep 0.1
      done

      if [ -w "${internalPanelBacklight}/max_brightness" ]; then
        echo 1 > "${internalPanelBacklight}/max_brightness" 2>/dev/null || true
        echo 0 > "${internalPanelBacklight}/brightness" 2>/dev/null || true
      fi
    '';
  };

  # ============================================================
  # TAREA 9: calidad de audio
  # ============================================================
  #
  # BASTA DE ATENCIÓN AQUÍ, porque es la parte que más fácilmente se estropea
  # sola: en el ALC256 el "volumen" de PipeWire Y el control del mezclador de
  # ALSA son el MISMO mando. No hay un volumen software aparte del hardware.
  # Por eso, dos reglas:
  #
  #   1. `wpctl set-volume` ESCRIBE en el mezclador de ALSA. Poner un source de
  #      micro a 1.0 empuja Mic Boost y Capture a 30 dB, que es exactamente la
  #      saturación que esta tarea viene a quitar. Por eso el script de
  #      "defaults" SÓLO elige dispositivo por defecto y NO toca volúmenes.
  #
  #   2. WirePlumber restaura sus volúmenes guardados al iniciar la sesión
  #      (~/.local/state/wireplumber), y eso pisa lo que se haya puesto al
  #      arrancar. Por eso el reparto de ganancia se aplica DOS veces: una a
  #      nivel de sistema (línea base temprana) y otra en la sesión de usuario
  #      DESPUÉS de wireplumber.service, que es la que manda.
  #
  #   3. NO se intenta "sincronizar" la vista de PipeWire con el hardware.
  #      Se probó (wpctl set-volume sobre el sink para dejarla en 0.4597, el
  #      equivalente lineal de -6.75 dB) y el resultado es peor que el problema:
  #      PipeWire escribe en el CODEC con OTRO mapeo de ganancia y el auricular
  #      acabó en raw 60 (-20.25 dB) en vez de raw 78 (-6.75 dB), es decir
  #      13.5 dB más bajo de lo pedido. Así que amixer manda y la lectura
  #      cacheada de PipeWire se acepta como lo que es: cosmética, y se
  #      corrige sola la próxima vez que una app o el OSD toquen el volumen.
  systemd.services.biko-audio-quality = {
    description = "ALC256: ganancias de micrófono y jack de auriculares (línea base)";

    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-modules-load.service"
      "alsa-restore.service"
      "sound.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${audioTuning}
    '';
  };

  # Rearranca del reparto de ganancia en la sesión de usuario, después de que
  # WirePlumber haya restaurado su estado guardado. Es la autoridad final sobre
  # Mic Boost / Capture / Dmic0 / Headphone.
  systemd.user.services.biko-audio-gain = {
    description = "ALC256: reaplica las ganancias tras el arranque de WirePlumber";
    wantedBy = [ "graphical-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" ];
    # Sólo amixer a propósito: ver el comentario sobre wpctl en el script.
    path = [
      pkgs.alsa-utils # amixer
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${audioTuning}
    '';
  };

  # Sinks y sources por defecto. Va como servicio de usuario porque sólo
  # existe una sesión PipeWire cuando hay login; espera a que aparezca.
  systemd.user.services.biko-audio-defaults = {
    description = "Auriculares analógicos y micrófono del jack como dispositivos por defecto";
    wantedBy = [ "graphical-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" ];
    # IMPORANTE: las unidades de systemd NO heredan el PATH del perfil del
    # usuario, sólo el que genera NixOS (coreutils, findutils, grep, sed,
    # systemd). Sin esta lista explícita el script falla de dos maneras, ambas
    # silenciosas porque el servicio acaba con status=0:
    #   * sin `wireplumber` no existe `wpctl`, el bucle de espera se come los
    #     60 s enteros y no se configura nada;
    #   * sin `gawk` no existe `awk`, que es donde vive la función `pick` que
    #     localiza los sinks/sources: aunque `wpctl` funcione, `pick` devuelve
    #     vacío y los `if [ -n ... ]` se saltan.
    path = [
      pkgs.wireplumber # wpctl
      pkgs.gawk # awk: usado por pick() para leer wpctl status
      pkgs.pulseaudio # pactl: fija el sumidero virtual como predeterminado por nombre
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pipewireDefaults}
    '';
  };

  # Aparta el audio de Discord del sumidero virtual del visualizador. Va como
  # servicio de usuario (necesita la sesión PipeWire, que sólo existe con login
  # gráfico) y no es oneshot: `pactl subscribe` deja un lector abierto esperando
  # streams nuevos. Ver el comentario de discordRoute para saber por qué esto no
  # puede ser una regla de WirePlumber.
  systemd.user.services.biko-discord-route = {
    description = "Aleja el audio de Discord del sumidero virtual del visualizador";
    wantedBy = [ "graphical-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" ];
    path = [
      pkgs.pulseaudio # pactl: list/move/subscribe sobre los sink-inputs
      pkgs.jq # jq: lee el JSON de `pactl -f json list sink-inputs`
    ];
    serviceConfig = {
      # `always`, no `on-failure`: si `pactl subscribe` termina por su cuenta (por
      # ejemplo al reiniciarse PipeWire en un `nixos-rebuild switch`), el script
      # acaba con status 0 y sin esto el vigilante no volvería a levantarse.
      Restart = "always";
      RestartSec = 3;
    };
    script = ''
      ${discordRoute}
    '';
  };

  # ============================================================
  # TAREA 7 + 10: ethernet con cable -- EEE NO se puede desactivar aquí
  # ============================================================
  # La intención original era apagar EEE (Energy Efficient Ethernet) en la
  # RTL8111 para quitar los picos de latencia de varios ms que introduce el
  # enlace. Se midió y en esta máquina NO es posible:
  #
  #   $ ethtool --show-eee enp4s0
  #     EEE status: enabled - active
  #   $ ethtool --set-eee enp4s0 off
  #     ethtool (--set-eee): unknown parameter 'off'
  #
  # El driver r8169 (kernel 6.18.53, firmware rtl8168h-2_0.0.2) implementa la
  # operación get_EEE --por eso --show-eee responde-- pero NO la set_EEE, así que
  # ethtool no tiene ningún parámetro que_valga y no existe ningún control EEE en
  # /sys/class/net/enp4s0 (sólo aparece reset_method). El EEE de los Realtek es
  # una función interna del chip que el driver mainline no expone.
  #
  # Por eso NO hay un servicio aquí. Se eliminó el que tenía: ejecutaba
  # `ethtool --set-eee off >/dev/null 2>&1 || true`, que falla y se descarta, y
  # luego el servicio terminaba con status=0/SUCCESS. O sea, decía haberlo
  # hecho sin haberlo hecho, que es peor que no intentarlo. Un
  # biko-ethernet-noeee así inactivo era engañoso.
  #
  # Lo que sí está bien y no se toca: autonegociación activa, 1000Mb/s Full.

  # ============================================================
  # TAREA 7 + 10: módulos de kernel que faltan por cargar
  # ============================================================
  # kvm-intel ya viene en hardware-configuration.nix. Se añaden los que
  # aparecen en el hardware y no estaban cargados:
  #   * i915            -> Intel UHD (ya lo carga modesetting, pero se asegura)
  #   * nvidia_drm      -> KMS de la RTX 4060 en modo explícito
  #   * r8169           -> Realtek RTL8111 Ethernet con cable
  #   * iwlwifi         -> Intel AX211 Wi-Fi
  #   * snd_hda_intel   -> PCH HD Audio
  #   * coretemp        -> sensores de temperatura de la CPU (para la tarea 10)
  # kvm_intel ya viene en hardware-configuration.nix y no se toca.
  boot.kernelModules = [
    "i915"
    "nvidia"
    "nvidia_drm"
    "nvidia_modeset"
    "nvidia_uvm"
    "r8169"
    "iwlwifi"
    "snd_hda_intel"
    "snd_hda_codec_realtek"
    "coretemp"
  ];

  # El driver de la RTX 4060 tiene que estar en el initrd: sin él, Plymouth y
  # el monitor externo se quedan en negro hasta que el sistema raíz está montado.
  # (Los parámetros de KMS del initrd los pone ya `hardware.nvidia.modesetting`
  # con `nvidia_drm.modeset=1`; aquí sólo se listan los módulos que faltaban.)
  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_drm"
    "nvidia_modeset"
    "i915"
    "snd_hda_intel"
  ];

  # ============================================================
  # Tarea 10: diagnóstico
  # ============================================================
  # lm_sensors no tiene módulo en nixpkgs: se cargan los sensores de la placa
  # en el arranque para que `sensors` muestre temperaturas y ventiladores.
  # (Los módulos coretemp/k10temp ya están en boot.kernelModules más arriba.)
  systemd.services.biko-load-sensors = {
    description = "Carga los sensores de la placa (lm_sensors)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -uo pipefail
      ${pkgs.lm_sensors}/bin/sensors -u >/dev/null 2>&1 || true
    '';
  };

  # SMART del NVMe y del resto de discos, una vez al mes, para la tarea 10.
  systemd.timers.biko-smart-scan = {
    description = "Lectura SMART mensual de los discos";
    wantedBy = [ "timers.target" ];
    after = [ "local-fs.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
      RandomizedDelaySec = 300;
    };
    unitConfig.ConditionPathExists = "/dev/nvme0n1";
  };
  systemd.services.biko-smart-scan = {
    description = "Lectura SMART mensual de los discos";
    path = with pkgs; [
      smartmontools
      nvme-cli
    ];
    script = ''
      set -uo pipefail
      smartctl --scan-open 2>/dev/null | while read -r dev _rest; do
        [ -b "$dev" ] || continue
        echo "===== $dev ====="
        smartctl -H -A "$dev" 2>/dev/null || true
      done
      echo "===== NVMe: desgaste y salud ====="
      nvme smart-log /dev/nvme0 2>/dev/null || true
    '';
  };
}
