# ShadowPC + ShadowUSB pour Raspberry Pi 5

Ce projet fournit un script d'installation automatisé pour configurer **ShadowPC** et **ShadowUSB** sur un Raspberry Pi 5 avec optimisations spécifiques pour le streaming de jeux et la redirection USB.

## 🎮 Qu'est-ce que ShadowPC ?

ShadowPC est un service de cloud gaming qui vous permet d'accéder à un PC Windows virtuel haute performance depuis votre Raspberry Pi. Avec ce script, vous pouvez transformer votre Raspberry Pi 5 en une console de gaming cloud optimisée.

## 🔌 Qu'est-ce que ShadowUSB ?

ShadowUSB permet de rediriger vos périphériques USB locaux (manettes, claviers, souris, etc.) vers votre session Shadow, vous donnant une expérience de jeu native.

## 📋 Prérequis

- **Raspberry Pi 5** (recommandé, mais compatible avec d'autres systèmes ARM64)
- **Raspberry Pi OS** (ou autre distribution basée sur Debian)
- **Connexion internet stable** (recommandé : 50+ Mbps pour une expérience optimale)
- **Droits administrateur** (sudo)
- **Au moins 4 GB de RAM** (8 GB recommandé)
- **Carte microSD rapide** (Class 10 ou mieux) ou SSD USB

## 🚀 Installation rapide

### Méthode 1 : Installation automatique (recommandée)

```bash
# Télécharger et exécuter le script d'installation
curl -fsSL https://raw.githubusercontent.com/aaudeon/shadow-pc-raspberryPi5/main/shadow-install.sh | sudo bash
```

### Méthode 2 : Installation manuelle

```bash
# Cloner le dépôt
git clone https://github.com/aaudeon/shadow-pc-raspberryPi5.git
cd shadow-pc-raspberryPi5

# Rendre le script exécutable
chmod +x shadow-install.sh

# Exécuter l'installation
sudo ./shadow-install.sh
```

## 📦 Ce que le script installe

### Applications principales
- **ShadowPC** : Client Shadow pour le cloud gaming
- **ShadowUSB** : Service de redirection USB

### Dépendances système
- Bibliothèques de décodage vidéo (H.264/H.265)
- Drivers graphiques optimisés
- Support Wayland/X11
- Bibliothèques audio (ALSA/PulseAudio)
- Outils de développement pour la compilation

### Optimisations Raspberry Pi 5
- **Accélération matérielle GPU** : Configuration automatique du VideoCore VII
- **Optimisations réseau** : Paramètres TCP optimisés pour le streaming
- **Gestion mémoire** : Allocation GPU optimisée (128 MB)
- **Décodage matériel** : Support H.264/H.265 via V4L2

## 🎛️ Utilisation

### Lancer ShadowPC
```bash
launch-shadow
```

### Contrôler ShadowUSB
```bash
# Démarrer le service
shadowusb-control start

# Arrêter le service
shadowusb-control stop

# Redémarrer le service
shadowusb-control restart

# Voir le statut
shadowusb-control status

# Voir les logs en temps réel
shadowusb-control logs
```

## ⚙️ Configuration post-installation

### 1. Redémarrage obligatoire
Après l'installation, redémarrez votre Raspberry Pi pour activer toutes les optimisations :
```bash
sudo reboot
```

### 2. Premier lancement
1. Lancez Shadow avec `launch-shadow`
2. Connectez-vous avec vos identifiants Shadow
3. Configurez votre résolution et vos préférences

### 3. Configuration USB (optionnel)
Si vous souhaitez utiliser des périphériques USB avec Shadow :
1. Démarrez ShadowUSB : `shadowusb-control start`
2. Connectez vos périphériques USB
3. Ils apparaîtront automatiquement dans votre session Shadow

## 🔧 Optimisations appliquées

### Réseau
- **Buffer TCP** : Augmentation des buffers de réception/émission
- **Window Scaling** : Activation pour de meilleures performances sur liaisons à latence élevée
- **SACK** : Acquittements sélectifs pour une meilleure récupération d'erreurs

### GPU et vidéo
- **Mémoire GPU** : 128 MB alloués au GPU
- **Overlay VC4** : Driver KMS pour l'accélération 3D
- **Décodage matériel** : Support V4L2 pour H.264/H.265

### Système
- **Groupes utilisateur** : Ajout automatique aux groupes nécessaires
- **Services systemd** : Configuration automatique des services
- **Règles udev** : Permissions pour les périphériques USB

## 📁 Fichiers de configuration

| Fichier | Description |
|---------|-------------|
| `/etc/systemd/system/shadowusb.service` | Service systemd pour ShadowUSB |
| `/etc/udev/rules.d/99-shadow-usb.rules` | Règles udev pour les périphériques USB |
| `/etc/sysctl.d/99-shadow-network.conf` | Optimisations réseau |
| `/boot/config.txt` | Configuration de l'accélération matérielle |
| `/usr/local/bin/launch-shadow` | Script de lancement ShadowPC |
| `/usr/local/bin/shadowusb-control` | Script de contrôle ShadowUSB |

## 🐛 Dépannage

### Shadow ne se lance pas
```bash
# Vérifier l'installation Flatpak
flatpak list | grep shadow

# Vérifier les logs système
journalctl -u shadowusb.service -f

# Relancer l'installation de Shadow
sudo flatpak install --reinstall flathub com.shadow.BetaClient
```

### Problèmes de performance
```bash
# Vérifier l'accélération matérielle
vainfo

# Vérifier la mémoire GPU
vcgencmd get_mem gpu

# Optimiser la configuration
sudo raspi-config
# Advanced Options > Memory Split > 128
```

### Périphériques USB non détectés
```bash
# Vérifier le service ShadowUSB
shadowusb-control status

# Redémarrer le service
shadowusb-control restart

# Vérifier les permissions
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## 🔒 Sécurité

- Le script vérifie les prérequis avant installation
- Toutes les installations utilisent des sources officielles
- Les services sont configurés avec des permissions minimales
- Les règles udev sont sécurisées pour éviter les conflits

## 📊 Performances attendues

### Configuration minimale
- **Résolution** : 1080p à 30 FPS
- **Latence** : < 50ms avec une bonne connexion
- **Bande passante** : ~25 Mbps

### Configuration optimale
- **Résolution** : 1080p à 60 FPS
- **Latence** : < 30ms
- **Bande passante** : ~50 Mbps
- **Décodage matériel** : Activé

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
- Signaler des bugs via les [Issues](https://github.com/aaudeon/shadow-pc-raspberryPi5/issues)
- Proposer des améliorations via des [Pull Requests](https://github.com/aaudeon/shadow-pc-raspberryPi5/pulls)
- Partager vos configurations optimisées

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 🙏 Remerciements

- L'équipe Shadow pour leur service de cloud gaming
- La communauté Raspberry Pi pour les optimisations matérielles
- Les contributeurs du projet ShadowUSB

---

**Note** : Ce script est optimisé pour Raspberry Pi 5 mais peut fonctionner sur d'autres systèmes ARM64. Les performances peuvent varier selon votre matériel et votre connexion réseau.