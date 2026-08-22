#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# install.sh — Despliegue automatizado de NixOS en MSI Thin GF63 12VF
#
# Este script debe ejecutarse desde un NixOS ISO live (o cualquier live
# con Nix instalado).
#
# Orden de operaciones:
#   1. Particionado del disco NVMe con disko
#   2. Instalación de NixOS (flakes + impermanence)
#   3. Los dotfiles Ryoku se instalan en el primer boot (activationScript)
#
# Uso:   bash install.sh
# ══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; }

banner() {
  echo -e "${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║   MSI Thin GF63 12VF — NixOS Installer      ║"
  echo "  ║   i7-12650H | RTX 4060 | Impermanence       ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ── Pre-checks ───────────────────────────────────────────────────────────
preflight() {
  banner

  info "Verificando entorno..."

  if [ "$(id -u)" -ne 0 ]; then
    err "Este script debe ejecutarse como root (sudo)."
    exit 1
  fi

  if [ ! -f "$(dirname "$0")/flake.nix" ]; then
    err "No se encuentra flake.nix. Ejecuta desde ~/nixos-config/"
    exit 1
  fi

  if ! command -v nix &>/dev/null; then
    err "Nix no está instalado. Arranca desde un NixOS ISO."
    exit 1
  fi

  DISK="/dev/nvme0n1"
  if [ ! -b "$DISK" ]; then
    err "No se detecta el NVMe $DISK"
    lsblk -d -o NAME,SIZE,MODEL
    exit 1
  fi

  log "Disco detectado: $DISK ($(lsblk -dn -o SIZE "$DISK"))"
  warn ""
  warn "  ⚠  ESTE SCRIPT VA A FORMATEAR COMPLETAMENTE $DISK"
  warn "  ⚠  TODOS LOS DATOS SE PERDERÁN"
  warn ""
  read -rp "  ¿Continuar? Escribe 'FORMATEAR' para confirmar: " confirm
  if [ "$confirm" != "FORMATEAR" ]; then
    info "Abortando."
    exit 0
  fi
}

# ── Paso 1: Particionar con disko ────────────────────────────────────────
run_disko() {
  info "Paso 1/3: Particionando disco con disko..."
  info "    Disco: $DISK"
  info "    Layout: 1G ESP (VFAT) + resto Btrfs (subvolúmenes /nix, /persist)"

  nix --experimental-features "nix-command flakes" \
    run github:nix-community/disko -- \
    --mode disko \
    "$(dirname "$0")/disko.nix"

  log "Particionado completado."

  # Montar las particiones para nixos-install
  info "Montando particiones para instalación..."
  mount /dev/disk/by-partlabel/NIXOS_PERSIST /mnt
  mkdir -p /mnt/boot
  mount /dev/disk/by-partlabel/ESP /mnt/boot
  mkdir -p /mnt/nix /mnt/persist
  mount /dev/disk/by-partlabel/NIXOS_PERSIST -o subvol=/nix,compress=zstd,noatime /mnt/nix
  mount /dev/disk/by-partlabel/NIXOS_PERSIST -o subvol=/persist,compress=zstd,noatime /mnt/persist

  # Estructura de persistencia
  mkdir -p /mnt/persist/home/biko
  mkdir -p /mnt/persist/etc/nixos
  mkdir -p /mnt/persist/var/log
  mkdir -p /mnt/persist/var/lib

  log "Particiones montadas en /mnt."
}

# ── Paso 2: Instalar NixOS ───────────────────────────────────────────────
install_nixos() {
  info "Paso 2/3: Instalando NixOS (flake)..."
  info "    Configuración: $(dirname "$0")#msi-thin"

  # Copiar la configuración a /mnt/persist/etc/nixos para que sobreviva
  cp -r "$(dirname "$0")" /mnt/persist/etc/nixos/

  nixos-install \
    --flake "/mnt/persist/etc/nixos#msi-thin" \
    --no-root-passwd \
    --root /mnt

  log "NixOS instalado."
}

# ── Paso 3: Post-instalación ─────────────────────────────────────────────
post_install() {
  info "Paso 3/3: Post-instalación..."

  # Los dotfiles Ryoku se instalan automáticamente en el primer boot
  # mediante system.activationScripts.ryoku-dotfiles en configuration.nix

  info "Limpieza..."
  umount -R /mnt 2>/dev/null || true

  log ""
  log "═══════════════════════════════════════════════════"
  log "  INSTALACIÓN COMPLETADA"
  log ""
  log "  ▶ Reinicia:  systemctl reboot"
  log "  ▶ Usuario:   biko / changeme"
  log "  ▶ Hostname:  msi-nixos"
  log ""
  log "  Al primer login, los dotfiles Ryoku se instalarán"
  log "  automáticamente. Cambia la contraseña con passwd."
  log "═══════════════════════════════════════════════════"
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  preflight
  run_disko
  install_nixos
  post_install
}

main "$@"