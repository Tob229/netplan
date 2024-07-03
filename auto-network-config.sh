#!/bin/bash

# Vérifier si figlet est installé
if ! command -v figlet &> /dev/null; then
    echo "figlet n'est pas installé. Installation ..."
    sudo apt-get install -y figlet > /dev/null
fi

# Afficher le nom du script en grand
figlet "AUTO NETWORK"

# Fonction pour extraire l'adresse réseau
extract_network() {
  IFS='/' read -r ip mask <<< "$1"
  IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
  echo "$i1.$i2.$i3.1"
}

# Fonction pour vérifier la configuration avec ifconfig
check_interface_config() {
  if ifconfig $1 &> /dev/null; then
    echo "L'interface $1 est configurée correctement."
  else
    echo "Erreur : l'interface $1 n'est pas configurée correctement."
    exit 1
  fi
}

# Fonction pour vérifier la connectivité en pingant la passerelle
check_gateway_connectivity() {
  ping -c 4 $1 &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Erreur : la passerelle $1 n'est pas joignable. Veuillez vérifier votre configuration."
    exit 1
  fi
}

# Fonction pour vérifier si une interface est déjà configurée
is_interface_configured() {
  grep -q "$1:" "$config_file"
}

# Fonction pour obtenir la configuration existante d'une interface
get_existing_interface_config() {
  grep -A5 "$1:" "$config_file" | grep -E 'addresses:|dhcp4:|routes:|nameservers:' | sed 's/^[ \t]*//'
}

# Recherche du fichier de configuration Netplan
config_file=$(find /etc/netplan -name "*.yaml")

if [ -z "$config_file" ]; then
  echo "Fichier de configuration Netplan non trouvé."
  exit 1
fi

# Initialiser le contenu du fichier YAML
yaml_content="network:\n  version: 2\n  ethernets:\n"

while true; do
  # Demande du nom de l'interface réseau
  read -p "Entrez le nom de votre interface réseau (ou appuyez sur Entrée pour terminer): " interface_name
  if [ -z "$interface_name" ]; then
    break
  fi

  if is_interface_configured "$interface_name"; then
    echo "L'interface $interface_name est déjà configurée."
    existing_config=$(get_existing_interface_config "$interface_name")
    echo "Configuration actuelle :"
    echo "$existing_config"
    
    read -p "Souhaitez-vous modifier cette interface ? (o/n): " modify
    if [ "$modify" != "o" ]; then
      continue
    fi
  fi

  # Choix entre configuration statique et DHCP
  read -p "Choisissez le type de configuration pour $interface_name (statique/dhcp): " config_type
  if [ "$config_type" == "statique" ]; then
    read -p "Entrez votre adresse IP (format: xxx.xxx.xxx.xxx/xx): " ip_address

    # Calcul de la passerelle
    gateway=$(extract_network "$ip_address")

    # Ajouter ou modifier la configuration de l'interface au contenu YAML
    yaml_content+="    $interface_name:\n      dhcp4: false\n      addresses:\n        - $ip_address\n      nameservers:\n        addresses: [8.8.8.8, 8.8.4.4]\n"
  elif [ "$config_type" == "dhcp" ]; then
    # Ajouter ou modifier la configuration de l'interface au contenu YAML
    yaml_content+="    $interface_name:\n      dhcp4: true\n"
  else
    echo "Configuration invalide. Veuillez entrer 'statique' ou 'dhcp'."
    continue
  fi
done

# Écrire le contenu YAML dans le fichier de configuration
echo -e "$yaml_content" > "$config_file"

# Appliquer la configuration Netplan
netplan apply
if [ $? -ne 0 ]; then
  echo "Erreur : impossible d'appliquer la configuration Netplan."
  exit 1
fi

# Vérifier la configuration de chaque interface réseau
while true; do
  read -p "Entrez le nom de l'interface réseau pour vérifier la configuration (ou appuyez sur Entrée pour terminer): " interface_name
  if [ -z "$interface_name" ]; then
    break
  fi

  check_interface_config $interface_name
  
  # Calcul de la passerelle pour vérification
  ip_address=$(grep -A1 "ethernets:" $config_file | grep -A1 "$interface_name:" | grep "addresses:" | awk '{print $2}' | tr -d ',')
  if [ ! -z "$ip_address" ]; then
    gateway=$(extract_network "$ip_address")
    check_gateway_connectivity $gateway
  fi
done

echo "La configuration réseau a été mise à jour, appliquée et les interfaces sont configurées."
