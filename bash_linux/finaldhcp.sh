#!/bin/bash

# FUNCIONES DE VALIDACION DE IP
validar_ip_rango() {
 # Verifica formato basico
 [[ $1 =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]] || return 1
 IFS='.' read -r oc1 oc2 oc3 oc4 <<< "$1"

 for o in $oc1 $oc2 $oc3 $oc4; do
  [[ $o -ge 0 && $o -le 255 ]] || return 1
 done

 # No permitir IP reservadas
 [[ "$1" == "0.0.0.0" ]] && return 1
 [[ $oc1 -eq 127 || $oc1 -eq 0 ]] && return 1

 return 0
}

# CONVERSION IP <-> NUMERO
ip_a_numero_rango() {
 IFS='.' read -r oc1 oc2 oc3 oc4 <<< "$1"
 echo $(( (oc1<<24) + (oc2<<16) + (oc3<<8) + oc4 ))
}

numero_a_ip_rango() {
 num=$1
 oc1=$(( (num >> 24) & 255 ))
 oc2=$(( (num >> 16) & 255 ))
 oc3=$(( (num >> 8) & 255 ))
 oc4=$(( num & 255 ))
 echo "$oc1.$oc2.$oc3.$oc4"
}

# VALIDAR RANGO DE IP
validar_rango_ip() {
 [[ $(ip_a_numero_rango "$2") -ge $(ip_a_numero_rango "$1") ]]
}

# SUMAR UNO A UNA IP
sumar_uno_ip_rango() {
 num=$(ip_a_numero_rango "$1")
 nueva=$((num + 1))
 numero_a_ip_rango $nueva
}

# VERIFICAR MISMA RED
misma_red_rango() {
 IFS='.' read -r a1 a2 a3 _ <<< "$1"
 IFS='.' read -r b1 b2 b3 _ <<< "$2"
 [[ $a1 -eq $b1 && $a2 -eq $b2 && $a3 -eq $b3 ]]
}

# OBTENER MASCARA SEGUN CLASE DE IP
obtener_mascara_rango() {
  echo "255.255.255.0"
}

# VERIFICAR DHCP
verificar_dhcp_rango() {
 rpm -q dhcp-server &>/dev/null && echo "DHCP instalado " || echo "DHCP no instalado "
}

# INSTALAR DHCP
instalar_dhcp_rango() {
 if rpm -q dhcp-server &>/dev/null; then
  echo ""
  read -p "Quieres reinstalar? (s/n): " opcion
  if [[ $opcion == "s" || $opcion == "S" ]]; then
   echo "Reinstalando DHCP..."
   sudo urpmi --replacepkgs --auto dhcp-server &>/dev/null
   echo "Reinstalacion completa"
  else
   echo "Instalacion cancelada"
  fi
 else
  echo "Instalando DHCP..."
  sudo urpmi --auto dhcp-server &>/dev/null
  echo "Instalacion completa"
 fi
}

