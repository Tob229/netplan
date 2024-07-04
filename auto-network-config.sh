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

# Fonction pour vérifier si une interface existe
interface_exists() {
  ip link show | grep -q "$1:"
}

# Fonction pour vérifier si une interface est déjà configurée
is_interface_configured() {
  grep -q "$1:" "$config_file"
}

# Fonction pour obtenir la configuration existante d'une interface
get_existing_interface_config() {
  grep -A5 "$1:" "$config_file" | grep -E 'addresses:|dhcp4:|routes:|nameservers:' | sed 's/^[ \t]*//'
}

# Fonction pour vérifier la validité de l'adresse IP
validate_ip() {
  local ip=$1
  local stat=1
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    IFS='/' read -r addr mask <<< "$ip"
    IFS='.' read -r -a octets <<< "$addr"
    if [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && ${octets[2]} -le 255 && ${octets[3]} -le 255 && $mask -le 32 ]]; then
      stat=0
    fi
  fi
  return $stat
}

# Fonction pour lister les interfaces réseau disponibles
list_network_interfaces() {
  ip link show | awk -F': ' '/^[0-9]+: / {print $2}' | grep -v '^lo$'
}

# Recherche du fichier de configuration Netplan
config_file=$(find /etc/netplan -name "*.yaml")

if [ -z "$config_file" ]; then
  echo "Fichier de configuration Netplan non trouvé."
  exit 1
fi

# Lire le contenu actuel du fichier YAML
yaml_content=$(cat "$config_file")

# Initialiser le contenu du fichier YAML s'il est vide
if [ -z "$yaml_content" ]; then
  yaml_content="network:\n  version: 2\n  ethernets:\n"
fi

# Afficher les interfaces disponibles au démarrage du script
echo "Interfaces réseau disponibles :"
list_network_interfaces
echo -e "\n\n"

while true; do
  # Demande du nom de l'interface réseau
  read -p "Entrez le nom de votre interface réseau (ou appuyez sur Entrée pour terminer): " interface_name
  
  if [ -z "$interface_name" ]; then
    break
  fi

  # Vérifier si l'interface existe
  if ! interface_exists "$interface_name"; then
    echo "Erreur : l'interface $interface_name n'existe pas. Veuillez vérifier le nom et réessayer."
    continue
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

    # Supprimer l'ancienne configuration de l'interface
    yaml_content=$(echo "$yaml_content" | sed "/$interface_name:/,/^$/d")
  fi

  # Choix entre configuration statique et DHCP
  read -p "Choisissez le type de configuration pour $interface_name (statique/dhcp): " config_type
  if [ "$config_type" == "statique" ]; then
    while true; do
      read -p "Entrez votre adresse IP (format: xxx.xxx.xxx.xxx/xx): " ip_address

      # Vérifier la validité de l'adresse IP
      if validate_ip "$ip_address"; then
        break
      else
        echo "Erreur : Adresse IP invalide. Veuillez entrer une adresse IP valide au format xxx.xxx.xxx.xxx/xx."
      fi
    done

    # Calcul de la passerelle
    gateway=$(extract_network "$ip_address")

    # Ajouter ou modifier la configuration de l'interface au contenu YAML
    yaml_content=$(echo -e "$yaml_content" | sed "/ethernets:/a \    $interface_name:\n      dhcp4: false\n      addresses:\n        - $ip_address\n      nameservers:\n        addresses: [8.8.8.8, 8.8.4.4]")
  elif [ "$config_type" == "dhcp" ]; then
    # Ajouter ou modifier la configuration de l'interface au contenu YAML
    yaml_content=$(echo -e "$yaml_content" | sed "/ethernets:/a \    $interface_name:\n      dhcp4: true")
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
