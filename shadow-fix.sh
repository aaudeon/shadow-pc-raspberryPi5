#!/bin/bash

# Script de réparation pour Shadow sur Raspberry Pi
# Résout les problèmes de notifications et services manquants

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Fonction de diagnostic
diagnose_system() {
    log_info "Diagnostic du système..."
    
    echo "=== ÉTAT DU SYSTÈME ==="
    echo "Desktop Environment: ${XDG_CURRENT_DESKTOP:-Non défini}"
    echo "Session Type: ${XDG_SESSION_TYPE:-Non défini}"
    echo "Display: ${DISPLAY:-Non défini}"
    echo "Wayland Display: ${WAYLAND_DISPLAY:-Non défini}"
    
    # Vérifier les services critiques
    echo -e "\n=== SERVICES CRITIQUES ==="
    services=("dbus" "gdm3" "lightdm" "sddm" "xdg-desktop-portal")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $service: actif"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo -e "${YELLOW}⚠${NC} $service: installé mais inactif"
        else
            echo -e "${RED}✗${NC} $service: non trouvé"
        fi
    done
    
    # Vérifier les processus de notification
    echo -e "\n=== PROCESSUS DE NOTIFICATION ==="
    if pgrep -f "notification" > /dev/null; then
        echo -e "${GREEN}✓${NC} Processus de notification trouvé:"
        pgrep -af "notification"
    else
        echo -e "${RED}✗${NC} Aucun processus de notification actif"
    fi
    
    # Vérifier D-Bus
    echo -e "\n=== D-BUS ==="
    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
        echo -e "${GREEN}✓${NC} D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
    else
        echo -e "${RED}✗${NC} D-Bus session non configuré"
    fi
    
    # Vérifier XDG Desktop Portal
    if command -v xdg-desktop-portal &> /dev/null; then
        echo -e "${GREEN}✓${NC} xdg-desktop-portal installé"
    else
        echo -e "${RED}✗${NC} xdg-desktop-portal manquant"
    fi
}

# Installation des services de notification manquants
install_notification_services() {
    log_info "Installation des services de notification..."
    
    # Installer les paquets nécessaires
    apt update
    apt install -y \
        notification-daemon \
        libnotify-bin \
        dbus-x11 \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        dunst \
        at-spi2-core
    
    log_success "Services de notification installés"
}

# Configuration de notification-daemon
setup_notification_daemon() {
    log_info "Configuration du daemon de notifications..."
    
    # Créer le service utilisateur pour notification-daemon
    local user_home=$(getent passwd $SUDO_USER | cut -d: -f6)
    local systemd_user_dir="$user_home/.config/systemd/user"
    
    mkdir -p "$systemd_user_dir"
    
    cat > "$systemd_user_dir/notification-daemon.service" << 'EOF'
[Unit]
Description=Notification Daemon
PartOf=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/lib/notification-daemon/notification-daemon
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    # Alternative avec dunst (plus léger)
    cat > "$systemd_user_dir/dunst.service" << 'EOF'
[Unit]
Description=Dunst notification daemon
Documentation=man:dunst(1)
PartOf=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/bin/dunst
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    # Changer le propriétaire
    chown -R $SUDO_USER:$SUDO_USER "$user_home/.config"
    
    log_success "Services de notification configurés"
}

# Configuration D-Bus pour les notifications
setup_dbus_notifications() {
    log_info "Configuration D-Bus pour les notifications..."
    
    # S'assurer que le service D-Bus est actif
    systemctl enable dbus
    systemctl start dbus
    
    # Configuration D-Bus pour les notifications
    cat > /usr/share/dbus-1/services/org.freedesktop.Notifications.service << 'EOF'
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/bin/dunst
SystemdService=dunst.service
EOF

    log_success "D-Bus configuré pour les notifications"
}

# Configuration de l'environnement desktop
setup_desktop_environment() {
    log_info "Configuration de l'environnement desktop..."
    
    local user_home=$(getent passwd $SUDO_USER | cut -d: -f6)
    
    # Créer/modifier le fichier .xsessionrc
    cat > "$user_home/.xsessionrc" << 'EOF'
# Configuration pour Shadow et notifications
export XDG_CURRENT_DESKTOP=LXDE
export XDG_SESSION_TYPE=x11
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Démarrer les services nécessaires
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Démarrer le service de notifications
if ! pgrep -f "dunst|notification-daemon" > /dev/null; then
    dunst &
fi

# Variables pour l'accélération matérielle
export LIBVA_DRIVER_NAME=v4l2_request
export LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12
EOF

    # Créer le fichier .profile
    cat > "$user_home/.profile" << 'EOF'
# Configuration pour Shadow
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# Variables d'environnement
export XDG_CURRENT_DESKTOP=LXDE
export XDG_SESSION_TYPE=x11
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# Démarrer D-Bus si nécessaire
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ "$XDG_SESSION_TYPE" = "x11" ]; then
    export $(dbus-launch)
fi
EOF

    chown $SUDO_USER:$SUDO_USER "$user_home/.xsessionrc"
    chown $SUDO_USER:$SUDO_USER "$user_home/.profile"
    
    log_success "Environnement desktop configuré"
}

