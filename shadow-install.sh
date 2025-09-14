#!/bin/bash
# Script d'installation complet ShadowPC + ShadowUSB pour Raspberry Pi 4/5 (64-bit)
# Auteur : Alexandre & Assistant
# Date   : $(date +"%Y-%m-%d")
# OS     : Raspberry Pi OS 64-bit (Debian-based, bullseye/bookworm)

set -euo pipefail

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Vérification prérequis ---
check_prerequisites() {
  log_info "Vérification des prérequis..."
  if ! uname -m | grep -qE 'aarch64|arm64'; then
    log_error "Architecture non ARM64 : ce script vise Raspberry Pi OS 64-bit."
    exit 1
  fi
  if ! grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
    log_warning "Système non Raspberry Pi : fonctionnement non garanti."
  fi
  if ! command -v apt &>/dev/null; then
    log_error "Ce script nécessite un système basé sur Debian (apt)."
    exit 1
  fi
  if [[ $EUID -ne 0 ]]; then
    log_error "Exécutez ce script en root (sudo)."
    exit 1
  fi
  log_success "Prérequis validés"
}

update_system() {
  log_info "Mise à jour du système..."
  apt update && apt full-upgrade -y
  log_success "Système mis à jour"
}

install_dependencies() {
  log_info "Installation des dépendances utiles..."
  apt install -y wget curl gpg git xdg-desktop-portal-gtk \
     libva2 libvdpau1 libva-drm2 libva-wayland2 libdrm2 \
     libasound2 libpulse0
  log_success "Dépendances installées"
}

# Détecte le bon chemin de config boot (Bookworm: /boot/firmware)
_boot_cfg_path() {
  if [ -f /boot/firmware/config.txt ]; then
    echo "/boot/firmware/config.txt"
  else
    echo "/boot/config.txt"
  fi
}

# Pi 5 : activer kernel 4K pages (obligatoire pour Shadow)
ensure_pi5_kernel_4k() {
  if grep -qi "raspberry pi 5" /proc/device-tree/model 2>/dev/null; then
    local cfg="$(_boot_cfg_path)"
    if ! grep -q "^\[pi5\]" "$cfg"; then
      log_info "Ajout du bloc [pi5] kernel=kernel8.img dans $cfg"
      {
        echo ""
        echo "[pi5]"
        echo "kernel=kernel8.img"
      } >> "$cfg"
      log_warning "Un redémarrage sera nécessaire pour appliquer le kernel 4K pages."
    else
      # S'assurer que la ligne kernel est présente sous [pi5]
      awk -v RS= -v ORS="\n\n" '
        BEGIN{updated=0}
        /\[pi5\]/{
          if ($0 !~ /kernel=kernel8\.img/) {
            sub(/\[pi5\][^\n]*/, "&\nkernel=kernel8.img")
            updated=1
          }
        } {print}
        END{ if(updated){ exit 10 } }
      ' "$cfg" > /tmp/config.txt.$$ || true
      if [ $? -eq 10 ]; then
        cp /tmp/config.txt.$$ "$cfg"
        log_warning "Ajout de kernel=kernel8.img sous [pi5] dans $cfg (redémarrage requis)."
      fi
      rm -f /tmp/config.txt.$$
    fi
  fi
}

# Installe ShadowPC (méthode officielle .deb qui ajoute le dépôt APT)
install_shadow_pc() {
  log_info "Installation de ShadowPC (Raspberry Pi ARM64)..."
  local tmpdir="/tmp/shadow-install"
  mkdir -p "$tmpdir"; cd "$tmpdir"

  # URL officielle RPi ARM64 (prod)
  local deb_url="https://update.shadow.tech/launcher/prod/linux/rpi/shadow-arm64.deb"
  if wget -q --show-progress -O shadow-arm64.deb "$deb_url"; then
    apt install -y ./shadow-arm64.deb || true
  else
    log_warning "Téléchargement du .deb RPi échoué, on passe à l'ajout manuel du dépôt."
  fi

  # Si pour une raison quelconque l'install n'a pas ajouté la source, on force
  if ! apt-cache policy | grep -q "repository.shadow.tech"; then
    log_info "Ajout du dépôt APT Shadow (arm64/prod)..."
    apt-get install -y wget gpg
    wget -qO- http://repository.shadow.tech/shadow_signing.key | gpg --dearmor > packages.shadowapp.gpg
    install -o root -g root -m 644 packages.shadowapp.gpg /etc/apt/trusted.gpg.d/
    rm -f packages.shadowapp.gpg
    echo 'deb [arch=arm64] http://repository.shadow.tech/prod bullseye main' \
      > /etc/apt/sources.list.d/shadow-prod.list
    apt update
  fi

  # Installe l'appli stable (prod)
  apt install -y shadow-prod
  cd /; rm -rf "$tmpdir"
  log_success "ShadowPC installé (canal prod)."
}

