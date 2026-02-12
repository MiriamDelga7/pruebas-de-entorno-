#!/bin/bash

#validaciones de la red

validar_ipv4() {

 [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

 IFS='.' read -r a b c d <<< "$1"

 for bloque in $a $b $c $d; do
  [[ $bloque -ge 0 && $bloque -le 255 ]] || return 1
 done

 [[ "$1" == "0.0.0.0" ]] && return 1
 [[ $d -eq 0 || $d -eq 255 ]] && return 1

 return 0
}

ip_a_decimal() {
 IFS='.' read -r a b c d <<< "$1"
 echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

rango_correcto() {
 [[ $(ip_a_decimal "$2") -ge $(ip_a_decimal "$1") ]]
}

sumar_ip() {

 numero=$(ip_a_decimal "$1")
 nuevo=$((numero + 1))

 o1=$(( (nuevo >> 24) & 255 ))
 o2=$(( (nuevo >> 16) & 255 ))
 o3=$(( (nuevo >> 8) & 255 ))
 o4=$(( nuevo & 255 ))

 echo "$o1.$o2.$o3.$o4"
}

misma_red() {

 IFS='.' read -r a1 a2 a3 _ <<< "$1"
 IFS='.' read -r b1 b2 b3 _ <<< "$2"

 [[ $a1 -eq $b1 && $a2 -eq $b2 && $a3 -eq $b3 ]]
}

calcular_mascara() {

 IFS='.' read -r primero _ <<< "$1"

 if (( primero <= 126 )); then
  echo "255.0.0.0"
 elif (( primero <= 191 )); then
  echo "255.255.0.0"
 else
  echo "255.255.255.0"
 fi
}


# FUNCIONES PRINCIPALES

revisar_dhcp() {

 if rpm -q dhcp-server &>/dev/null; then
  echo "Servidor DHCP instalado"
 else
  echo "Servidor DHCP no instalado"
 fi
}

instalar_dhcp_srv() {

 if rpm -q dhcp-server &>/dev/null; then
  read -p "Deseas reinstalar el servicio? (s/n): " resp
  if [[ $resp =~ ^[sS]$ ]]; then
   sudo urpmi --replacepkgs --auto dhcp-server &>/dev/null
   echo "Reinstalacion completada"
  else
   echo "Operacion cancelada"
  fi
 else
  sudo urpmi --auto dhcp-server &>/dev/null
  echo "Instalacion completada"
 fi
}

configurar_interactivo() {

 echo "CONFIGURACION DEL SERVIDOR DHCP"

 while true; do
  read -p "IP Incial servidor: " IP_SERVIDOR
  validar_ipv4 "$IP_SERVIDOR" && break
  echo "IP invalida"
 done

 while true; do
  read -p "IP final servidor: " IP_FINAL
  validar_ipv4 "$IP_FINAL" && break
  echo "IP invalida"
 done

 misma_red "$IP_SERVIDOR" "$IP_FINAL" || { echo "No pertenecen a la misma red"; exit 1; }
 rango_correcto "$IP_SERVIDOR" "$IP_FINAL" || { echo "Rango incorrecto"; exit 1; }

 IP_INICIO_POOL=$(sumar_ip "$IP_SERVIDOR")

 rango_correcto "$IP_INICIO_POOL" "$IP_FINAL" || { echo "Conflicto con IP del servidor"; exit 1; }

 GATEWAY="$IP_SERVIDOR"
 DNS="1.1.1.1"
 LEASE="300"

 MASCARA=$(calcular_mascara "$IP_SERVIDOR")
 RED=${IP_SERVIDOR%.*}.0

 sudo ip addr flush dev enp0s8
 sudo ip addr add $IP_SERVIDOR/24 dev enp0s8
 sudo ip link set enp0s8 up

 sudo tee /etc/dhcpd.conf >/dev/null <<EOF
default-lease-time $LEASE;
max-lease-time $LEASE;
authoritative;

subnet $RED netmask $MASCARA {
 range $IP_INICIO_POOL $IP_FINAL;
 option routers $GATEWAY;
 option domain-name-servers $DNS;
}
EOF

 echo "Configuracion creada"
 echo "IP inicial del servidor: $IP_SERVIDOR"
 echo "Rango DHCP: $IP_INICIO_POOL hasta $IP_FINAL"
}

aplicar_cambios() {

 if sudo dhcpd -t &>/dev/null; then
  sudo systemctl restart dhcpd
  sudo systemctl enable dhcpd
  echo "Configuracion aplicada"
 else
  echo "Error. No reinicio"
 fi
}

ver_clientes() {

 echo "Estado del servicio:"
 systemctl is-active dhcpd

 echo ""
 echo "Registro de clientes:"
 grep "lease " /var/lib/dhcpd/dhcpd.leases 2>/dev/null
}

reiniciar_pool() {

 sudo systemctl stop dhcpd
 sudo rm -f /var/lib/dhcpd/dhcpd.leases
 sudo touch /var/lib/dhcpd/dhcpd.leases
 sudo chown dhcpd:dhcpd /var/lib/dhcpd/dhcpd.leases
 sudo systemctl start dhcpd

 echo "Serviodr reiniciado y limpio de clientes"
}

case "$1" in
 revisar)
  revisar_dhcp
  ;;
 instalar)
  instalar_dhcp_srv
  ;;
 configurar)
  configurar_interactivo
  ;;
 aplicar)
  aplicar_cambios
  ;;
 estado)
  ver_clientes
  ;;
 limpiar)
  reiniciar_pool
  ;;
 *)
  echo "Parametros que puedes utilizar:"
  echo " ./server.sh revisar"
  echo " ./server.sh instalar"
  echo " ./server.sh configurar"
  echo " ./server.sh aplicar"
  echo " ./server.sh estado"
  echo " ./server.sh limpiar"
  ;;
esac
