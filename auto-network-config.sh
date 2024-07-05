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

# Fonction pour vérifier si une interface existe
interface_exists() {
  ip link show | grep -q "$1:"
}

# Fonction pour obtenir la configuration existante d'une interface
get_existing_interface_config() {
  local interface=$1
  awk "/^$interface:/,/^[^[:space:]]/" "$config_file"
}

# Fonction pour obtenir la méthode de configuration d'une interface
get_interface_method() {
  local interface=$1
  if grep -q "$interface:" "$config_file"; then
    if grep -q "$interface:" "$config_file" | grep -q "dhcp4: true"; then
      echo "DHCP"
    else
      echo "Statique"
    fi
  else
    echo "Configuration non trouvée"
  fi
}

# Fonction pour obtenir l'adresse IP d'une interface
get_interface_ip() {
  local interface=$1
  ifconfig "$interface" | grep 'inet ' | awk '{print $2}'
}

# Fonction pour afficher la configuration actuelle d'une interface
display_interface_config() {
  local interface=$1

  # Lire la méthode de configuration
  method=$(get_interface_method "$interface")
  if [ "$method" == "Configuration non trouvée" ]; then
    echo "Configuration non trouvée pour l'interface $interface."
    return
  fi

  # Obtenir l'adresse IP de l'interface
  ip_address=$(get_interface_ip "$interface")

  echo ""
  echo "Configuration de l'interface $interface :"
  echo "Méthode de configuration : $method"
  echo "Adresse IP : $ip_address"
}

# Fonction pour afficher le menu principal
display_menu() {
  echo "Menu principal :"
  echo "1. Voir les interfaces disponibles"
  echo "2. Configurer une nouvelle interface"
  echo "3. Modifier une interface existante"
  echo "4. Afficher la configuration actuelle d'une interface"
  echo "5. Quitter"
}

# Fonction pour lister les interfaces réseau disponibles
list_network_interfaces() {
  ip link show | awk -F': ' '/^[0-9]+: / {print $2}' | grep -v '^lo$'
}

# Fonction pour configurer une nouvelle interface
configure_new_interface() {
  while true; do
    echo ""
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

    # Vérifier si l'interface est déjà configurée
    if grep -q "$interface_name:" "$config_file"; then
      echo ""
      echo "L'interface $interface_name est déjà configurée."
      existing_config=$(get_existing_interface_config "$interface_name")
      echo "Configuration actuelle :"
      echo "$existing_config"
      
      read -p "Souhaitez-vous modifier cette interface ? (o/n): " modify
      if [ "$modify" != "o" ]; then
        continue
      fi

      # Supprimer l'ancienne configuration de l'interface
      yaml_content=$(echo "$yaml_content" | sed "/$interface_name:/,/^[^[:space:]]/d")
    fi

    echo ""
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
}

# Fonction pour sauvegarder la configuration
save_and_apply_configuration() {
  # Écrire le contenu YAML dans le fichier de configuration
  echo -e "$yaml_content" > "$config_file"

  # Appliquer la configuration Netplan
  netplan apply
  if [ $? -ne 0 ]; then
    echo "Erreur : impossible d'appliquer la configuration Netplan."
    exit 1
  fi

  echo "La configuration réseau a été mise à jour, appliquée et les interfaces sont configurées."
}

# Fonction pour vérifier la configuration d'une interface existante
check_existing_interface() {
  while true; do
    echo ""
    read -p "Entrez le nom de l'interface réseau pour vérifier la configuration (ou appuyez sur Entrée pour terminer): " interface_name
    if [ -z "$interface_name" ]; then
      break
    fi

    # Obtenir la configuration existante
    existing_config=$(get_existing_interface_config "$interface_name")
    
    if [ -z "$existing_config" ]; then
      echo "Aucune configuration trouvée pour l'interface $interface_name."
      continue
    fi

    echo "Configuration actuelle :"
    echo "$existing_config"
    
    # Calcul de la passerelle pour vérification
    ip_address=$(echo "$existing_config" | grep "addresses:" | awk '{print $2}' | tr -d ',')
    if [ ! -z "$ip_address" ]; then
      gateway=$(extract_network "$ip_address")
      check_gateway_connectivity $gateway
    fi
  done
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

while true; do
  display_menu
  read -p "Choisissez une option : " option

  case $option in
    1)
      echo ""
      echo "Interfaces réseau disponibles :"
      list_network_interfaces
      echo -e "\n"
      ;;
    2)
      configure_new_interface
      echo -e "\n"
      save_and_apply_configuration
      echo -e "\n"
      ;;
    3)
      check_existing_interface
      echo -e "\n"
      ;;
    4)
      echo ""
      read -p "Entrez le nom de l'interface réseau pour afficher la configuration actuelle : " interface_name
      if [ -z "$interface_name" ]; then
        echo "Aucun nom d'interface fourni. Retour au menu."
        continue
      fi
      display_interface_config "$interface_name"
      ;;
    5)
      echo "Quitter"
      exit 0
      ;;
    *)
      echo "Option invalide. Veuillez choisir une option valide."
      ;;
  esac
done