# Installe ShadowUSB via le dépôt officiel
install_shadow_usb() {
  log_info "Installation de ShadowUSB..."
  # Le dépôt a normalement été ajouté par l'étape ShadowPC ; sinon on s'assure
  if ! apt-cache policy | grep -q "repository.shadow.tech"; then
    log_info "Ajout du dépôt APT Shadow (arm64/prod) pour ShadowUSB..."
    apt-get install -y wget gpg
    wget -qO- http://repository.shadow.tech/shadow_signing.key | gpg --dearmor > packages.shadowapp.gpg
    install -o root -g root -m 644 packages.shadowapp.gpg /etc/apt/trusted.gpg.d/
    rm -f packages.shadowapp.gpg
    echo 'deb [arch=arm64] http://repository.shadow.tech/prod bullseye main' \
      > /etc/apt/sources.list.d/shadow-prod.list
    apt update
  fi
  apt install -y shadowusb
  systemctl enable shadowusb.service || true
  systemctl daemon-reload
  log_success "ShadowUSB installé et service enregistré."
}

# Accélération matérielle (variables VAAPI/Wayland)
setup_hardware_acceleration() {
  log_info "Configuration variables d'accélération (VAAPI/Wayland)..."
  # On ajoute sans écraser le fichier
  for line in \
    "LIBVA_DRIVER_NAME=v4l2_request" \
    "LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12" \
    "SDL_VIDEODRIVER=wayland"
  do
    grep -q "^${line}$" /etc/environment 2>/dev/null || echo "$line" >> /etc/environment
  done
  log_success "Variables d'environnement ajoutées."
}

# Optimisations réseau (optionnel mais utile)
setup_network_optimizations() {
  log_info "Application des optimisations réseau..."
  cat >/etc/sysctl.d/99-shadow-network.conf <<'EOF'
# Optimisations réseau Shadow
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.core.netdev_max_backlog = 5000
EOF
  sysctl -p /etc/sysctl.d/99-shadow-network.conf
  log_success "Optimisations réseau appliquées."
}

# Scripts utilitaires
create_launch_scripts() {
  log_info "Création des scripts de lancement..."
  cat >/usr/local/bin/launch-shadow <<'EOF'
#!/bin/bash
# Lance ShadowPC (binaire installé par le paquet shadow-*)
export LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-v4l2_request}
export LIBVA_V4L2_REQUEST_VIDEO_PATH=${LIBVA_V4L2_REQUEST_VIDEO_PATH:-/dev/video10,/dev/video11,/dev/video12}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-wayland}
# Essais de binaires possibles
for bin in shadow shadow-prod shadow-beta; do
  if command -v "$bin" >/dev/null 2>&1; then
    exec "$bin" "$@"
  fi
done
echo "Shadow n'est pas installé (shadow/shadow-prod introuvable)." >&2
exit 1
EOF
  chmod +x /usr/local/bin/launch-shadow
  log_success "Scripts créés."
}

setup_user_permissions() {
  log_info "Permissions utilisateur..."
  local user="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
  if [ -n "$user" ]; then
    usermod -a -G input,plugdev,video,audio "$user" || true
    log_success "Groupes ajoutés pour $user"
  else
    log_warning "Utilisateur non détecté, ajoutez votre user aux groupes input/plugdev/video/audio"
  fi
}

test_installation() {
  log_info "Tests installation..."
  if command -v shadow >/dev/null 2>&1 || command -v shadow-prod >/dev/null 2>&1; then
    log_success "ShadowPC détecté"
  else
    log_error "ShadowPC non détecté"
  fi
  if systemctl list-unit-files | grep -q '^shadowusb\.service'; then
    systemctl is-enabled --quiet shadowusb.service && log_success "ShadowUSB activé" || log_warning "ShadowUSB installé mais non activé"
  else
    log_warning "Service ShadowUSB non présent (paquet manquant ?)"
  fi
  [ -x /usr/local/bin/launch-shadow ] && log_success "Script launch-shadow OK" || log_error "Script launch-shadow manquant"
}

show_post_install_info() {
  echo
  log_info "=== Installation terminée ==="
  echo "Commandes utiles :"
  echo "  launch-shadow             → Lancer ShadowPC"
  echo "  systemctl status shadowusb.service  → État ShadowUSB"
  echo "  journalctl -u shadowusb.service -f  → Logs temps réel ShadowUSB"
  echo
  if grep -qi "raspberry pi 5" /proc/device-tree/model 2>/dev/null; then
    log_warning "Pi 5 : si le bloc [pi5]/kernel=kernel8.img vient d'être ajouté, redémarrez (sudo reboot)."
  else
    log_warning "Un redémarrage est recommandé pour activer toutes les optimisations."
  fi
}

main() {
  echo "=== INSTALLATION SHADOW RPi (ARM64) ==="
  check_prerequisites
  update_system
  install_dependencies
  ensure_pi5_kernel_4k
  install_shadow_pc
  install_shadow_usb
  setup_hardware_acceleration
  setup_network_optimizations
  create_launch_scripts
  setup_user_permissions
  test_installation
  show_post_install_info
}

main "$@"
