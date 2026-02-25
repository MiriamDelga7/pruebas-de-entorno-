CONF_PRINCIPAL="/etc/named.conf"
DIRECTORIO_ZONAS="/var/named"

# validar direccion ip
comprobar_ip() {

    local ip=$1

    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"

    for octeto in $o1 $o2 $o3 $o4
    do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    if [[ "$ip" == "0.0.0.0" ]]; then return 1; fi
    if ((o4 == 255)); then return 1; fi
    if ((o1 == 0 || o1 == 127)); then return 1; fi

    return 0
}

# instalar bind (Mageia usa dnf y servicio named)
activar_dns() {

    if rpm -q bind &>/dev/null; then
        echo "DNS ya esta instalado"
    else
        echo "Instalando bind..."
        sudo dnf install -y bind bind-utils
        sudo systemctl enable named
        sudo systemctl start named
        echo "Instalacion completada"
    fi
}

# verificar estado
ver_estado() {

    if ! rpm -q bind &>/dev/null; then
        echo "DNS instalado"
    return
    fi

   if  systemctl is-active --quiet named; then
 echo "DNS activo y corriendo"
else
 echo "DNS instalado pero detenido"
fi
}

# crear zona
crear_zona() {

    dominio=$1
    ip=$2

    if [[ -z $dominio || -z $ip ]]; then
        echo "Uso: ./mirisdns.sh crear dominio.com IP"
        return
    fi

    comprobar_ip $ip
    if [[ $? -ne 0 ]]; then
        echo "IP invalida"
        return
    fi

    if grep -q "zone \"$dominio\"" $CONF_PRINCIPAL; then
        echo "El dominio ya existe"
        return
    fi

    echo "zone \"$dominio\" IN {
    type master;
    file \"$DIRECTORIO_ZONAS/db.$dominio\";
};" | sudo tee -a $CONF_PRINCIPAL > /dev/null

    sudo bash -c "cat > $DIRECTORIO_ZONAS/db.$dominio" <<EOF
\$TTL 604800
@   IN  SOA ns.$dominio. admin.$dominio. (
        2
        604800
        86400
        2419200
        604800 )

@   IN  NS  ns.$dominio.
ns  IN  A   $ip
@   IN  A   $ip
www IN  A   $ip
EOF

    sudo chown named:named $DIRECTORIO_ZONAS/db.$dominio
    sudo chmod 640 $DIRECTORIO_ZONAS/db.$dominio

    sudo systemctl restart named
    echo "Zona creada correctamente"
}

# mostrar zonas
mostrar_zonas() {

    echo "Zonas configuradas:"

    grep '^zone "' $CONF_PRINCIPAL | \
    awk -F\" '{print $2}'
}

# eliminar zona
borrar_zona() {

    dominio=$1

    if [[ -z $dominio ]]; then
        echo "Uso: ./dnsM.sh borrar dominio.com"
        return
    fi

    sudo sed -i "/zone \"$dominio\"/,/};/d" $CONF_PRINCIPAL
    sudo rm -f $DIRECTORIO_ZONAS/db.$dominio

    sudo systemctl restart named
    echo "Zona eliminada"
}

# quitar bind
remover_dns() {

    sudo systemctl stop named
    sudo dnf remove -y bind bind-utils
    echo "DNS removido del sistema"
}
