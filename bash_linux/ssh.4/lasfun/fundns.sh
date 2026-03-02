#!/bin/bash

LOCALCONF="/etc/named.conf"
ZONADIR="/var/named"

checar_ip() {

 ip=$1

 [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 1

 IFS='.' read -r a b c d <<< "$ip"

 for n in $a $b $c $d; do
  (( n<0 || n>255 )) && return 1
 done

 [[ "$ip" == "0.0.0.0" ]] && return 1
 (( d==255 )) && return 1
 (( a==127 || a==0 )) && return 1

 return 0
}

dns_local() {

 if systemctl is-active --quiet named; then
  sudo tee /etc/resolv.conf >/dev/null <<EOF
nameserver 127.0.0.1
EOF
 else
  echo "named inactivo"
 fi
}

instalar() {

 if rpm -q bind &>/dev/null; then
  echo "bind instalado"
 else
  dnf install -y bind bind-utils
  systemctl enable named
  systemctl start named
 fi

 dns_local
}

estado() {

 rpm -q bind &>/dev/null && echo "bind presente" || { echo "bind no instalado"; return; }

 systemctl is-active --quiet named && echo "servicio activo" || echo "servicio detenido"
 systemctl is-enabled --quiet named && echo "inicio habilitado" || echo "inicio deshabilitado"
}

agregar() {

 DOM=$1
 IP=$2
 ZONA="$ZONADIR/db.$DOM"

 [ -z "$DOM" ] || [ -z "$IP" ] && { echo "uso agregar dominio ip"; exit 1; }

 checar_ip "$IP" || { echo "ip invalida"; exit 1; }

 grep -q "zone \"$DOM\"" $LOCALCONF && { echo "existe"; exit 0; }

 cat <<EOF >> $LOCALCONF

zone "$DOM" IN {
 type master;
 file "db.$DOM";
};

EOF

 cat <<EOF > $ZONA
\$TTL 604800
@ IN SOA NS.$DOM. admin.$DOM. (
 1
 604800
 86400
 2419200
 604800 )

@ IN NS ns.$DOM.
ns IN A $IP
@ IN A $IP
WWW IN CNAME @
EOF

 chown named:named $ZONA
 chmod 640 $ZONA

 systemctl restart named
 dns_local

 echo "dominio agregado"
}

listar() {

 for Z in $ZONADIR/db.*; do
  [ -f "$Z" ] || continue
  DOM=$(basename "$Z" | sed 's/^db\.//')
  IP=$(grep -E '^\s*@\s+IN\s+A\s+' "$Z" | awk '{print $4}')
  echo "$DOM -> $IP"
 done
}

eliminar_dominio() {

 DOM=$1
 [ -z "$DOM" ] && { echo "uso eliminar dominio"; exit 1; }

 ZONA="/var/named/db.$DOM"

 sudo sed -i "/zone \"$DOM\"/,/};/d" /etc/named.conf

 [ -f "$ZONA" ] && sudo rm -f "$ZONA"

 if sudo named-checkconf &>/dev/null; then
  sudo systemctl restart named
  echo "eliminado"
 else
  echo "error config"
 fi
}

desinstalar() {
 dnf remove -y bind bind-utils
 echo "dns removido"
}