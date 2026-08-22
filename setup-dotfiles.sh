#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# setup-dotfiles.sh — Adaptador de Dotfiles Ryoku para NixOS
#
# Clona el repo ryoku-arch, copia .config a /persist/home/biko/.config
# y parchea las rutas FHS de Arch Linux ( /usr/bin/ , /bin/ ) hacia rutas
# compatibles con el PATH de NixOS (/run/current-system/sw/bin/).
#
# Ejecución: bash setup-dotfiles.sh
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuración ────────────────────────────────────────────────────────
DOTFILES_REPO="https://github.com/neur0map/ryoku-arch"
TMP_DIR="/tmp/ryoku"
PERSIST_HOME="/persist/home/biko"

# ── Colores ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; }

# ── Pre-checks ───────────────────────────────────────────────────────────
if [ ! -d "$PERSIST_HOME" ]; then
  err "No existe $PERSIST_HOME. Asegúrate de que /persist esté montado."
  exit 1
fi

if [ -d "$PERSIST_HOME/.config/hypr" ]; then
  warn "Parece que los dotfiles ya están instalados en $PERSIST_HOME/.config"
  read -rp "¿Sobrescribir? [s/N]: " confirm
  if [ "${confirm,,}" != "s" ]; then
    info "Abortando."
    exit 0
  fi
fi

# ── Clonar repositorio ───────────────────────────────────────────────────
info "Clonando $DOTFILES_REPO ..."
rm -rf "$TMP_DIR"
git clone --depth 1 "$DOTFILES_REPO" "$TMP_DIR"

# ── Copiar .config ───────────────────────────────────────────────────────
info "Copiando .config/* → $PERSIST_HOME/.config/"
mkdir -p "$PERSIST_HOME/.config"
if [ -d "$TMP_DIR/.config" ]; then
  cp -r "$TMP_DIR/.config/"* "$PERSIST_HOME/.config/"
else
  # Si el repo no tiene .config/ en raíz, buscar recursivamente
  warn "No se encontró .config/ en la raíz del repo. Buscando..."
  find "$TMP_DIR" -type d -name ".config" -maxdepth 3 | while read -r cfgdir; do
    info "Copiando desde $cfgdir ..."
    cp -r "$cfgdir/"* "$PERSIST_HOME/.config/"
  done
fi

# ── Parchear rutas FHS Arch → PATH NixOS ─────────────────────────────────
info "Parcheando rutas absolutas de Arch → NixOS..."
PATCH_COUNT=0

while IFS= read -r -d '' script; do
  info "   → $(basename "$script")"

  # Sustituir rutas hardcodeadas típicas de Arch
  sed -i \
    -e 's|#!/usr/bin/env bash|#!/usr/bin/env bash|' \
    -e 's|#!/usr/bin/bash|#!/usr/bin/env bash|' \
    -e 's|#!/bin/bash|#!/usr/bin/env bash|' \
    -e 's|/usr/bin/|/run/current-system/sw/bin/|g' \
    -e 's|/usr/local/bin/|/run/current-system/sw/bin/|g' \
    -e 's|\b/bin/|/run/current-system/sw/bin/|g' \
    -e 's|/usr/share/|/run/current-system/sw/share/|g' \
    -e 's|/usr/lib/|/run/current-system/sw/lib/|g' \
    "$script"

  PATCH_COUNT=$((PATCH_COUNT + 1))
done < <(find "$PERSIST_HOME/.config" -name "*.sh" -type f -print0)

# ── Permisos de ejecución ────────────────────────────────────────────────
info "Asignando permisos de ejecución..."
find "$PERSIST_HOME/.config" -name "*.sh" -type f -exec chmod +x {} \;

# ── Propiedad del usuario ────────────────────────────────────────────────
if id biko &>/dev/null; then
  chown -R biko:users "$PERSIST_HOME/.config"
fi

# ── Limpiar ──────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"

# ── Resumen ──────────────────────────────────────────────────────────────
log "Dotfiles Ryoku instalados en $PERSIST_HOME/.config/"
log "Scripts parcheados: $PATCH_COUNT"
log "Listo para usar con Hyprland."