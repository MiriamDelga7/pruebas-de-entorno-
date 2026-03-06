#!/bin/bash

# ============================================================
# ftpserver.sh - Servidor FTP para Mageia 9
# Uso: ./ftpserver.sh [comprobar|montar|cuentas|reanudar|info|mostrar|menu]
# ============================================================

verde="\e[32m"; rojo="\e[31m"; amarillo="\e[33m"
cyan="\e[36m";  negrita="\e[1m"; nc="\e[0m"

msg_info()    { echo -e "${cyan}[INFO]  $*${nc}"; }
msg_ok()      { echo -e "${verde}[OK]    $*${nc}"; }
msg_error()   { echo -e "${rojo}[ERROR] $*${nc}"; }
msg_warn()    { echo -e "${amarillo}[WARN]  $*${nc}"; }
msg_titulo()  { echo -e "\n${negrita}${amarillo}=== $* ===${nc}\n"; }

readonly RAIZ_FTP="/srv/ftp"
readonly GRP_REPROBADOS="reprobados"
readonly GRP_RECURSADORES="recursadores"
readonly CONF_VSFTPD="/etc/vsftpd/vsftpd.conf"
readonly DIR_USUARIOS="/etc/vsftpd/users"
readonly LISTA_FTP="/etc/vsftpd/ftp_users"
readonly LISTA_NEGRA="/etc/vsftpd/ftpusers"
readonly HOMES_FTP="/home/ftp_users"

if [[ $EUID -ne 0 ]]; then
    msg_error "Este script debe ejecutarse como root"
    exit 1
fi

# ============================================================
# MENU DE AYUDA
# ============================================================
menu() {
    echo ""
    echo -e "${negrita}Uso: ./ftpserver.sh [comando]${nc}"
    echo ""
    echo "  verificar   Verifica si vsftpd esta instalado"
    echo "  instalar    Instala y configura el servidor FTP"
    echo "  usuarios    Gestionar cuentas FTP (crear/mover/borrar)"
    echo "  reiniciar   Reinicia el servicio FTP"
    echo "  estado      Muestra el estado actual del servidor"
    echo "  listar      Lista todas las cuentas FTP registradas"
    echo "  ayuda       Muestra esta ayuda"
    echo ""
}

# ============================================================
# CORRECCION PAM
# ============================================================
aplicar_pam() {
    grep -qx "/sbin/nologin" /etc/shells || {
        echo "/sbin/nologin" >> /etc/shells
        msg_ok "/sbin/nologin agregado a /etc/shells"
    }

    cat > /etc/pam.d/vsftpd << 'EOF'
#%PAM-1.0
auth     required    pam_unix.so     shadow nullok
account  required    pam_unix.so
session  required    pam_unix.so
EOF
    msg_ok "PAM vsftpd configurado"
}

# ============================================================
# LIMPIAR LISTA NEGRA
# ============================================================
limpiar_blacklist() {
    local cuenta="$1"
    [[ -f "$LISTA_NEGRA" ]] && \
        grep -qx "$cuenta" "$LISTA_NEGRA" 2>/dev/null && {
        sed -i "/^${cuenta}$/d" "$LISTA_NEGRA"
        msg_ok "'$cuenta' quitado de ftpusers"
    }
}

# ============================================================
# COMPROBAR INSTALACION
# ============================================================
comprobar() {
    msg_info "Comprobando instalacion de vsftpd..."
    if rpm -q vsftpd &>/dev/null; then
        local ver
        ver=$(rpm -q vsftpd --queryformat '%{VERSION}')
        msg_ok "vsftpd instalado (version: $ver)"
        return 0
    fi
    msg_warn "vsftpd NO esta instalado"
    return 1
}

