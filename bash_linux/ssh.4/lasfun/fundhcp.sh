#!/bin/bash


INTERFAZ_DHCP="enp0s8"


# VALIDACION IP

validar_ip_rango() {

 [[ $1 =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]] || return 1

 IFS='.' read -r oc1 oc2 oc3 oc4 <<< "$1"

 for o in $oc1 $oc2 $oc3 $oc4; do
  [[ $o -ge 0 && $o -le 255 ]] || return 1
 done

 [[ "$1" == "0.0.0.0" ]] && return 1
 [[ $oc1 -eq 127 || $oc1 -eq 0 ]] && return 1

 return 0
}


# IP -> NUMERO

ip_a_numero_rango() {
 IFS='.' read -r oc1 oc2 oc3 oc4 <<< "$1"
 echo $(( (oc1<<24)+(oc2<<16)+(oc3<<8)+oc4 ))
}

numero_a_ip_rango() {
 num=$1
 echo "$((num>>24&255)).$((num>>16&255)).$((num>>8&255)).$((num&255))"
}

validar_rango_ip() {
 [[ $(ip_a_numero_rango "$2") -ge $(ip_a_numero_rango "$1") ]]
}

sumar_uno_ip_rango() {
 numero_a_ip_rango $(( $(ip_a_numero_rango "$1")+1 ))
}

misma_red_rango() {
 IFS='.' read -r a1 a2 a3 _ <<< "$1"
 IFS='.' read -r b1 b2 b3 _ <<< "$2"
 [[ $a1 -eq $b1 && $a2 -eq $b2 && $a3 -eq $b3 ]]
}

obtener_mascara_rango() {
 echo "255.255.255.0"
}


# DHCP INSTALACION

verificar_dhcp_rango() {
 rpm -q dhcp-server &>/dev/null && \
 echo "DHCP instalado" || echo "DHCP no instalado"
}

instalar_dhcp_rango() {

 if rpm -q dhcp-server &>/dev/null; then
  read -p "Quieres reinstalar? (s/n): " opcion

  if [[ $opcion =~ [sS] ]]; then
   urpmi --replacepkgs --auto dhcp-server
  fi
 else
  urpmi --auto dhcp-server
 fi

 echo "Instalacion DHCP completa"
}

# CONFIGURACION DHCP

configurar_dhcp_rango() {

 echo "Configuracion DHCP en interfaz $INTERFAZ_DHCP"

 while true; do
  read -p "IP inicial servidor: " IP_INICIAL
  validar_ip_rango "$IP_INICIAL" && break
  echo "IP invalida"
 done

 while true; do
  read -p "IP final rango: " IP_FINAL
  validar_ip_rango "$IP_FINAL" && break
  echo "IP invalida"
 done

 misma_red_rango "$IP_INICIAL" "$IP_FINAL" || {
  echo "No estan en la misma red"
  exit 1
 }

 validar_rango_ip "$IP_INICIAL" "$IP_FINAL" || {
  echo "Rango incorrecto"
  exit 1
 }

 IP_SERVIDOR="$IP_INICIAL"
 IP_RANGO_INICIAL=$(sumar_uno_ip_rango "$IP_INICIAL")

 read -p "DNS1 (default 8.8.8.8): " DNS1
 read -p "DNS2 opcional: " DNS2

 [ -z "$DNS1" ] && DNS1="8.8.8.8"

 if [ -z "$DNS2" ]; then
  DNS_CONFIG="option domain-name-servers $DNS1;"
 else
  DNS_CONFIG="option domain-name-servers $DNS1, $DNS2;"
 fi

 read -p "Lease default (300): " LEASE_DEFAULT
 read -p "Lease max (300): " LEASE_MAX

 [ -z "$LEASE_DEFAULT" ] && LEASE_DEFAULT=300
 [ -z "$LEASE_MAX" ] && LEASE_MAX=300

 mascara=$(obtener_mascara_rango)
 red=${IP_SERVIDOR%.*}.0


 # CONFIGURAR SOLO ADAPTADOR 2

 ip addr flush dev $INTERFAZ_DHCP
 ip addr add $IP_SERVIDOR/24 dev $INTERFAZ_DHCP
 ip link set $INTERFAZ_DHCP up


 # ARCHIVO DHCP

 tee /etc/dhcpd.conf >/dev/null <<EOF
default-lease-time $LEASE_DEFAULT;
max-lease-time $LEASE_MAX;
authoritative;

subnet $red netmask $mascara {
 range $IP_RANGO_INICIAL $IP_FINAL;
 option routers $IP_SERVIDOR;
 $DNS_CONFIG
}
EOF

 echo "DHCPD_INTERFACE=$INTERFAZ_DHCP" > /etc/sysconfig/dhcpd

 echo "Configuracion completada"
}


# GUARDAR Y REINICIAR

guardar() {

 echo "Validando configuracion..."

 if dhcpd -t &>/dev/null; then

  systemctl enable dhcpd
  systemctl restart dhcpd

  echo "DHCP activo en $INTERFAZ_DHCP"

 else
  echo "Error en configuracion"
 fi
}

# MONITOREO

monitoreo_rango() {

 echo "Estado DHCP:"
 systemctl is-active dhcpd && echo "Activo" || echo "Inactivo"

 echo ""
 echo "Clientes:"
 grep lease /var/lib/dhcpd/dhcpd.leases 2>/dev/null
}


# RESET DHCP

reset_dhcp_rango() {

 systemctl stop dhcpd
 systemctl disable dhcpd

 rm -f /etc/dhcpd.conf
 rm -f /var/lib/dhcpd/dhcpd.leases

 urpmi --auto dhcp-server

 echo "Reset DHCP completado"
}


# VERIFICAR INTERFAZ DHCP

verificar_interfaz_dhcp() {

 echo "Interfaces disponibles:"
 ip -o link show | awk -F': ' '{print $2}'

 echo ""
 echo "DHCP configurado en:"
 cat /etc/sysconfig/dhcpd
}
