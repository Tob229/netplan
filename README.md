# Auto Network Config

Ce script permet de configurer automatiquement vos interfaces réseau sur Ubuntu.

## Prérequis

- Ubuntu (ou toute autre distribution compatible avec `netplan`).

## Installation et Utilisation

Clonez le dépôt Git :

   ```bash
   git clone https://github.com/Tob229/netplan.git
   ```
   
## Accédez au répertoire cloné puis Rendez le script exécutable  :

```bash
cd netplan && chmod +x auto-network-config.sh
```

## Vider le contenu de votre fichier yaml  (optionnel ) :

```bash
sudo echo " " > /etc/netplan/*.yaml
```

## Exécutez le script avec les privilèges administratifs :

```bash
sudo ./auto-network-config.sh
```
## Suivez les instructions pour configurer vos interfaces réseau.