# ============================================================
# CREAR GRUPOS DEL SISTEMA
# ============================================================
preparar_grupos() {
    msg_info "Verificando grupos..."
    for grp in "$GRP_REPROBADOS" "$GRP_RECURSADORES"; do
        if ! getent group "$grp" &>/dev/null; then
            groupadd "$grp"
            msg_ok "Grupo '$grp' creado"
        else
            msg_info "Grupo '$grp' ya existe"
        fi
    done
}

# ============================================================
# PREPARAR DIRECTORIOS BASE
# ============================================================
preparar_directorios() {
    msg_info "Creando estructura de directorios..."

    local rutas=(
        "$RAIZ_FTP"
        "$RAIZ_FTP/general"
        "$RAIZ_FTP/$GRP_REPROBADOS"
        "$RAIZ_FTP/$GRP_RECURSADORES"
        "$RAIZ_FTP/personal"
        "$HOMES_FTP"
        "$DIR_USUARIOS"
    )

    for ruta in "${rutas[@]}"; do
        [[ -d "$ruta" ]] || { mkdir -p "$ruta" && msg_ok "Creado: $ruta"; }
    done

    chown root:root "$RAIZ_FTP"          && chmod 755 "$RAIZ_FTP"
    chown root:root "$RAIZ_FTP/personal" && chmod 755 "$RAIZ_FTP/personal"
    chown root:root "$HOMES_FTP"         && chmod 755 "$HOMES_FTP"

    chown root:root "$RAIZ_FTP/general"
    chmod 777 "$RAIZ_FTP/general"
    chmod +t  "$RAIZ_FTP/general"

    chown root:"$GRP_REPROBADOS"  "$RAIZ_FTP/$GRP_REPROBADOS"
    chmod 770 "$RAIZ_FTP/$GRP_REPROBADOS"
    chmod +t  "$RAIZ_FTP/$GRP_REPROBADOS"

    chown root:"$GRP_RECURSADORES" "$RAIZ_FTP/$GRP_RECURSADORES"
    chmod 770 "$RAIZ_FTP/$GRP_RECURSADORES"
    chmod +t  "$RAIZ_FTP/$GRP_RECURSADORES"

    msg_ok "Estructura lista"
}

# ============================================================
# ESCRIBIR CONFIGURACION VSFTPD
# ============================================================
escribir_config() {
    msg_info "Configurando vsftpd..."

    [[ -f "$CONF_VSFTPD" ]] && \
        cp "$CONF_VSFTPD" "${CONF_VSFTPD}.bak.$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$DIR_USUARIOS"
    printf "anonymous\nftp\n" > "$LISTA_FTP"

    cat > "$CONF_VSFTPD" << EOF
# vsftpd.conf - Mageia 9
# Generado por ftpserver.sh

listen=YES
listen_ipv6=NO

local_enable=YES
write_enable=YES
local_umask=022

anonymous_enable=YES
anon_root=$RAIZ_FTP/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=$HOMES_FTP/\$USER
user_config_dir=$DIR_USUARIOS

hide_ids=YES
use_localtime=YES

xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
xferlog_std_format=YES

connect_from_port_20=YES
idle_session_timeout=600
data_connection_timeout=120

dirmessage_enable=YES
ftpd_banner=Bienvenido al servidor FTP

pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

userlist_enable=YES
userlist_file=$LISTA_FTP
userlist_deny=NO

pam_service_name=vsftpd
EOF

    cp "$CONF_VSFTPD" /etc/vsftpd.conf 2>/dev/null

    if ! id ftp &>/dev/null; then
        useradd -r -d "$RAIZ_FTP/general" -s /sbin/nologin ftp
        msg_ok "Usuario 'ftp' creado"
    fi
    limpiar_blacklist "ftp"

    msg_ok "vsftpd configurado"
}

