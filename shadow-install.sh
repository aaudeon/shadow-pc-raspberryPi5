#!/bin/bash

# Script d'installation complet ShadowPC + ShadowUSB pour Raspberry Pi 5
# Auteur: Assistant Claude
# Date: $(date)
# Compatible: Raspberry Pi OS (Debian-based)

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage coloré
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérification des prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    # Vérifier si on est sur un Raspberry Pi
    if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        log_warning "Ce script est optimisé pour Raspberry Pi, mais peut fonctionner sur d'autres systèmes ARM64"
    fi
    
    # Vérifier la version d'OS
    if ! command -v apt &> /dev/null; then
        log_error "Ce script nécessite un système basé sur Debian (apt)"
        exit 1
    fi
    
    # Vérifier les droits root
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté avec les droits root (sudo)"
        exit 1
    fi
    
    log_success "Prérequis validés"
}

# Mise à jour du système
update_system() {
    log_info "Mise à jour du système..."
    apt update && apt upgrade -y
    log_success "Système mis à jour"
}

# Installation des dépendances
install_dependencies() {
    log_info "Installation des dépendances..."
    
    # Dépendances de base
    apt install -y \
        wget \
        curl \
        git \
        build-essential \
        cmake \
        pkg-config \
        libssl-dev \
        libavcodec-dev \
        libavformat-dev \
        libavutil-dev \
        libswscale-dev \
        libswresample-dev \
        libsdl2-dev \
        libsdl2-ttf-dev \
        libva-dev \
        libvdpau-dev \
        libxkbcommon-dev \
        libwayland-dev \
        libx11-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        libasound2-dev \
        libpulse-dev \
        libudev-dev \
        libusb-1.0-0-dev \
        libevdev-dev \
        libdbus-1-dev \
        libsystemd-dev \
        flatpak \
        xdg-desktop-portal-gtk
    
    log_success "Dépendances installées"
}

# Configuration de Flatpak
setup_flatpak() {
    log_info "Configuration de Flatpak..."
    
    # Ajouter le dépôt Flathub
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    # Mettre à jour les dépôts Flatpak
    flatpak update --appstream
    
    log_success "Flatpak configuré"
}

# Installation de ShadowPC
install_shadow_pc() {
    log_info "Installation de ShadowPC..."
    
    # Télécharger et installer ShadowPC via Flatpak
    flatpak install -y flathub com.valvesoftware.Steam
    flatpak install -y flathub com.shadow.BetaClient
    
    # Alternative: installation manuelle si Flatpak ne fonctionne pas
    if ! flatpak list | grep -q "com.shadow.BetaClient"; then
        log_warning "Installation Flatpak échouée, tentative d'installation manuelle..."
        
        # Créer un répertoire temporaire
        mkdir -p /tmp/shadow-install
        cd /tmp/shadow-install
        
        # Télécharger le package ARM64 (adaptez l'URL selon la dernière version)
        wget -O shadow-beta.deb "https://update.shadow.tech/launcher/preprod/linux/ubuntu_18.04/shadow-beta.deb"
        
        # Installer le package
        dpkg -i shadow-beta.deb || apt-get install -f -y
        
        # Nettoyer
        cd /
        rm -rf /tmp/shadow-install
    fi
    
    log_success "ShadowPC installé"
}

# Installation de ShadowUSB
install_shadow_usb() {
    log_info "Installation de ShadowUSB..."
    
    # Créer un répertoire pour ShadowUSB
    mkdir -p /opt/shadowusb
    cd /opt/shadowusb
    
    # Cloner le dépôt ShadowUSB (ou télécharger depuis GitHub)
    if [ -d ".git" ]; then
        git pull
    else
        git clone https://github.com/NicolasGuilloux/shadow-usb-linux.git .
    fi
    
    # Compiler ShadowUSB
    make clean && make
    
    # Installer les binaires
    make install
    
    # Configurer les permissions udev
    cp rules/99-shadow-usb.rules /etc/udev/rules.d/
    udevadm control --reload-rules
    udevadm trigger
    
    log_success "ShadowUSB installé"
}

# Configuration des services système
setup_services() {
    log_info "Configuration des services système..."
    
    # Service ShadowUSB
    cat > /etc/systemd/system/shadowusb.service << 'EOF'
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

    # Recharger systemd et activer les services
    systemctl daemon-reload
    systemctl enable shadowusb.service
    
    log_success "Services configurés"
}

# Configuration de l'accélération matérielle
setup_hardware_acceleration() {
    log_info "Configuration de l'accélération matérielle pour Raspberry Pi 5..."
    
    # Configuration GPU
    if ! grep -q "gpu_mem=128" /boot/config.txt; then
        echo "gpu_mem=128" >> /boot/config.txt
    fi
    
    # Configuration pour H.264/H.265
    if ! grep -q "dtoverlay=vc4-kms-v3d" /boot/config.txt; then
        echo "dtoverlay=vc4-kms-v3d" >> /boot/config.txt
    fi
    
    # Variables d'environnement pour l'accélération
    cat > /etc/environment << 'EOF'
# Accélération matérielle Raspberry Pi 5
LIBVA_DRIVER_NAME=v4l2_request
LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12
EOF

    log_success "Accélération matérielle configurée"
}

