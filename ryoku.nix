# Managed by ryoku-install.
#
# Este fichero lo gestiona el instalador de Ryoku. NO lo borres ni reescribas
# su estructura: `ryoku update` y el Hub lo usan para localizar el input
# `ryoku` del flake. Sus opciones se pueden editar, pero mantén el marcador
# `# Managed by ryoku-install.` en la primera línea (el instalador se niega a
# sobrescribir un ryoku.nix que no lleve ese marcador).
{ ... }:

{
  programs.ryoku.enable = true;

  # El flake de NixOS vive en /etc/nixos (no en ~/Escritorio). El backend de
  # actualización del Hub solo avanza el input `ryoku` de ESTE flake.
  programs.ryoku.updateFlake = "/etc/nixos";

  # Input del flake que gestiona el Hub (por defecto ya es "ryoku").
  programs.ryoku.updateInput = "ryoku";

  # Fish es el shell por defecto de Ryoku. Cámbialo a "zsh" si lo prefieres.
  programs.ryoku.shell = "fish";
}
