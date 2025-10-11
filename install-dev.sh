#!/usr/bin/env bash
set -euo pipefail

### --------------------------------------------------------------
###  Dev bootstrap for Raspberry Pi (VS Code + Git + essentials)
###  Raspberry Pi OS Trixie/Bookworm (arm64/armhf)
###  v1.1 - remove software-properties-common + add .deb fallback
### --------------------------------------------------------------

g() { printf "\033[1;32m%s\033[0m\n" "$*"; }
y() { printf "\033[1;33m%s\033[0m\n" "$*"; }
r() { printf "\033[1;31m%s\033[0m\n" "$*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    r "Veuillez exécuter ce script avec sudo ou en root."
    exit 1
  fi
}

check_network() {
  y "Vérification de la connectivité réseau…"
  if ! ping -c1 -W2 deb.debian.org >/dev/null 2>&1; then
    r "Pas d'accès réseau. Connectez le Raspberry Pi à Internet puis relancez."
    exit 1
  fi
}

detect_arch() {
  ARCH="$(dpkg --print-architecture)"
  case "$ARCH" in
    arm64|armhf) g "Architecture détectée : $ARCH" ;;
    *)
      r "Architecture non supportée ($ARCH). Ce script cible arm64/armhf."
      exit 1
      ;;
  esac
}

prep_system() {
  g "Mise à jour APT et installation des paquets de base…"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl wget gnupg apt-transport-https \
    build-essential pkg-config \
    git git-lfs \
    unzip zip tar xz-utils \
    openssh-client
  git lfs install --system || true
}

install_vscode_repo() {
  g "Ajout du dépôt Microsoft VS Code…"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
  chmod a+r /etc/apt/keyrings/packages.microsoft.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt-get update -y
}

install_vscode_from_repo() {
  g "Installation de Visual Studio Code via APT…"
  apt-get install -y code
}

install_vscode_fallback_deb() {
  g "Fallback : installation via .deb officiel (latest)…"
  cd /tmp
  case "$(dpkg --print-architecture)" in
    arm64) DEB_URL="https://update.code.visualstudio.com/latest/linux-deb-arm64/stable" ;;
    armhf) DEB_URL="https://update.code.visualstudio.com/latest/linux-deb-armhf/stable" ;;
  esac
  wget -O code_latest.deb "$DEB_URL"
  dpkg -i code_latest.deb || apt-get -f install -y
}

post_checks() {
  g "Vérifications…"
  if command -v code >/dev/null 2>&1; then
    y "VS Code : $(code --version | head -n1)"
  else
    r "VS Code n'est pas dans le PATH. Vérifiez l'installation."
  fi
  if command -v git >/dev/null 2>&1; then
    y "Git : $(git --version)"
  else
    r "Git n'est pas dans le PATH. Vérifiez l'installation."
  fi
}

optional_tweaks() {
  cat <<'EOF'

─ Options utiles (facultatives) ──────────────────────────────────────────
• Node.js LTS :
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs

• Python outils dev :
    sudo apt-get install -y python3-pip python3-venv

• Extensions VS Code (exemples) :
    code --install-extension ms-python.python
    code --install-extension ms-vscode.cpptools
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension esbenp.prettier-vscode
    code --install-extension eamodio.gitlens

• Lancer VS Code :
    code
──────────────────────────────────────────────────────────────────────────
EOF
}

main() {
  require_root
  check_network
  detect_arch
  prep_system
  if install_vscode_repo && install_vscode_from_repo; then
    g "VS Code installé via le dépôt Microsoft."
  else
    y "Le dépôt Microsoft a échoué, bascule sur le .deb…"
    install_vscode_fallback_deb
  fi
  post_checks
  optional_tweaks
  g "Installation terminée ✅"
}

main "$@"
