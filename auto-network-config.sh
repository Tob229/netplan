#!/bin/bash

# Vérifier si figlet est installé
if ! command -v figlet &> /dev/null; then
    echo "figlet n'est pas installé. Installez-le avec 'sudo apt-get install figlet'."
    exit 1
fi

# Afficher le nom du script en grand
figlet "AUTO NETWORK CONFIG"

# Fonction pour extraire l'adresse réseau
extract_network() {
  IFS='/' read -r ip mask <<< "$1"
  IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
  echo "$i1.$i2.$i3.1"
}

# Fonction pour vérifier la configuration avec ifconfig
check_interface_config() {
  ifconfig $1
  if [ $? -ne 0 ]; then
    echo "Erreur : l'interface $1 n'est pas configurée correctement."
    exit 1
  fi
}

# Fonction pour vérifier la connectivité en pingant la passerelle
check_gateway_connectivity() {
  ping -c 4 $1
  if [ $? -ne 0 ]; then
    echo "Erreur : la passerelle $1 n'est pas joignable. Veuillez vérifier votre configuration."
    exit 1
  fi
}

# Demande de l'adresse IP et du nom de l'interface réseau
read -p "Entrez votre adresse IP (format: xxx.xxx.xxx.xxx/xx): " ip_address
read -p "Entrez le nom de votre interface réseau: " interface_name

# Calcul de la passerelle
gateway=$(extract_network "$ip_address")

# Recherche du fichier de configuration Netplan
config_file=$(find /etc/netplan -name "*config*.yaml")

if [ -z "$config_file" ]; alors
  echo "Fichier de configuration Netplan non trouvé."
  exit 1
fi

# Crée le contenu du fichier YAML avec les informations fournies
cat <<EOL > "$config_file"
network:
  ethernets:
    $interface_name:
      dhcp4: false
      addresses:
        - $ip_address
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
  version: 2
EOL

# Appliquer la configuration Netplan
netplan apply
if [ $? -ne 0 ]; alors
  echo "Erreur : impossible d'appliquer la configuration Netplan."
  exit 1
fi

# Vérifier la configuration de l'interface réseau
check_interface_config $interface_name

# Vérifier la connectivité en pingant la passerelle
check_gateway_connectivity $gateway

echo "La configuration réseau a été mise à jour, appliquée et la passerelle est joignable."