# ============================================================
# ABRIR PUERTOS EN FIREWALL
# ============================================================
abrir_puertos() {
    msg_info "Configurando firewall..."
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=21/tcp          &>/dev/null
        firewall-cmd --permanent --add-port=40000-40100/tcp &>/dev/null
        firewall-cmd --permanent --add-service=ftp          &>/dev/null
        firewall-cmd --reload                               &>/dev/null
        msg_ok "Firewall: puertos 21 y 40000-40100 abiertos"
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport 21 -j ACCEPT
        iptables -I INPUT -p tcp --dport 40000:40100 -j ACCEPT
        msg_ok "iptables: puertos abiertos"
    else
        msg_warn "Sin firewall detectado - verifica el puerto 21 manualmente"
    fi
}

# ============================================================
# MONTAR JAULA CON BIND MOUNTS
# ============================================================
montar_jaula() {
    local cuenta="$1"
    local grp="$2"
    local jaula="$HOMES_FTP/$cuenta"

    msg_info "Montando jaula para '$cuenta'..."

    mkdir -p "$jaula"
    chown root:root "$jaula"
    chmod 755 "$jaula"

    mkdir -p "$jaula/general"
    mkdir -p "$jaula/$grp"
    mkdir -p "$jaula/$cuenta"

    chown root:root "$jaula/general"  && chmod 755 "$jaula/general"
    chown root:root "$jaula/$grp"     && chmod 755 "$jaula/$grp"
    chown "$cuenta":"$grp" "$jaula/$cuenta" && chmod 700 "$jaula/$cuenta"

    mountpoint -q "$jaula/general" 2>/dev/null || {
        mount --bind "$RAIZ_FTP/general" "$jaula/general"
        msg_ok "Bind mount: general"
    }

    mountpoint -q "$jaula/$grp" 2>/dev/null || {
        mount --bind "$RAIZ_FTP/$grp" "$jaula/$grp"
        msg_ok "Bind mount: $grp"
    }

    mountpoint -q "$jaula/$cuenta" 2>/dev/null || {
        mount --bind "$RAIZ_FTP/personal/$cuenta" "$jaula/$cuenta"
        msg_ok "Bind mount: $cuenta (personal)"
    }

    local entradas=(
        "$RAIZ_FTP/general $jaula/general none bind 0 0"
        "$RAIZ_FTP/$grp $jaula/$grp none bind 0 0"
        "$RAIZ_FTP/personal/$cuenta $jaula/$cuenta none bind 0 0"
    )
    for entrada in "${entradas[@]}"; do
        grep -Fx "$entrada" /etc/fstab &>/dev/null || echo "$entrada" >> /etc/fstab
    done

    echo "local_root=$jaula" > "$DIR_USUARIOS/$cuenta"
    msg_ok "Jaula lista: $jaula"
}

# ============================================================
# DESMONTAR Y ELIMINAR JAULA
# ============================================================
desmontar_jaula() {
    local cuenta="$1"
    local jaula="$HOMES_FTP/$cuenta"

    msg_info "Desmontando jaula de '$cuenta'..."

    for punto in "$jaula/$cuenta" "$jaula/$GRP_REPROBADOS" \
                 "$jaula/$GRP_RECURSADORES" "$jaula/general"; do
        mountpoint -q "$punto" 2>/dev/null && {
            umount "$punto" && msg_ok "Desmontado: $punto"
        }
    done

    sed -i "\| $jaula/|d" /etc/fstab 2>/dev/null
    rm -f "$DIR_USUARIOS/$cuenta"
    rm -rf "$jaula"
    msg_ok "Jaula eliminada"
}