# CONFIGURAR DHCP
configurar_dhcp_rango() {
 echo "Configuracion de rangos IP"

 while true; do
  read -p "IP inicial: " IP_INICIAL
  validar_ip_rango "$IP_INICIAL" && break
  echo "IP inicial invalida.. "
 done

 while true; do
  read -p "IP final: " IP_FINAL
  validar_ip_rango "$IP_FINAL" && break
  echo "IP final invalida.."
 done

 if ! misma_red_rango "$IP_INICIAL" "$IP_FINAL"; then
  echo "Error: IP no pertenecen a la misma red"
  exit 1
 fi

 if ! validar_rango_ip "$IP_INICIAL" "$IP_FINAL"; then
  echo "Rango invalido"
  exit 1
 fi

 IP_SERVIDOR="$IP_INICIAL"
 IP_RANGO_INICIAL=$(sumar_uno_ip_rango "$IP_INICIAL")
 if ! validar_rango_ip "$IP_RANGO_INICIAL" "$IP_FINAL"; then
  echo "Error:"
  exit 1
 fi

 # Configuracion de DNS y tiempos de lease
 read -p "DNS1 opcional: " DNS1
 read -p "DNS2 opcional: " DNS2
 [ -z "$DNS1" ] && DNS1="8.8.8.8"
 [ -z "$DNS2" ] && DNS_CONFIG="option domain-name-servers $DNS1;" || DNS_CONFIG="option domain-name-servers $DNS1, $DNS2;"

 read -p "Tiempo de duracion: " LEASE_DEFAULT
 read -p "Tiempo de duracion maximo: " LEASE_MAX
 [ -z "$LEASE_DEFAULT" ] && LEASE_DEFAULT=300
 [ -z "$LEASE_MAX" ] && LEASE_MAX=300

 mascara=$(obtener_mascara_rango "$IP_SERVIDOR")
 red=${IP_SERVIDOR%.*}.0

 # Configurar IP en la interfaz enp0s8
 sudo ip addr flush dev enp0s8
 sudo ip addr add $IP_SERVIDOR/24 dev enp0s8
 sudo ip link set enp0s8 up

 # Crear archivo de configuracion dhcpd.conf
 sudo tee /etc/dhcpd.conf >/dev/null <<EOF
default-lease-time $LEASE_DEFAULT;
max-lease-time $LEASE_MAX;
authoritative;

subnet $red netmask $mascara {
 range $IP_RANGO_INICIAL $IP_FINAL;
 option routers $IP_SERVIDOR;
 $DNS_CONFIG
}
EOF

 echo "DHCPD_INTERFACE=enp0s8" | sudo tee /etc/sysconfig/dhcpd >/dev/null

 echo "Rangos configurados:"
 echo "IP fija servidor: $IP_SERVIDOR"
 echo "Rango dhcp: $IP_RANGO_INICIAL hasta $IP_FINAL"
}

# GUARDAR CONFIG Y REINICIAR DHCP
guardar() {
 echo "Guardando configuracion...."
 if sudo dhcpd -t &>/dev/null; then
  sudo systemctl enable dhcpd &>/dev/null
  if sudo systemctl restart dhcpd &>/dev/null; then
   echo "Guardando y reiniciando"
  else
   echo "Error no se reinicio"
  fi
 else
  echo "configuracion invalida"
 fi
}

# MONITOREO DHCP
monitoreo_rango() {
 echo "Estado del servidor DHCP:"
 systemctl is-active --quiet dhcpd && echo "Activado" || echo "Desactivado"
 echo ""
 echo "Clientes conectados:"
 grep "lease " /var/lib/dhcpd/dhcpd.leases 2>/dev/null
}

# RESET DHCP
reset_dhcp_rango() {
 sudo systemctl stop dhcpd 2>/dev/null
 sudo systemctl disable dhcpd 2>/dev/null
 sudo rm -f /etc/dhcpd.conf /var/lib/dhcpd/dhcpd.leases >/dev/null 2>&1
 sudo dnf remove -y dhcp-server >/dev/null 2>&1
 echo "Reset completo "
}

# MENU PRINCIPAL
case "$1" in
verificar) verificar_dhcp_rango ;;
instalar) instalar_dhcp_rango ;;
configurar) configurar_dhcp_rango ;;
guardar) guardar ;;
monitoreo) monitoreo_rango ;;
reset) reset_dhcp_rango ;;
*) 
 echo "Comandos de dhcp :"
 echo " ./DHCP_nuevo.sh verificar"
 echo " ./DHCP_nuevo.sh instalar"
 echo " ./DHCP_nuevo.sh configurar"
 echo " ./DHCP_nuevo.sh guardar"
 echo " ./DHCP_nuevo.sh monitoreo"
 echo " ./DHCP_nuevo.sh reset"
 exit 1
 ;;
esac
