{
  description = "NixOS biko-msi — Ryoku (Hyprland) como escritorio único + ajustes de hardware";

  inputs = {
    # nixos-unstable: la misma rama que trae el sistema instalado (26.05).
    # También es de donde Ryoku espera un nixpkgs razonablemente reciente.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Ryoku-on-NixOS: puerto oficial del escritorio Ryoku (Hyprland/Niri +
    # Quickshell). Se deja SIN `inputs.nixpkgs.follows` a propósito: Ryoku fija
    # su propio nixpkgs para compilar Hyprland, sus plugins y Quickshell con una
    # ABI exacta. Es lo que hace también el instalador oficial
    # (nix/apps/ryoku-install-edit.py).
    ryoku = {
      url = "github:aethctl/Ryoku-on-NixOS/main";
    };

    # Sonora (tarea 11): https://github.com/sonorahq/sonora
    # Cliente nativo de música en streaming (Rust + GPUI). No está en nixpkgs.
    # Se usa su binario precompilado (`default` = sonora-bin) en lugar de compilar
    # el crate: mismo upstream, mismo binario, sin necesitar toolchain de Rust.
    # Sigue SIN `follows` porque su flake fija su propio nixpkgs + rust-overlay,
    # igual que hace Ryoku.
    sonora = {
      url = "github:sonorahq/sonora";
    };
  };

  # NOTA: `outputs = {` debe quedar en una sola línea; el instalador oficial de
  # Ryoku parsea este fichero con una regex que no admite un salto entre `=` y
  # `{`. Mantener este formato para que `ryoku update` / reinstalaciones sigan
  # funcionando.
  #
  # NOTA 2: no se pide `inputs` en la lista de argumentos de outputs. Con ese
  # nombre Nix lo interpreta como "quiero un input llamado inputs" y falla con
  # `cannot find flake 'flake:inputs'`. Se pasa lo que hace falta con un nombre
  # propio vía specialArgs (ver abajo).
  outputs = { self, nixpkgs, ryoku, sonora, ... }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        # Los módulos de NixOS no reciben los inputs del flake por su cuenta:
        # hay que pasarlos explícitamente. configuration.nix usa `sonoraInput`
        # para meter Sonora (que no está en nixpkgs) en
        # environment.systemPackages.
        specialArgs = { sonoraInput = sonora; };

        modules = [
          # ---- Ryoku (fuerza Hyprland + su ABI, portales, SDDM theme, etc.) ----
          ryoku.nixosModules.default
          ./ryoku.nix

          # ---- Configuración del sistema ----
          ./configuration.nix
          ./hardware-configuration.nix

        ];
      };

      # Empaquetado de referencia para `nix build` (no es el sistema).
      packages.x86_64-linux.sonora = sonora.packages.x86_64-linux.default;
    };
}