# Configuration réseau et optimisations
setup_network_optimizations() {
    log_info "Application des optimisations réseau..."
    
    # Optimisations TCP pour le streaming
    cat > /etc/sysctl.d/99-shadow-network.conf << 'EOF'
# Optimisations réseau pour Shadow
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
EOF

    # Appliquer les modifications
    sysctl -p /etc/sysctl.d/99-shadow-network.conf
    
    log_success "Optimisations réseau appliquées"
}

# Création des scripts de lancement
create_launch_scripts() {
    log_info "Création des scripts de lancement..."
    
    # Script de lancement ShadowPC
    cat > /usr/local/bin/launch-shadow << 'EOF'
#!/bin/bash
# Script de lancement ShadowPC optimisé pour Raspberry Pi 5

# Variables d'environnement
export LIBVA_DRIVER_NAME=v4l2_request
export LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12
export SDL_VIDEODRIVER=wayland

# Lancer ShadowPC
if command -v flatpak &> /dev/null && flatpak list | grep -q "com.shadow.BetaClient"; then
    echo "Lancement de Shadow via Flatpak..."
    flatpak run com.shadow.BetaClient "$@"
elif command -v shadow-beta &> /dev/null; then
    echo "Lancement de Shadow (installation native)..."
    shadow-beta "$@"
else
    echo "Shadow n'est pas installé!"
    exit 1
fi
EOF

    # Script de contrôle ShadowUSB
    cat > /usr/local/bin/shadowusb-control << 'EOF'
#!/bin/bash
# Script de contrôle ShadowUSB

case "$1" in
    start)
        echo "Démarrage de ShadowUSB..."
        sudo systemctl start shadowusb.service
        ;;
    stop)
        echo "Arrêt de ShadowUSB..."
        sudo systemctl stop shadowusb.service
        ;;
    restart)
        echo "Redémarrage de ShadowUSB..."
        sudo systemctl restart shadowusb.service
        ;;
    status)
        systemctl status shadowusb.service
        ;;
    logs)
        journalctl -u shadowusb.service -f
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF

    # Rendre les scripts exécutables
    chmod +x /usr/local/bin/launch-shadow
    chmod +x /usr/local/bin/shadowusb-control
    
    log_success "Scripts de lancement créés"
}

# Configuration des permissions utilisateur
setup_user_permissions() {
    log_info "Configuration des permissions utilisateur..."
    
    # Ajouter l'utilisateur aux groupes nécessaires
    local current_user=$(logname 2>/dev/null || echo $SUDO_USER)
    if [ -n "$current_user" ]; then
        usermod -a -G input,plugdev,video,audio "$current_user"
        log_success "Permissions utilisateur configurées pour $current_user"
    else
        log_warning "Utilisateur non détecté, ajoutez manuellement votre utilisateur aux groupes: input, plugdev, video, audio"
    fi
}

# Test de l'installation
test_installation() {
    log_info "Test de l'installation..."
    
    # Vérifier ShadowPC
    if flatpak list | grep -q "com.shadow.BetaClient" || command -v shadow-beta &> /dev/null; then
        log_success "ShadowPC détecté"
    else
        log_error "ShadowPC non détecté"
    fi
    
    # Vérifier ShadowUSB
    if systemctl is-enabled shadowusb.service &> /dev/null; then
        log_success "Service ShadowUSB configuré"
    else
        log_error "Service ShadowUSB non configuré"
    fi
    
    # Vérifier les scripts
    if [ -x "/usr/local/bin/launch-shadow" ] && [ -x "/usr/local/bin/shadowusb-control" ]; then
        log_success "Scripts de lancement créés"
    else
        log_error "Scripts de lancement manquants"
    fi
}

# Affichage des informations post-installation
show_post_install_info() {
    log_info "Installation terminée!"
    echo
    echo "=== INFORMATIONS POST-INSTALLATION ==="
    echo
    echo "Commandes disponibles:"
    echo "  - launch-shadow          : Lancer ShadowPC"
    echo "  - shadowusb-control start: Démarrer ShadowUSB"
    echo "  - shadowusb-control stop : Arrêter ShadowUSB"
    echo "  - shadowusb-control status: Status de ShadowUSB"
    echo "  - shadowusb-control logs : Voir les logs ShadowUSB"
    echo
    echo "Prochaines étapes:"
    echo "  1. Redémarrer le système: sudo reboot"
    echo "  2. Lancer Shadow avec: launch-shadow"
    echo "  3. Configurer vos périphériques USB avec ShadowUSB"
    echo
    echo "Fichiers de configuration importants:"
    echo "  - Service ShadowUSB: /etc/systemd/system/shadowusb.service"
    echo "  - Règles udev: /etc/udev/rules.d/99-shadow-usb.rules"
    echo "  - Optimisations réseau: /etc/sysctl.d/99-shadow-network.conf"
    echo "  - Configuration boot: /boot/config.txt"
    echo
    log_success "Installation complète!"
}

# Fonction principale
main() {
    echo "=========================================="
    echo "  INSTALLATION SHADOWPC + SHADOWUSB"
    echo "      Pour Raspberry Pi 5"
    echo "=========================================="
    echo
    
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
    
    echo
    log_success "Script d'installation terminé avec succès!"
    log_warning "Un redémarrage est recommandé pour activer toutes les optimisations"
}

# Exécution du script principal
main "$@"