#!/bin/bash

# Script d'installation complet ShadowPC + ShadowUSB pour Raspberry Pi 5
# Auteur : Alexandre & Assistant
# Date   : $(date +"%Y-%m-%d")
# OS     : Raspberry Pi OS (Debian-based)

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Vérification prérequis ---
check_prerequisites() {
    log_info "Vérification des prérequis..."
    if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        log_warning "Non-Raspberry Pi détecté : fonctionnement non garanti"
    fi
    if ! command -v apt &>/dev/null; then
        log_error "Ce script nécessite un système basé sur Debian (apt)"
        exit 1
    fi
    if [[ $EUID -ne 0 ]]; then
        log_error "Exécutez ce script en root (sudo)"
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
    log_info "Installation dépendances..."
    apt install -y wget curl git build-essential cmake pkg-config \
        libssl-dev libavcodec-dev libavformat-dev libavutil-dev \
        libswscale-dev libswresample-dev libsdl2-dev libsdl2-ttf-dev \
        libva-dev libvdpau-dev libxkbcommon-dev libwayland-dev libx11-dev \
        libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
        libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev \
        libasound2-dev libpulse-dev libudev-dev libusb-1.0-0-dev \
        libevdev-dev libdbus-1-dev libsystemd-dev \
        flatpak xdg-desktop-portal-gtk
    log_success "Dépendances installées"
}

setup_flatpak() {
    log_info "Configuration Flatpak..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak update -y --appstream
    log_success "Flatpak configuré"
}

install_shadow_pc() {
    log_info "Installation ShadowPC..."
    flatpak install -y flathub com.shadow.ShadowBeta || true
    if ! flatpak list | grep -q "com.shadow.ShadowBeta"; then
        log_warning "Échec Flatpak, tentative d'installation .deb..."
        mkdir -p /tmp/shadow-install && cd /tmp/shadow-install
        wget -O shadow-beta.deb "https://update.shadow.tech/launcher/preprod/linux/ubuntu_18.04/shadow-beta.deb"
        dpkg -i shadow-beta.deb || apt -f install -y
        cd / && rm -rf /tmp/shadow-install
    fi
    log_success "ShadowPC installé"
}

install_shadow_usb() {
    log_info "Installation ShadowUSB..."
    mkdir -p /opt/shadowusb && cd /opt/shadowusb
    if [ -d ".git" ]; then git pull; else git clone https://github.com/NicolasGuilloux/shadow-usb-linux.git .; fi
    make clean && make
    make install || true
    if [ -f rules/99-shadow-usb.rules ]; then
        cp rules/99-shadow-usb.rules /etc/udev/rules.d/
        udevadm control --reload-rules && udevadm trigger
    fi
    log_success "ShadowUSB installé"
}

setup_services() {
    log_info "Configuration service systemd..."
    cat >/etc/systemd/system/shadowusb.service <<'EOF'
[Unit]
Description=Shadow USB Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadowusb-daemon
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowusb.service
    log_success "Service systemd configuré"
}

setup_hardware_acceleration() {
    log_info "Config GPU/VAAPI..."
    grep -q "gpu_mem=128" /boot/config.txt || echo "gpu_mem=128" >> /boot/config.txt
    grep -q "dtoverlay=vc4-kms-v3d" /boot/config.txt || echo "dtoverlay=vc4-kms-v3d" >> /boot/config.txt
    cat >>/etc/environment <<'EOF'
# Accélération matérielle RPi5
LIBVA_DRIVER_NAME=v4l2_request
LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12
EOF
    log_success "Accélération matérielle configurée"
}

setup_network_optimizations() {
    log_info "Optimisations réseau..."
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
    log_success "Optimisations réseau appliquées"
}

create_launch_scripts() {
    log_info "Scripts de lancement..."
    cat >/usr/local/bin/launch-shadow <<'EOF'
#!/bin/bash
export LIBVA_DRIVER_NAME=v4l2_request
export LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12
export SDL_VIDEODRIVER=wayland
if command -v flatpak &>/dev/null && flatpak list | grep -q "com.shadow.ShadowBeta"; then
    flatpak run com.shadow.ShadowBeta "$@"
elif command -v shadow-beta &>/dev/null; then
    shadow-beta "$@"
else
    echo "Shadow non installé"
    exit 1
fi
EOF
    cat >/usr/local/bin/shadowusb-control <<'EOF'
#!/bin/bash
case "$1" in
  start) systemctl start shadowusb.service ;;
  stop) systemctl stop shadowusb.service ;;
  restart) systemctl restart shadowusb.service ;;
  status) systemctl status shadowusb.service ;;
  logs) journalctl -u shadowusb.service -f ;;
  *) echo "Usage: $0 {start|stop|restart|status|logs}"; exit 1 ;;
esac
EOF
    chmod +x /usr/local/bin/launch-shadow /usr/local/bin/shadowusb-control
    log_success "Scripts créés"
}

setup_user_permissions() {
    log_info "Permissions utilisateur..."
    local user="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
    if [ -n "$user" ]; then
        usermod -a -G input,plugdev,video,audio "$user"
        log_success "Groupes ajoutés pour $user"
    else
        log_warning "Utilisateur non détecté, ajoutez manuellement votre user aux groupes input/plugdev/video/audio"
    fi
}

test_installation() {
    log_info "Tests installation..."
    flatpak list | grep -q "com.shadow.ShadowBeta" || command -v shadow-beta &>/dev/null \
        && log_success "ShadowPC OK" || log_error "ShadowPC non trouvé"
    systemctl is-enabled --quiet shadowusb.service \
        && log_success "Service ShadowUSB activé" || log_error "Service ShadowUSB KO"
    [ -x /usr/local/bin/launch-shadow ] && [ -x /usr/local/bin/shadowusb-control ] \
        && log_success "Scripts OK" || log_error "Scripts manquants"
}

show_post_install_info() {
    echo
    log_info "=== Installation terminée ==="
    echo "Commandes utiles :"
    echo "  launch-shadow             → Lancer ShadowPC"
    echo "  shadowusb-control start   → Démarrer ShadowUSB"
    echo "  shadowusb-control logs    → Logs temps réel"
    echo
    log_warning "Redémarrage recommandé (sudo reboot)"
}

main() {
    echo "=== INSTALLATION SHADOW RPi5 ==="
    check_prerequisites
    update_system
    install_dependencies
    setup_flatpak
    install_shadow_pc
    install_shadow_usb
    setup_services
    setup_hardware_acceleration
    setup_network_optimizations
    create_launch_scripts
    setup_user_permissions
    test_installation
    show_post_install_info
}

main "$@"
