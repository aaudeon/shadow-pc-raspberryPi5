#!/usr/bin/env bash
set -euo pipefail

g() { printf "\033[1;32m%s\033[0m\n" "$*"; }
y() { printf "\033[1;33m%s\033[0m\n" "$*"; }
r() { printf "\033[1;31m%s\033[0m\n" "$*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    r "Ce script doit être exécuté avec sudo ou root."
    exit 1
  fi
}

check_network() {
  g "Vérification connectivité réseau…"
  if ! ping -c1 -W2 deb.debian.org >/dev/null 2>&1; then
    r "Pas d’accès réseau. Veuillez vérifier la connexion Internet."
    exit 1
  fi
}

detect_arch() {
  ARCH="$(dpkg --print-architecture)"
  g "Architecture détectée : $ARCH"
  # Shadow supporte arm64 pour Raspberry Pi OS 64 bits selon la doc. :contentReference[oaicite:0]{index=0}
  if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
    r "Architecture non supportée par ce script (attendu arm64 ou amd64)."
    exit 1
  fi
}

install_base_tools() {
  g "Installation des outils de base (wget, gpg, ca-certificates…)…"
  apt-get update -y
  apt-get install -y wget gpg apt-transport-https ca-certificates
  
  # Nettoyer les paquets partiellement configurés (shadowusb a une erreur connue)
  dpkg --configure -a 2>/dev/null || true
}

add_shadow_signing_key_and_repo() {
  g "Ajout de la clé de signature Shadow et du dépôt 'prod' (bullseye)…"

  # On récupère la clé officielle
  wget -qO- http://repository.shadow.tech/shadow_signing.key \
    | gpg --dearmor > packages.shadowapp.gpg

  # On installe la clé dans trusted.gpg.d
  install -o root -g root -m 644 packages.shadowapp.gpg /etc/apt/trusted.gpg.d/
  rm -f packages.shadowapp.gpg

  # Ajouter le dépôt – on force "bullseye" qui est supporté par Shadow
  # Important: spécifier [signed-by=...] pour éviter les warnings
  echo "deb [arch=$ARCH signed-by=/etc/apt/trusted.gpg.d/packages.shadowapp.gpg] http://repository.shadow.tech/prod bullseye main" \
    > /etc/apt/sources.list.d/shadow-prod.list
}

install_shadow_packages() {
  g "Installation directe de Shadow pour Raspberry Pi (ARM64)…"
  
  # Pour Raspberry Pi, Shadow recommande l'installation directe du .deb
  # car le dépôt ne contient pas toujours les bons paquets pour ARM64
  cd /tmp
  
  # Téléchargement de Shadow pour Raspberry Pi
  g "Téléchargement de shadow-arm64.deb…"
  wget -O shadow-arm64.deb https://update.shadow.tech/launcher/prod/linux/rpi/shadow-arm64.deb
  
  # Installation de Shadow
  g "Installation de Shadow…"
  if apt install -y ./shadow-arm64.deb; then
    g "Shadow installé avec succès."
  else
    y "Tentative de réparation des dépendances…"
    dpkg -i shadow-arm64.deb || true
    apt-get install -f -y
  fi
  rm -f shadow-arm64.deb
  
  # Installation de ShadowUSB depuis le dépôt
  g "Installation de shadowusb depuis le dépôt…"
  apt-get update -y
  
  # Nettoyer d'éventuels fichiers temporaires
  rm -rf /tmp/shadowusb_*.deb /tmp/shadowusb-fixed /tmp/shadowusb-fixed.deb
  
  # Télécharger et corriger le paquet shadowusb (bug connu dans le script postinst)
  g "Téléchargement et correction du paquet shadowusb…"
  cd /tmp
  apt download shadowusb 2>/dev/null || true
  
  if ls /tmp/shadowusb_*.deb >/dev/null 2>&1; then
    # Extraire le paquet
    dpkg-deb -R shadowusb_*.deb shadowusb-fixed
    
    # Corriger le bug du chemin relatif dans le script postinst
    sed -i 's|systemd_install "$(systemd_find_system_service_location)"|systemd_install "/lib/systemd/system"|g' \
      shadowusb-fixed/DEBIAN/postinst
    
    # Reconstruire le paquet
    dpkg-deb -b shadowusb-fixed shadowusb-fixed.deb >/dev/null 2>&1
    
    # Installer le paquet corrigé
    if apt install -y /tmp/shadowusb-fixed.deb; then
      g "✓ shadowusb installé avec succès (version corrigée)."
    else
      y "⚠ Installation de shadowusb avec erreurs, mais probablement fonctionnel."
      dpkg --configure -a 2>/dev/null || true
    fi
    
    # Nettoyer
    rm -rf /tmp/shadowusb_*.deb /tmp/shadowusb-fixed /tmp/shadowusb-fixed.deb
  else
    y "⚠ shadowusb non disponible dans le dépôt."
  fi
}



post_checks() {
  g "Vérifications post-installation…"
  
  # Vérifier Shadow (le binaire peut s'appeler shadow-prod, shadow-launcher ou shadow-beta)
  if command -v shadow-prod >/dev/null 2>&1; then
    y "✓ shadow-prod disponible"
  elif command -v shadow-launcher >/dev/null 2>&1; then
    y "✓ shadow-launcher disponible"
  elif command -v shadow-beta >/dev/null 2>&1; then
    y "✓ shadow-beta disponible"
  elif dpkg -l | grep -qE "shadow-prod|shadow-beta|shadow-launcher"; then
    y "✓ Shadow installé (confirmé via dpkg)"
  else
    r "✗ Shadow non trouvé !"
  fi
  
  # Vérifier ShadowUSB
  if dpkg -l | grep -q shadowusb; then
    y "✓ shadowusb installé (confirmé via dpkg)"
  else
    y "⚠ shadowusb non installé (optionnel)"
  fi
  
  # Afficher les applications desktop disponibles
  if ls /usr/share/applications/shadow*.desktop >/dev/null 2>&1; then
    y "✓ Lanceurs Shadow trouvés dans les applications:"
    ls /usr/share/applications/shadow*.desktop | sed 's|.*/||' | sed 's|^|  - |'
  fi
  
  # Vérifier les groupes utilisateur
  if groups "$SUDO_USER" 2>/dev/null | grep -q "shadow-input"; then
    y "✓ Utilisateur dans le groupe shadow-input"
  fi
  if groups "$SUDO_USER" 2>/dev/null | grep -q "shadow-users"; then
    y "✓ Utilisateur dans le groupe shadow-users"
  fi
  
  g ""
  g "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  g "Installation terminée avec succès ! 🎉"
  y "⚠  IMPORTANT: Redémarrez votre système pour que les modifications de groupe prennent effet."
  g "Après le redémarrage, lancez Shadow depuis le menu des applications."
  g "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main() {
  require_root
  check_network
  detect_arch
  install_base_tools
  add_shadow_signing_key_and_repo
  install_shadow_packages
  post_checks
}

main "$@"