# ============================================================
# VALIDAR NOMBRE DE CUENTA
# ============================================================
validar_nombre() {
    local n="$1"
    [[ -z "$n" ]]                       && msg_error "Nombre vacio"                    && return 1
    [[ ${#n} -lt 3 || ${#n} -gt 20 ]]  && msg_error "Entre 3 y 20 caracteres"         && return 1
    [[ ! "$n" =~ ^[a-z][a-z0-9_-]*$ ]] && msg_error "Solo minusculas, numeros, - y _" && return 1
    id "$n" &>/dev/null                 && msg_error "Cuenta '$n' ya existe"           && return 1
    return 0
}

# ============================================================
# VALIDAR CLAVE
# ============================================================
validar_clave() {
    local c="$1"
    [[ ${#c} -lt 8 ]]            && msg_error "Minimo 8 caracteres"         && return 1
    [[ ! "$c" =~ [A-Z] ]]        && msg_error "Necesita una mayuscula"      && return 1
    [[ ! "$c" =~ [0-9] ]]        && msg_error "Necesita un numero"          && return 1
    [[ ! "$c" =~ [^a-zA-Z0-9] ]] && msg_error "Necesita un simbolo (@#$%)" && return 1
    return 0
}

# ============================================================
# REGISTRAR CUENTA FTP
# ============================================================
registrar_cuenta() {
    local cuenta="$1"
    local clave="$2"
    local grp="$3"

    useradd -M -s /sbin/nologin \
        -d "$HOMES_FTP/$cuenta" \
        -g "$grp" \
        -c "Usuario FTP - $grp" \
        "$cuenta" || {
        msg_error "Error al crear '$cuenta'"
        return 1
    }
    msg_ok "Cuenta del sistema creada"

    echo "$cuenta:$clave" | chpasswd || {
        msg_error "Error al establecer clave"
        userdel "$cuenta" 2>/dev/null
        return 1
    }
    msg_ok "Clave establecida"

    limpiar_blacklist "$cuenta"
    grep -qx "$cuenta" "$LISTA_FTP" 2>/dev/null || echo "$cuenta" >> "$LISTA_FTP"

    local personal="$RAIZ_FTP/personal/$cuenta"
    [[ -d "$personal" ]] || {
        mkdir -p "$personal"
        chown "$cuenta":"$grp" "$personal"
        chmod 700 "$personal"
        msg_ok "Carpeta personal: $personal"
    }

    montar_jaula "$cuenta" "$grp"

    echo ""
    msg_ok "════════════════════════════════════════"
    msg_ok "  Cuenta '$cuenta' creada"
    msg_ok "════════════════════════════════════════"
    msg_info "  Grupo    : $grp"
    msg_info "  Al conectar ve:"
    msg_info "    /general/   (compartida)"
    msg_info "    /$grp/      (su grupo)"
    msg_info "    /$cuenta/   (personal)"
    msg_ok "════════════════════════════════════════"
    return 0
}

# ============================================================
# MOVER CUENTA A OTRO GRUPO
# ============================================================
mover_grupo() {
    local cuenta="$1"

    id "$cuenta" &>/dev/null || {
        msg_error "Cuenta '$cuenta' no existe"
        return 1
    }

    local grp_actual
    grp_actual=$(id -gn "$cuenta")

    echo ""
    msg_info "Cuenta      : $cuenta"
    msg_info "Grupo actual: $grp_actual"
    echo ""
    echo "1) $GRP_REPROBADOS"
    echo "2) $GRP_RECURSADORES"
    echo ""
    read -rp "Nuevo grupo: " op

    local nuevo_grp
    case "$op" in
        1) nuevo_grp="$GRP_REPROBADOS"   ;;
        2) nuevo_grp="$GRP_RECURSADORES" ;;
        *) msg_warn "Opcion invalida" && return 1 ;;
    esac

    [[ "$grp_actual" == "$nuevo_grp" ]] && {
        msg_warn "Ya pertenece a '$nuevo_grp'"
        return 0
    }

    desmontar_jaula "$cuenta"
    usermod -g "$nuevo_grp" "$cuenta" && msg_ok "Grupo actualizado"

    local personal="$RAIZ_FTP/personal/$cuenta"
    [[ -d "$personal" ]] || {
        mkdir -p "$personal"
        chown "$cuenta":"$nuevo_grp" "$personal"
        chmod 700 "$personal"
    }

    montar_jaula "$cuenta" "$nuevo_grp"
    systemctl restart vsftpd
    msg_ok "Cuenta '$cuenta' -> '$nuevo_grp' - reconecta FileZilla"
}

# ============================================================
# MOSTRAR LISTADO DE CUENTAS
# ============================================================
mostrar() {
    msg_titulo "Cuentas FTP"

    if [[ ! -s "$LISTA_FTP" ]]; then
        msg_info "No hay cuentas FTP configuradas"
        return 0
    fi

    local n=0
    printf "%-20s %-15s %-8s %-8s\n" "CUENTA" "GRUPO" "JAULA" "MOUNTS"
    printf "%-20s %-15s %-8s %-8s\n" "------" "-----" "-----" "------"

    while IFS= read -r u; do
        [[ -z "$u" || "$u" == "anonymous" || "$u" == "ftp" ]] && continue
        id "$u" &>/dev/null || continue

        local g m=0
        g=$(id -gn "$u")
        local jaula="$HOMES_FTP/$u"
        local st="FALTA"; [[ -d "$jaula" ]] && st="OK"

        mountpoint -q "$jaula/general" 2>/dev/null && m=$((m+1))
        mountpoint -q "$jaula/$g"      2>/dev/null && m=$((m+1))
        mountpoint -q "$jaula/$u"      2>/dev/null && m=$((m+1))

        printf "%-20s %-15s %-8s %-8s\n" "$u" "$g" "$st" "$m/3"
        n=$((n+1))
    done < "$LISTA_FTP"

    [[ $n -eq 0 ]] && msg_warn "No hay cuentas FTP"
    echo ""
}

# ============================================================
# INFORMACION DEL SERVIDOR
# ============================================================
info() {
    msg_titulo "Informacion del Servidor FTP"

    echo -n "vsftpd : "
    systemctl is-active vsftpd

    echo ""
    echo "Puerto 21:"
    ss -tlnp | grep ":21" || echo "  (no escucha)"

    echo ""
    local ip
    ip=$(hostname -I | awk '{print $1}')
    msg_info "IP servidor: $ip"

    echo ""
    msg_info "Checks PAM:"
    grep -qx "/sbin/nologin" /etc/shells \
        && msg_ok "  /sbin/nologin en /etc/shells" \
        || msg_warn "  /sbin/nologin NO en /etc/shells"
    grep -q "pam_unix" /etc/pam.d/vsftpd 2>/dev/null \
        && msg_ok "  PAM vsftpd correcto" \
        || msg_warn "  PAM vsftpd tiene problemas"
    grep -q "pam_service_name" "$CONF_VSFTPD" 2>/dev/null \
        && msg_ok "  pam_service_name configurado" \
        || msg_warn "  pam_service_name FALTA en vsftpd.conf"

    echo ""
    mostrar
}

# ============================================================
# REANUDAR SERVICIO
# ============================================================
reanudar() {
    msg_info "Reiniciando vsftpd..."
    systemctl restart vsftpd
    sleep 1
    systemctl is-active --quiet vsftpd \
        && msg_ok "vsftpd reiniciado correctamente" \
        || msg_error "Fallo al reiniciar vsftpd"
}

# ============================================================
# MONTAR SERVIDOR COMPLETO
# ============================================================
montar() {
    msg_titulo "Instalacion del Servidor FTP - Mageia 9"

    if comprobar 2>/dev/null; then
        echo ""
        read -rp "vsftpd ya instalado. Reconfigurar? (s/n): " r
        [[ "$r" != "s" ]] && msg_info "Cancelado" && return
        systemctl stop vsftpd 2>/dev/null
    else
        msg_info "Instalando vsftpd con urpmi..."
        urpmi --auto vsftpd
        rpm -q vsftpd &>/dev/null || {
            msg_error "Fallo la instalacion de vsftpd"
            exit 1
        }
        msg_ok "vsftpd instalado"
    fi

    echo ""
    aplicar_pam
    echo ""
    preparar_grupos
    echo ""
    preparar_directorios
    echo ""
    escribir_config
    echo ""
    abrir_puertos
    echo ""

    systemctl enable vsftpd &>/dev/null
    systemctl restart vsftpd

    systemctl is-active --quiet vsftpd || {
        msg_error "vsftpd no pudo iniciar"
        msg_error "Revisa: journalctl -xeu vsftpd.service"
        return 1
    }

    local ip
    ip=$(hostname -I | awk '{print $1}')

    echo ""
    msg_ok "════════════════════════════════════════"
    msg_ok "  Servidor FTP listo"
    msg_ok "════════════════════════════════════════"
    msg_info "  IP     : ftp://$ip"
    msg_info "  Puerto : 21"
    msg_info "  Anonimo  -> /general (solo lectura)"
    msg_info "  Cuentas  -> ./ftpserver.sh cuentas"
    msg_ok "════════════════════════════════════════"
}

# ============================================================
# ADMINISTRAR CUENTAS
# ============================================================
cuentas() {
    msg_titulo "Administracion de Cuentas FTP"

    comprobar &>/dev/null || {
        msg_error "vsftpd no instalado. Ejecuta: ./ftpserver.sh montar"
        return 1
    }

    echo "1) Crear cuenta(s)"
    echo "2) Mover a otro grupo"
    echo "3) Borrar cuenta"
    echo ""
    read -rp "Opcion: " op

    case "$op" in
        1)
            read -rp "Cuantas cuentas?: " num
            [[ ! "$num" =~ ^[0-9]+$ || "$num" -lt 1 ]] && {
                msg_error "Numero invalido"
                return 1
            }

            for ((i=1; i<=num; i++)); do
                msg_titulo "Cuenta $i de $num"

                while true; do
                    read -rp "Nombre de cuenta  : " cuenta
                    validar_nombre "$cuenta" && break
                done

                while true; do
                    read -rsp "Clave             : " clave; echo ""
                    validar_clave "$clave" || continue
                    read -rsp "Confirmar         : " clave2; echo ""
                    [[ "$clave" == "$clave2" ]] && break
                    msg_error "Las claves no coinciden"
                done

                echo ""
                echo "  1) $GRP_REPROBADOS"
                echo "  2) $GRP_RECURSADORES"
                read -rp "Grupo: " g
                [[ "$g" == "1" ]] && grp="$GRP_REPROBADOS" || grp="$GRP_RECURSADORES"

                registrar_cuenta "$cuenta" "$clave" "$grp"
            done

            systemctl restart vsftpd && msg_ok "Servicio reiniciado"
            ;;
        2)
            mostrar
            read -rp "Cuenta a mover de grupo: " u
            mover_grupo "$u"
            ;;
        3)
            mostrar
            read -rp "Cuenta a eliminar: " u
            id "$u" &>/dev/null || {
                msg_error "No existe '$u'"
                return 1
            }
            read -rp "Confirma borrar '$u'? (s/n): " c
            if [[ "$c" == "s" ]]; then
                desmontar_jaula "$u"
                rm -rf "$RAIZ_FTP/personal/$u"
                sed -i "/^${u}$/d" "$LISTA_FTP"       2>/dev/null
                sed -i "/^${u}$/d" "$LISTA_NEGRA"     2>/dev/null
                rm -f "$DIR_USUARIOS/$u"
                userdel "$u" 2>/dev/null
                msg_ok "Cuenta '$u' eliminada"
                systemctl restart vsftpd && msg_ok "Servicio reiniciado"
            else
                msg_info "Cancelado"
            fi
            ;;
        *) msg_warn "Opcion invalida" ;;
    esac
}

# ============================================================
# MAIN
# ============================================================
case "${1:-}" in
    verificar)  comprobar          ;;
    instalar)   montar             ;;
    usuarios)   cuentas            ;;
    reiniciar)  reanudar           ;;
    estado)     info               ;;
    listar)     mostrar            ;;
    ayuda)      menu               ;;
    *)          menu               ;;
esac