# Script de lancement Shadow corrigé
create_fixed_shadow_launcher() {
    log_info "Création du script de lancement Shadow corrigé..."
    
    cat > /usr/local/bin/shadow-fixed << 'EOF'
#!/bin/bash

# Script de lancement Shadow avec corrections pour Raspberry Pi 5

# Couleurs pour les messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== LANCEMENT SHADOW CORRIGÉ ===${NC}"

# Vérifier et configurer D-Bus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    echo -e "${YELLOW}Configuration D-Bus...${NC}"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    
    # Si le bus n'existe pas, le créer
    if [ ! -S "/run/user/$(id -u)/bus" ]; then
        eval $(dbus-launch --sh-syntax)
    fi
fi

# Démarrer le service de notifications si nécessaire
if ! pgrep -f "dunst|notification-daemon" > /dev/null; then
    echo -e "${YELLOW}Démarrage du service de notifications...${NC}"
    dunst &
    sleep 2
fi

# Variables d'environnement pour Shadow
export XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-LXDE}
export XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-x11}
export LIBVA_DRIVER_NAME=v4l2_request
export LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video10,/dev/video11,/dev/video12

# Options de lancement optimisées
SHADOW_OPTIONS=(
    "--disable-gpu-sandbox"
    "--use-gl=egl"
    "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder"
    "--disable-features=VizDisplayCompositor"
    "--enable-gpu-rasterization"
    "--enable-zero-copy"
    "--disable-background-timer-throttling"
    "--disable-backgrounding-occluded-windows"
    "--disable-renderer-backgrounding"
)

echo -e "${GREEN}Lancement de Shadow avec les options optimisées...${NC}"
echo "D-Bus: $DBUS_SESSION_BUS_ADDRESS"
echo "Desktop: $XDG_CURRENT_DESKTOP"
echo "Session: $XDG_SESSION_TYPE"

# Tester les notifications avant de lancer Shadow
if command -v notify-send &> /dev/null; then
    notify-send "Shadow" "Lancement en cours..." 2>/dev/null || echo "Test de notification échoué (normal au premier lancement)"
fi

# Lancer Shadow
if command -v shadow-prod &> /dev/null; then
    echo -e "${GREEN}Lancement de shadow-prod...${NC}"
    shadow-prod "${SHADOW_OPTIONS[@]}" "$@"
elif command -v shadow-beta &> /dev/null; then
    echo -e "${GREEN}Lancement de shadow-beta...${NC}"
    shadow-beta "${SHADOW_OPTIONS[@]}" "$@"
elif flatpak list | grep -q "com.shadow.BetaClient"; then
    echo -e "${GREEN}Lancement via Flatpak...${NC}"
    flatpak run com.shadow.BetaClient "$@"
else
    echo -e "${RED}Shadow n'est pas installé!${NC}"
    exit 1
fi
EOF

    chmod +x /usr/local/bin/shadow-fixed
    
    log_success "Script de lancement Shadow corrigé créé"
}

# Test des corrections
test_fixes() {
    log_info "Test des corrections..."
    
    # Test D-Bus
    if systemctl is-active --quiet dbus; then
        log_success "D-Bus actif"
    else
        log_error "D-Bus inactif"
    fi
    
    # Test des notifications en tant qu'utilisateur
    local user_home=$(getent passwd $SUDO_USER | cut -d: -f6)
    
    # Test avec sudo pour simuler l'utilisateur
    if sudo -u $SUDO_USER DISPLAY=:0 notify-send "Test" "Notifications fonctionnelles" 2>/dev/null; then
        log_success "Notifications fonctionnelles"
    else
        log_warning "Notifications peuvent nécessiter un redémarrage"
    fi
    
    # Vérifier les fichiers créés
    if [ -f "/usr/local/bin/shadow-fixed" ]; then
        log_success "Script shadow-fixed créé"
    else
        log_error "Script shadow-fixed manquant"
    fi
}

# Service de démarrage automatique des notifications
create_autostart_service() {
    log_info "Création du service de démarrage automatique..."
    
    local user_home=$(getent passwd $SUDO_USER | cut -d: -f6)
    local autostart_dir="$user_home/.config/autostart"
    
    mkdir -p "$autostart_dir"
    
    cat > "$autostart_dir/shadow-notifications.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Shadow Notifications Service
Exec=sh -c 'sleep 3 && dunst'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
EOF

    chown -R $SUDO_USER:$SUDO_USER "$autostart_dir"
    
    log_success "Service de démarrage automatique créé"
}

# Fonction principale
main() {
    echo "================================================="
    echo "   RÉPARATION SHADOW - PROBLÈMES NOTIFICATIONS"
    echo "================================================="
    echo
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté avec sudo"
        exit 1
    fi
    
    if [ -z "$SUDO_USER" ]; then
        log_error "Variable SUDO_USER non définie"
        exit 1
    fi
    
    diagnose_system
    echo
    read -p "Continuer avec les réparations ? (o/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[OoYy]$ ]]; then
        install_notification_services
        setup_notification_daemon
        setup_dbus_notifications
        setup_desktop_environment
        create_fixed_shadow_launcher
        create_autostart_service
        test_fixes
        
        echo
        echo "=== INSTRUCTIONS POST-RÉPARATION ==="
        echo "1. Redémarrer le système: sudo reboot"
        echo "2. Utiliser le nouveau script: shadow-fixed"
        echo "3. Ou avec les anciennes commandes: shadow-prod --disable-gpu-sandbox --use-gl=egl"
        echo
        echo "Si le problème persiste:"
        echo "- Vérifier que vous êtes dans une session graphique complète"
        echo "- Essayer: sudo systemctl --user --global enable dunst.service"
        echo "- Lancer manuellement: dunst & puis shadow-prod"
        echo
        log_success "Réparations terminées!"
        log_warning "Un redémarrage est fortement recommandé"
    else
        log_info "Réparations annulées"
    fi
}

main "$@"