#!/bin/bash

checar_ip() {
 [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
 IFS='.' read -r a b c d <<< "$1"

 for n in $a $b $c $d; do
  [[ $n -ge 0 && $n -le 255 ]] || return 1
 done

 [[ "$1" == "0.0.0.0" ]] && return 1
 [[ $a -eq 127 ]] && return 1
 [[ $a -eq 0 ]] && return 1
 return 0
}

ipnum2() {
 IFS='.' read -r a b c d <<< "$1"
 echo $(( (a<<24)+(b<<16)+(c<<8)+d ))
}

rango_ok() {
 [[ $(ipnum2 "$2") -ge $(ipnum2 "$1") ]]
}

sumar_ip() {
 n=$(ipnum2 "$1")
 nuevo=$((n+1))

 a=$(( (nuevo>>24)&255 ))
 b=$(( (nuevo>>16)&255 ))
 c=$(( (nuevo>>8)&255 ))
 d=$(( nuevo&255 ))

 echo "$a.$b.$c.$d"
}

misma_subred() {
 IFS='.' read -r a1 a2 a3 _ <<< "$1"
 IFS='.' read -r b1 b2 b3 _ <<< "$2"
 [[ $a1 -eq $b1 && $a2 -eq $b2 && $a3 -eq $b3 ]]
}

obtener_mask() {
 echo "255.255.255.0"
}

verificar_dhcp() {
 rpm -q dhcp-server &>/dev/null && echo "DHCP instalado" || echo "DHCP no instalado"
}

instalar_dhcp() {

 if rpm -q dhcp-server &>/dev/null; then
  read -p "Reinstalar? (s/n): " op
  if [[ $op == "s" || $op == "S" ]]; then
   sudo urpmi --replacepkgs --auto dhcp-server &>/dev/null
   echo "Reinstalado"
  else
   echo "Cancelado"
  fi
 else
  sudo urpmi --auto dhcp-server &>/dev/null
  echo "Instalado"
 fi
}

configurar_dhcp() {

 while true; do
  read -p "Ip inicial: " IP_INI
  checar_ip "$IP_INI" && break
 done

 while true; do
  read -p "Ip final: " IP_FIN
  checar_ip "$IP_FIN" && break
 done

 misma_subred "$IP_INI" "$IP_FIN" || { echo "Red distinta"; return 1; }
 rango_ok "$IP_INI" "$IP_FIN" || { echo "Rango invalido"; return 1; }

 IP_SERV="$IP_INI"
 IP_RANGO=$(sumar_ip "$IP_INI")

 rango_ok "$IP_RANGO" "$IP_FIN" || { echo "Servidor en rango"; return 1; }

 GATEWAY="$IP_SERV"

 IF_SSH=$(ip route | awk '/default/ {print $5}')
 IF_DHCP=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v "$IF_SSH" | head -n1)

 [ -z "$IF_DHCP" ] && { echo "Sin interfaz"; return 1; }

 read -p "DNS1: " DNS1
 read -p "DNS2: " DNS2

 [ -z "$DNS1" ] && DNS1="$IP_SERV"

 if [ -z "$DNS2" ]; then
  DNS_CONF="option domain-name-servers $DNS1;"
 else
  DNS_CONF="option domain-name-servers $DNS1, $DNS2;"
 fi

 read -p "Lease default: " L1
 read -p "Lease max: " L2

 [ -z "$L1" ] && L1=300
 [ -z "$L2" ] && L2=300

 mask=$(obtener_mask "$IP_SERV")
 red=${IP_SERV%.*}.0

 sudo ip addr flush dev $IF_DHCP
 sudo ip addr add $IP_SERV/24 dev $IF_DHCP
 sudo ip link set $IF_DHCP up

 sudo tee /etc/dhcpd.conf >/dev/null <<EOF
default-lease-time $L1;
max-lease-time $L2;
authoritative;

subnet $red netmask $mask {
 range $IP_RANGO $IP_FIN;
 option routers $GATEWAY;
 $DNS_CONF
}
EOF

 echo "DHCPD_INTERFACE=$IF_DHCP" | sudo tee /etc/sysconfig/dhcpd >/dev/null

 sudo chattr -i /etc/resolv.conf 2>/dev/null

 sudo tee /etc/resolv.conf >/dev/null <<EOF
nameserver $IP_SERV
nameserver 8.8.8.8
EOF
}

guardaryreiniciar() {

 if sudo dhcpd -t &>/dev/null; then
  sudo systemctl enable dhcpd &>/dev/null
  sudo systemctl restart dhcpd &>/dev/null && echo "Reiniciado" || echo "Error reinicio"
 else
  echo "Error config"
 fi
}

monitoreo() {

 systemctl is-active --quiet dhcpd && echo "Activo" || echo "Inactivo"
 grep "lease " /var/lib/dhcpd/dhcpd.leases 2>/dev/null
}

reset_dhcp() {

 sudo systemctl stop dhcpd 2>/dev/null
 sudo systemctl disable dhcpd 2>/dev/null
 sudo rm -f /etc/dhcpd.conf
 sudo rm -f /var/lib/dhcpd/dhcpd.leases
 sudo dnf remove -y dhcp-server >/dev/null 2>&1
 echo "Reset completo"
}