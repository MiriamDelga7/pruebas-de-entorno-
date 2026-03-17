#!/bin/bash
# http2fun.sh - Funciones para instalacion y gestion de servidores HTTP
# Practica - Mageia Linux

# ─── Colores ─────────────────────────────────────────────────────────────────
ROSA="\033[1;35m"
RESET="\033[0m"

# ─── Utilidades de impresion ──────────────────────────────────────────────────
print_info()       { echo -e "${ROSA}[INFO]${RESET} $1"; }
print_completado() { echo -e "${ROSA}[OK]${RESET} $1"; }
print_error()      { echo -e "${ROSA}[ERROR]${RESET} $1"; }
print_titulo()     { echo ""; echo -e "${ROSA}>> $1${RESET}"; }

# ─── Constantes ───────────────────────────────────────────────────────────────
readonly PUERTOS_RESERVADOS=(22 21 23 25 53 443 3306 5432 6379 27017)
readonly APACHE_WEBROOT="/var/www/html/apache"
readonly NGINX_WEBROOT="/var/www/html/nginx"
readonly TOMCAT_WEBROOT="/opt/tomcat/webapps/ROOT"

# ─── Variables globales ───────────────────────────────────────────────────────
VERSION_ELEGIDA=""
PUERTO_ELEGIDO=""
PUERTO_INTERNO=""
PKG_MANAGER=""
PKG_INSTALL=""
INTERFAZ_RED=""
IP_SERVIDOR=""
AUTHBIND_CMD=""

# ─── Deteccion de entorno ─────────────────────────────────────────────────────
detectar_entorno() {
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"; PKG_INSTALL="dnf install -y"
    elif command -v urpmi &>/dev/null; then
        PKG_MANAGER="urpmi"; PKG_INSTALL="urpmi --auto"
    else
        print_error "No se detecto dnf ni urpmi."; exit 1
    fi
    print_completado "Gestor de paquetes: $PKG_MANAGER"
    INTERFAZ_RED="enp0s9"
    IP_SERVIDOR=$(ip addr show "$INTERFAZ_RED" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    [[ -z "$IP_SERVIDOR" ]] && IP_SERVIDOR=$(hostname -I 2>/dev/null | awk '{print $1}')
    print_completado "Interfaz: $INTERFAZ_RED (${IP_SERVIDOR:-no detectada})"
}

# ─── Validacion de root ───────────────────────────────────────────────────────
validar_root() {
    [[ $EUID -ne 0 ]] && { echo "[ERROR] Ejecuta como root."; exit 1; }
}

# ─── Deteccion de servidor en puerto ─────────────────────────────────────────
http_propio_en_puerto() {
    local puerto="$1"
    if [[ -f /opt/apache/bin/apachectl ]] && systemctl is-active --quiet apache-web 2>/dev/null; then
        local p; p=$(ss -tlnp 2>/dev/null | grep httpd | grep -oP ':\K[0-9]+' | head -1)
        [[ "$p" == "$puerto" ]] && echo "Apache:apache-web" && return
    fi
    if [[ -f /opt/nginx/sbin/nginx ]] && systemctl is-active --quiet nginx-web 2>/dev/null; then
        local p; p=$(ss -tlnp 2>/dev/null | grep nginx | grep -oP ':\K[0-9]+' | head -1)
        [[ "$p" == "$puerto" ]] && echo "Nginx:nginx-web" && return
    fi
    if [[ -f /opt/tomcat/bin/startup.sh ]] && systemctl is-active --quiet tomcat 2>/dev/null; then
        local nat_puerto
        nat_puerto=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep "redir ports" | grep "dpt:${puerto}" | head -1 | grep -oP 'dpt:\K[0-9]+')
        [[ -n "$nat_puerto" ]] && echo "Apache Tomcat:tomcat" && return
        local p; p=$(ss -tlnp 2>/dev/null | grep java | grep -oP '[:\*]\K[0-9]+' | grep -v "^8005$" | head -1)
        [[ "$p" == "$puerto" ]] && echo "Apache Tomcat:tomcat" && return
    fi
    echo ""
}

servicio_en_puerto() {
    local puerto="$1"
    local proc
    proc=$(ss -tlnp 2>/dev/null | grep ":${puerto} " | grep -oP 'users:\(\("\K[^"]+' | head -1)
    case "$proc" in
        *httpd*|*apache*) echo "apache-web" ;;
        *nginx*)          echo "nginx-web"  ;;
        *java*)           echo "tomcat"     ;;
        *)                echo "otro"       ;;
    esac
}

validar_puerto() {
    local puerto="$1"; shift
    local reservados=("$@")
    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        print_error "El puerto debe ser un numero."; return 1
    fi
    if (( puerto < 1 || puerto > 65535 )); then
        print_error "Puerto fuera de rango (1-65535)."; return 1
    fi
    for r in "${reservados[@]}"; do
        (( puerto == r )) && { print_error "Puerto $puerto reservado para otro servicio critico."; return 1; }
    done
    return 0
}

verificar_y_liberar_puerto() {
    local puerto="$1"
    if ! ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
        if ! iptables -t nat -L PREROUTING -n 2>/dev/null | grep -q "dpt:${puerto}"; then
            return 0
        fi
    fi
    local http_info
    http_info=$(http_propio_en_puerto "$puerto")
    if [[ -n "$http_info" ]]; then
        local nombre svc
        nombre="${http_info%%:*}"; svc="${http_info##*:}"
        print_error "Puerto $puerto ya esta en uso por: $nombre"
        echo -n "Deseas desconectar $nombre y asignarlo al nuevo servidor? [s/N]: "
        read -r resp; resp="${resp,,}"
        if [[ "$resp" == "s" || "$resp" == "si" ]]; then
            systemctl stop "$svc" 2>/dev/null
            pkill -f java 2>/dev/null
            iptables -t nat -D PREROUTING -p tcp --dport "$puerto" -j REDIRECT --to-port "$((puerto+10000))" 2>/dev/null
            iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport "$puerto" -j REDIRECT --to-port "$((puerto+10000))" 2>/dev/null
            sleep 2
            print_completado "$nombre detenido. Puerto $puerto liberado."
            return 0
        else
            print_info "Elige un puerto diferente."; return 1
        fi
    fi
    if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
        local svc; svc=$(servicio_en_puerto "$puerto")
        print_error "Puerto $puerto ocupado por: $svc"
        echo -n "Deseas detener '$svc' y liberar el puerto? [s/N]: "
        read -r resp; resp="${resp,,}"
        if [[ "$resp" == "s" || "$resp" == "si" ]]; then
            systemctl stop "$svc" 2>/dev/null; sleep 2
            if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
                print_error "El puerto $puerto sigue ocupado."; return 1
            fi
            print_completado "Puerto $puerto liberado."
        else
            print_info "Elige un puerto diferente."; return 1
        fi
    fi
    return 0
}

# ─── Obtener versiones online ─────────────────────────────────────────────────
obtener_versiones_apache() {
    local base_url="https://downloads.apache.org/httpd/"
    print_info "Consultando versiones de Apache..." >&2
    local versiones
    versiones=$(curl -s --max-time 10 "$base_url" 2>/dev/null \
        | grep -oP 'httpd-\K2\.4\.[0-9]+(?=\.tar\.gz)' | sort -uV)
    if [[ -z "$versiones" ]]; then
        print_info "Sin acceso. Usando versiones de referencia." >&2
        echo "2.4.62"; echo "2.4.63"; echo "2.4.66"; return
    fi
    echo "$versiones"
}

obtener_versiones_nginx() {
    local base_url="https://nginx.org/download/"
    print_info "Consultando versiones de Nginx..." >&2
    local versiones
    versiones=$(curl -s --max-time 10 "$base_url" 2>/dev/null \
        | grep -oP 'nginx-\K1\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | sort -uV | tail -8)
    if [[ -z "$versiones" ]]; then
        print_info "Sin acceso. Usando versiones de referencia." >&2
        echo "1.26.3"; echo "1.27.5"; echo "1.28.0"; echo "1.29.0"; return
    fi
    echo "$versiones"
}

obtener_versiones_tomcat() {
    local base_url="https://dlcdn.apache.org/tomcat/"
    print_info "Consultando versiones de Tomcat..." >&2
    local ramas
    ramas=$(curl -s --max-time 8 "$base_url" 2>/dev/null \
        | grep -oP 'tomcat-\K[0-9]+(?=/)' | sort -uV)
    if [[ -z "$ramas" ]]; then
        print_info "Sin acceso. Usando versiones de referencia." >&2
        echo "9.0.102"; echo "10.1.40"; echo "11.0.7"; return
    fi
    while IFS= read -r rama; do
        local latest
        latest=$(curl -s --max-time 8 "${base_url}tomcat-${rama}/" 2>/dev/null \
            | grep -oP "v\K[0-9]+\.[0-9]+\.[0-9]+" | sort -V | tail -1)
        [[ -n "$latest" ]] && echo "$latest"
    done <<< "$ramas"
}

# ─── Seleccion de version ─────────────────────────────────────────────────────
elegir_version() {
    clear
    local paquete="$1"; shift
    local versiones=("$@")
    if [[ ${#versiones[@]} -eq 0 ]]; then
        print_error "No se encontraron versiones para '$paquete'."; return 1
    fi
    echo -e "${ROSA}"
    echo "======================================"
    echo "   Versiones disponibles: $paquete"
    echo "======================================"
    echo -e "${RESET}"
    local i=1 total=${#versiones[@]}
    for ver in "${versiones[@]}"; do
        local etiqueta=""
        [[ $i -eq 1      ]] && etiqueta="  [LTS / Estable]"
        [[ $i -eq $total ]] && etiqueta="  [Latest / Desarrollo]"
        echo -e "${ROSA}  [$i] $ver$etiqueta${RESET}"
        (( i++ ))
    done
    echo
    while true; do
        read -rp "Elige una version [1-$total]: " sel
        sel="${sel//[^0-9]/}"
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= total )); then
            VERSION_ELEGIDA="${versiones[$((sel-1))]}"
            print_completado "Version seleccionada: $VERSION_ELEGIDA"
            return 0
        fi
        print_error "Seleccion invalida."
    done
}

# ─── Pedir puerto ─────────────────────────────────────────────────────────────
pedir_puerto() {
    while true; do
        read -rp "Puerto HTTP a usar [ej: 80, 8080, 8180]: " PUERTO_ELEGIDO
        PUERTO_ELEGIDO="${PUERTO_ELEGIDO//[^0-9]/}"
        validar_puerto "$PUERTO_ELEGIDO" "${PUERTOS_RESERVADOS[@]}" || continue
        verificar_y_liberar_puerto "$PUERTO_ELEGIDO" && break
    done
    print_completado "Puerto seleccionado: $PUERTO_ELEGIDO"
}

# ─── Crear pagina index sin IP ni puerto (solo nombre del servicio) ───────────
crear_index() {
    local nombre="$1" version="$2" webroot="$3"
    mkdir -p "$webroot"
    cat > "$webroot/index.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>${nombre}</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
      font-family: 'Segoe UI', sans-serif;
      background: #0d0d0d;
      color: #f0f0f0;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      text-align: center;
      padding: 60px 80px;
      border: 2px solid #a259c4;
      border-radius: 16px;
      background: #1a1a1a;
      box-shadow: 0 0 40px #a259c455;
    }
    h1 { font-size: 2.8rem; color: #a259c4; margin-bottom: 12px; }
    .badge {
      display: inline-block;
      background: #a259c4;
      color: #fff;
      padding: 4px 18px;
      border-radius: 20px;
      font-size: 0.95rem;
      margin-bottom: 28px;
    }
    .status { margin-top: 24px; color: #a259c4; font-size: 1.1rem; font-weight: bold; }
    p { color: #aaa; font-size: 1rem; margin-top: 10px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${nombre}</h1>
    <div class="badge">v${version}</div>
    <p class="status">&#x2714; Servidor activo y funcionando</p>
    <p>Sistema: $(uname -n)</p>
  </div>
</body>
</html>
HTMLEOF
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
configurar_firewall() {
    local puerto="$1"
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        print_completado "Firewalld: puerto $puerto abierto."
    elif command -v ufw &>/dev/null; then
        ufw allow "$puerto/tcp" &>/dev/null
        print_completado "UFW: puerto $puerto abierto."
    else
        print_info "Abre el puerto $puerto manualmente si usas otro firewall."
    fi
}

mostrar_url() {
    local puerto="$1"
    local ip="${IP_SERVIDOR:-127.0.0.1}"
    echo ""
    echo -e "  ${ROSA}>>> URL: http://${ip}:${puerto}/ <<<${RESET}"
    echo ""
}

configurar_nat_tomcat() {
    local ext="$1" int="$2"
    iptables -t nat -A PREROUTING -p tcp --dport "$ext" -j REDIRECT --to-port "$int"
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport "$ext" -j REDIRECT --to-port "$int"
    print_completado "NAT configurado: $ext -> $int"
}

# ─── INSTALAR APACHE ──────────────────────────────────────────────────────────
instalar_apache() {
    print_titulo "Instalando Apache $VERSION_ELEGIDA..."
    local url="https://downloads.apache.org/httpd/httpd-${VERSION_ELEGIDA}.tar.gz"
    local tarball="/tmp/httpd-${VERSION_ELEGIDA}.tar.gz"

    $PKG_INSTALL gcc make pcre-devel expat-devel openssl-devel apr-devel apr-util-devel &>/dev/null
    command -v curl &>/dev/null || $PKG_INSTALL curl &>/dev/null

    print_info "Descargando Apache $VERSION_ELEGIDA..."
    curl -L --progress-bar -o "$tarball" "$url" 2>&1
    gzip -t "$tarball" &>/dev/null || { print_error "Descarga invalida."; rm -f "$tarball"; return 1; }
    print_completado "Descarga verificada."

    rm -rf /tmp/httpd-build && mkdir /tmp/httpd-build
    tar xzf "$tarball" -C /tmp/httpd-build --strip-components=1 || { print_error "Fallo extraccion."; return 1; }
    rm -f "$tarball"

    cd /tmp/httpd-build || return 1
    ./configure --prefix=/opt/apache \
        --enable-so --enable-ssl --enable-rewrite \
        --with-mpm=event --enable-modules=most &>/dev/null \
        || { print_error "Fallo configure."; return 1; }
    make -j"$(nproc)" &>/dev/null || { print_error "Fallo compilacion."; return 1; }
    make install &>/dev/null
    print_completado "Apache instalado en /opt/apache"
    cd / && rm -rf /tmp/httpd-build

    # Usuario
    if ! id "apache" &>/dev/null; then
        useradd -r -s /sbin/nologin apache
        print_completado "Usuario apache creado."
    fi

    # Webroot e index (sin IP ni puerto en la pagina)
    mkdir -p "$APACHE_WEBROOT"
    crear_index "Apache HTTP Server" "$VERSION_ELEGIDA" "$APACHE_WEBROOT"
    chown -R apache:apache "$APACHE_WEBROOT"
    chmod -R 755 "$APACHE_WEBROOT"

    # Detectar si MPM es modulo o estatico
    local mpm_line=""
    if [[ -f /opt/apache/modules/mod_mpm_event.so ]]; then
        mpm_line="LoadModule mpm_event_module   modules/mod_mpm_event.so"
    elif [[ -f /opt/apache/modules/mod_mpm_prefork.so ]]; then
        mpm_line="LoadModule mpm_prefork_module  modules/mod_mpm_prefork.so"
    else
        mpm_line="# MPM compilado estatico - no requiere LoadModule"
    fi

    # Escribir httpd.conf limpio y correcto
    cat > /opt/apache/conf/httpd.conf << CONFEOF
ServerRoot "/opt/apache"
Listen ${PUERTO_ELEGIDO}
ServerName ${IP_SERVIDOR:-127.0.0.1}:${PUERTO_ELEGIDO}
ServerAdmin admin@localhost

${mpm_line}
LoadModule authz_core_module  modules/mod_authz_core.so
LoadModule authz_host_module  modules/mod_authz_host.so
LoadModule log_config_module  modules/mod_log_config.so
LoadModule mime_module        modules/mod_mime.so
LoadModule dir_module         modules/mod_dir.so
LoadModule alias_module       modules/mod_alias.so
LoadModule autoindex_module   modules/mod_autoindex.so
LoadModule rewrite_module     modules/mod_rewrite.so
LoadModule unixd_module       modules/mod_unixd.so

User apache
Group apache

DocumentRoot "${APACHE_WEBROOT}"

<Directory />
    AllowOverride None
    Require all denied
</Directory>

<Directory "${APACHE_WEBROOT}">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

DirectoryIndex index.html index.htm
TypesConfig conf/mime.types
ErrorLog  logs/error_log
LogLevel  warn
LogFormat "%h %l %u %t \"%r\" %>s %b" common
CustomLog logs/access_log common
PidFile   logs/httpd.pid
CONFEOF

    chown -R apache:apache /opt/apache/logs
    chmod 750 /opt/apache/logs
    print_completado "httpd.conf configurado."

    # Verificar sintaxis antes de arrancar
    if ! /opt/apache/bin/apachectl -t &>/dev/null; then
        print_error "Error de sintaxis en httpd.conf:"
        /opt/apache/bin/apachectl -t
        return 1
    fi
    print_completado "Sintaxis httpd.conf correcta."

    cat > /etc/systemd/system/apache-web.service << EOF
[Unit]
Description=Apache HTTP Server ${VERSION_ELEGIDA}
After=network.target

[Service]
Type=forking
ExecStart=/opt/apache/bin/apachectl start
ExecStop=/opt/apache/bin/apachectl stop
ExecReload=/opt/apache/bin/apachectl graceful
PIDFile=/opt/apache/logs/httpd.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl stop apache-web 2>/dev/null; sleep 1
    systemctl enable apache-web &>/dev/null
    systemctl start apache-web
    sleep 2
    configurar_firewall "$PUERTO_ELEGIDO"

    if systemctl is-active --quiet apache-web; then
        print_completado "Apache $VERSION_ELEGIDA activo en puerto $PUERTO_ELEGIDO"
        mostrar_url "$PUERTO_ELEGIDO"
    else
        print_error "Apache no arranco."
        print_info  "Revisa: journalctl -u apache-web -n 30 --no-pager"
        print_info  "        cat /opt/apache/logs/error_log"
        return 1
    fi
}

# ─── INSTALAR NGINX ───────────────────────────────────────────────────────────
instalar_nginx() {
    print_titulo "Instalando Nginx $VERSION_ELEGIDA..."
    local url="https://nginx.org/download/nginx-${VERSION_ELEGIDA}.tar.gz"
    local tarball="/tmp/nginx-${VERSION_ELEGIDA}.tar.gz"

    $PKG_INSTALL gcc make pcre-devel zlib-devel openssl-devel &>/dev/null
    command -v curl &>/dev/null || $PKG_INSTALL curl &>/dev/null

    print_info "Descargando Nginx $VERSION_ELEGIDA..."
    curl -L --progress-bar -o "$tarball" "$url" 2>&1
    gzip -t "$tarball" &>/dev/null || { print_error "Descarga invalida."; rm -f "$tarball"; return 1; }
    print_completado "Descarga verificada."

    rm -rf /tmp/nginx-build && mkdir /tmp/nginx-build
    tar xzf "$tarball" -C /tmp/nginx-build --strip-components=1 || { print_error "Fallo extraccion."; return 1; }
    rm -f "$tarball"

    cd /tmp/nginx-build || return 1
    ./configure --prefix=/opt/nginx \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module &>/dev/null \
        || { print_error "Fallo configure."; return 1; }
    make -j"$(nproc)" &>/dev/null || { print_error "Fallo compilacion."; return 1; }
    make install &>/dev/null
    print_completado "Nginx instalado en /opt/nginx"
    cd / && rm -rf /tmp/nginx-build

    if ! id "nginx" &>/dev/null; then
        useradd -r -s /sbin/nologin nginx
        print_completado "Usuario nginx creado."
    fi

    mkdir -p "$NGINX_WEBROOT"
    crear_index "Nginx" "$VERSION_ELEGIDA" "$NGINX_WEBROOT"
    chown -R nginx:nginx "$NGINX_WEBROOT"
    chmod -R 755 "$NGINX_WEBROOT"

    cat > /opt/nginx/conf/nginx.conf << EOF
user nginx;
worker_processes auto;
error_log /opt/nginx/logs/error.log;
pid /opt/nginx/logs/nginx.pid;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    server {
        listen      ${PUERTO_ELEGIDO};
        server_name _;
        root        ${NGINX_WEBROOT};
        index       index.html;
    }
}
EOF

    chown -R nginx:nginx /opt/nginx/logs

    cat > /etc/systemd/system/nginx-web.service << EOF
[Unit]
Description=Nginx HTTP Server ${VERSION_ELEGIDA}
After=network.target

[Service]
Type=forking
ExecStart=/opt/nginx/sbin/nginx
ExecStop=/opt/nginx/sbin/nginx -s stop
ExecReload=/opt/nginx/sbin/nginx -s reload
PIDFile=/opt/nginx/logs/nginx.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl stop nginx-web 2>/dev/null; sleep 1
    systemctl enable nginx-web &>/dev/null
    systemctl start nginx-web
    sleep 2
    configurar_firewall "$PUERTO_ELEGIDO"

    if systemctl is-active --quiet nginx-web; then
        print_completado "Nginx $VERSION_ELEGIDA activo en puerto $PUERTO_ELEGIDO"
        mostrar_url "$PUERTO_ELEGIDO"
    else
        print_error "Nginx no arranco. Revisa: journalctl -u nginx-web -n 20 --no-pager"
        return 1
    fi
}

# ─── INSTALAR TOMCAT ──────────────────────────────────────────────────────────
instalar_tomcat() {
    print_titulo "Instalando Apache Tomcat $VERSION_ELEGIDA..."
    local rama="${VERSION_ELEGIDA%%.*}"
    local url="https://dlcdn.apache.org/tomcat/tomcat-${rama}/v${VERSION_ELEGIDA}/bin/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"
    local tarball="/tmp/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"

    if ! command -v java &>/dev/null; then
        print_info "Java no encontrado. Instalando OpenJDK..."
        $PKG_INSTALL java-21-openjdk java-21-openjdk-headless &>/dev/null || \
        $PKG_INSTALL java-11-openjdk java-11-openjdk-headless &>/dev/null || \
            { print_error "No se pudo instalar Java."; return 1; }
        print_completado "Java instalado."
    else
        print_completado "Java: $(java -version 2>&1 | head -1)"
    fi

    command -v curl &>/dev/null || $PKG_INSTALL curl &>/dev/null

    print_info "Descargando Tomcat $VERSION_ELEGIDA..."
    curl -L --progress-bar -o "$tarball" "$url" 2>&1
    gzip -t "$tarball" &>/dev/null || { print_error "Descarga invalida."; rm -f "$tarball"; return 1; }
    print_completado "Descarga verificada."

    print_info "Extrayendo en /opt/tomcat..."
    rm -rf /opt/tomcat && mkdir -p /opt/tomcat
    tar xzf "$tarball" -C /opt/tomcat --strip-components=1 \
        || { print_error "Fallo la extraccion."; rm -f "$tarball"; return 1; }
    rm -f "$tarball"
    print_completado "Tomcat extraido en /opt/tomcat"

    if (( PUERTO_ELEGIDO < 1024 )); then
        PUERTO_INTERNO=$(( PUERTO_ELEGIDO + 10000 ))
        print_info "Puerto $PUERTO_ELEGIDO < 1024. Tomcat usara internamente el puerto $PUERTO_INTERNO."
    else
        PUERTO_INTERNO=$PUERTO_ELEGIDO
    fi

    cp /opt/tomcat/conf/server.xml /opt/tomcat/conf/server.xml.bak
    sed -i "s/port=\"8080\"/port=\"${PUERTO_INTERNO}\"/" /opt/tomcat/conf/server.xml
    sed -i 's/port="8009"/port="-1"/' /opt/tomcat/conf/server.xml
    print_completado "Puerto interno configurado -> $PUERTO_INTERNO (AJP deshabilitado)."

    if ! id "tomcat" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /opt/tomcat -M tomcat
        print_completado "Usuario tomcat creado."
    fi

    mkdir -p "$TOMCAT_WEBROOT"
    crear_index "Apache Tomcat" "$VERSION_ELEGIDA" "$TOMCAT_WEBROOT"
    chown -R tomcat:tomcat /opt/tomcat
    chmod 750 /opt/tomcat /opt/tomcat/conf
    print_completado "Permisos configurados."

    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")

    cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat ${VERSION_ELEGIDA}
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${java_home}"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl stop tomcat 2>/dev/null
    pkill -f java 2>/dev/null; sleep 2
    systemctl enable tomcat &>/dev/null
    systemctl start tomcat
    print_info "Esperando que Tomcat inicie (15 seg)..."
    sleep 15

    if ! systemctl is-active --quiet tomcat; then
        print_error "Tomcat no arranco."
        print_info  "Revisa: cat /opt/tomcat/logs/catalina.out | tail -20"
        return 1
    fi

    (( PUERTO_ELEGIDO < 1024 )) && configurar_nat_tomcat "$PUERTO_ELEGIDO" "$PUERTO_INTERNO"
    configurar_firewall "$PUERTO_ELEGIDO"
    print_completado "Tomcat $VERSION_ELEGIDA activo en puerto $PUERTO_ELEGIDO"
    mostrar_url "$PUERTO_ELEGIDO"
}

# ─── ESTADO DE SERVIDORES CON URL ─────────────────────────────────────────────
verificar_HTTP() {
    local ip="${IP_SERVIDOR:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
    echo ""
    echo -e "${ROSA}=== Estado de Servidores HTTP ===${RESET}"
    echo ""

    # Apache
    echo -n "  Apache  : "
    if [[ -f /opt/apache/bin/apachectl ]]; then
        local ver; ver=$(/opt/apache/bin/apachectl -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+')
        if systemctl is-active --quiet apache-web 2>/dev/null; then
            local p; p=$(ss -tlnp 2>/dev/null | grep httpd | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${ROSA}Activo${RESET} | Version: ${ver:-?} | Puerto: ${p:-?}"
            echo -e "            URL: ${ROSA}http://${ip}:${p:-?}/${RESET}"
        else
            echo "Detenido | Version: ${ver:-?}"
        fi
    else
        echo "No instalado"
    fi
    echo ""

    # Nginx
    echo -n "  Nginx   : "
    if [[ -f /opt/nginx/sbin/nginx ]]; then
        local ver; ver=$(/opt/nginx/sbin/nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
        if systemctl is-active --quiet nginx-web 2>/dev/null; then
            local p; p=$(ss -tlnp 2>/dev/null | grep nginx | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${ROSA}Activo${RESET} | Version: ${ver:-?} | Puerto: ${p:-?}"
            echo -e "            URL: ${ROSA}http://${ip}:${p:-?}/${RESET}"
        else
            echo "Detenido | Version: ${ver:-?}"
        fi
    else
        echo "No instalado"
    fi
    echo ""

    # Tomcat
    echo -n "  Tomcat  : "
    if [[ -f /opt/tomcat/bin/startup.sh ]]; then
        local ver; ver=$(/opt/tomcat/bin/version.sh 2>/dev/null | grep "Server version" | grep -oP 'Tomcat/\K[0-9.]+')
        if systemctl is-active --quiet tomcat 2>/dev/null; then
            local p_int p_nat p_show
            p_int=$(ss -tlnp 2>/dev/null | grep java | grep -oP '[:\*]\K[0-9]+' | grep -v "^8005$" | head -1)
            p_nat=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep "redir ports ${p_int}" | grep -oP 'dpt:\K[0-9]+' | head -1)
            p_show="${p_nat:-$p_int}"
            echo -e "${ROSA}Activo${RESET} | Version: ${ver:-?} | Puerto: ${p_show:-?}"
            echo -e "            URL: ${ROSA}http://${ip}:${p_show:-?}/${RESET}"
        else
            echo "Detenido | Version: ${ver:-?}"
        fi
    else
        echo "No instalado"
    fi
    echo ""
}

# ─── MENU APACHE ─────────────────────────────────────────────────────────────
apache_menu() {
    local op
    while true; do
        clear
        echo -e "${ROSA}"
        echo "======================================"
        echo "          MENU APACHE"
        echo "======================================"
        echo -e "${RESET}"
        echo -e "${ROSA}1) Instalar Apache${RESET}"
        echo -e "${ROSA}2) Ver estado Apache${RESET}"
        echo -e "${ROSA}3) Iniciar Apache${RESET}"
        echo -e "${ROSA}4) Detener Apache${RESET}"
        echo -e "${ROSA}5) Reiniciar Apache${RESET}"
        echo -e "${ROSA}0) Volver${RESET}"
        echo
        read -rp "Seleccione opcion: " op
        op="${op//[^0-9]/}"
        case "$op" in
            1)
                local versiones=()
                mapfile -t versiones < <(obtener_versiones_apache)
                elegir_version "Apache" "${versiones[@]}" || { read -rp "ENTER..."; continue; }
                pedir_puerto
                instalar_apache
                read -rp "Presione ENTER para continuar"
                ;;
            2)
                echo ""
                if systemctl is-active --quiet apache-web 2>/dev/null; then
                    local p; p=$(ss -tlnp 2>/dev/null | grep httpd | grep -oP ':\K[0-9]+' | head -1)
                    local ip="${IP_SERVIDOR:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
                    echo -e "  Apache: ${ROSA}Activo${RESET}"
                    echo "  $(systemctl status apache-web | grep 'Active:')"
                    echo -e "  URL: ${ROSA}http://${ip}:${p:-?}/${RESET}"
                else
                    echo "  Apache: Detenido o no instalado"
                fi
                echo ""
                read -rp "Presione ENTER para continuar"
                ;;
            3) systemctl start apache-web 2>/dev/null \
                   && print_completado "Apache iniciado." \
                   || print_error "No se pudo iniciar Apache."
               read -rp "Presione ENTER para continuar" ;;
            4) systemctl stop apache-web 2>/dev/null \
                   && print_completado "Apache detenido." \
                   || print_error "No se pudo detener Apache."
               read -rp "Presione ENTER para continuar" ;;
            5) systemctl restart apache-web 2>/dev/null \
                   && print_completado "Apache reiniciado." \
                   || print_error "No se pudo reiniciar Apache."
               read -rp "Presione ENTER para continuar" ;;
            0) break ;;
            *) echo -e "${ROSA}Opcion invalida${RESET}"; sleep 2 ;;
        esac
    done
}

# ─── MENU NGINX ──────────────────────────────────────────────────────────────
nginx_menu() {
    local op
    while true; do
        clear
        echo -e "${ROSA}"
        echo "======================================"
        echo "          MENU NGINX"
        echo "======================================"
        echo -e "${RESET}"
        echo -e "${ROSA}1) Instalar Nginx${RESET}"
        echo -e "${ROSA}2) Ver estado Nginx${RESET}"
        echo -e "${ROSA}3) Iniciar Nginx${RESET}"
        echo -e "${ROSA}4) Detener Nginx${RESET}"
        echo -e "${ROSA}5) Reiniciar Nginx${RESET}"
        echo -e "${ROSA}0) Volver${RESET}"
        echo
        read -rp "Seleccione opcion: " op
        op="${op//[^0-9]/}"
        case "$op" in
            1)
                local versiones=()
                mapfile -t versiones < <(obtener_versiones_nginx)
                elegir_version "Nginx" "${versiones[@]}" || { read -rp "ENTER..."; continue; }
                pedir_puerto
                instalar_nginx
                read -rp "Presione ENTER para continuar"
                ;;
            2)
                echo ""
                if systemctl is-active --quiet nginx-web 2>/dev/null; then
                    local p; p=$(ss -tlnp 2>/dev/null | grep nginx | grep -oP ':\K[0-9]+' | head -1)
                    local ip="${IP_SERVIDOR:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
                    echo -e "  Nginx: ${ROSA}Activo${RESET}"
                    echo "  $(systemctl status nginx-web | grep 'Active:')"
                    echo -e "  URL: ${ROSA}http://${ip}:${p:-?}/${RESET}"
                else
                    echo "  Nginx: Detenido o no instalado"
                fi
                echo ""
                read -rp "Presione ENTER para continuar"
                ;;
            3) systemctl start nginx-web 2>/dev/null \
                   && print_completado "Nginx iniciado." \
                   || print_error "No se pudo iniciar Nginx."
               read -rp "Presione ENTER para continuar" ;;
            4) systemctl stop nginx-web 2>/dev/null \
                   && print_completado "Nginx detenido." \
                   || print_error "No se pudo detener Nginx."
               read -rp "Presione ENTER para continuar" ;;
            5) systemctl restart nginx-web 2>/dev/null \
                   && print_completado "Nginx reiniciado." \
                   || print_error "No se pudo reiniciar Nginx."
               read -rp "Presione ENTER para continuar" ;;
            0) break ;;
            *) echo -e "${ROSA}Opcion invalida${RESET}"; sleep 2 ;;
        esac
    done
}

# ─── MENU TOMCAT ─────────────────────────────────────────────────────────────
tomcat_menu() {
    local op
    while true; do
        clear
        echo -e "${ROSA}"
        echo "======================================"
        echo "          MENU TOMCAT"
        echo "======================================"
        echo -e "${RESET}"
        echo -e "${ROSA}1) Instalar Tomcat${RESET}"
        echo -e "${ROSA}2) Ver estado Tomcat${RESET}"
        echo -e "${ROSA}3) Iniciar Tomcat${RESET}"
        echo -e "${ROSA}4) Detener Tomcat${RESET}"
        echo -e "${ROSA}5) Reiniciar Tomcat${RESET}"
        echo -e "${ROSA}0) Volver${RESET}"
        echo
        read -rp "Seleccione opcion: " op
        op="${op//[^0-9]/}"
        case "$op" in
            1)
                local versiones=()
                mapfile -t versiones < <(obtener_versiones_tomcat)
                elegir_version "Apache Tomcat" "${versiones[@]}" || { read -rp "ENTER..."; continue; }
                pedir_puerto
                instalar_tomcat
                read -rp "Presione ENTER para continuar"
                ;;
            2)
                echo ""
                if systemctl is-active --quiet tomcat 2>/dev/null; then
                    local p_int p_nat p_show
                    p_int=$(ss -tlnp 2>/dev/null | grep java | grep -oP '[:\*]\K[0-9]+' | grep -v "^8005$" | head -1)
                    p_nat=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep "redir ports ${p_int}" | grep -oP 'dpt:\K[0-9]+' | head -1)
                    p_show="${p_nat:-$p_int}"
                    local ip="${IP_SERVIDOR:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
                    echo -e "  Tomcat: ${ROSA}Activo${RESET}"
                    echo "  $(systemctl status tomcat | grep 'Active:')"
                    echo -e "  URL: ${ROSA}http://${ip}:${p_show:-?}/${RESET}"
                else
                    echo "  Tomcat: Detenido o no instalado"
                fi
                echo ""
                read -rp "Presione ENTER para continuar"
                ;;
            3) systemctl start tomcat 2>/dev/null \
                   && print_completado "Tomcat iniciado." \
                   || print_error "No se pudo iniciar Tomcat."
               read -rp "Presione ENTER para continuar" ;;
            4) systemctl stop tomcat 2>/dev/null \
                   && print_completado "Tomcat detenido." \
                   || print_error "No se pudo detener Tomcat."
               read -rp "Presione ENTER para continuar" ;;
            5) systemctl restart tomcat 2>/dev/null \
                   && print_completado "Tomcat reiniciado." \
                   || print_error "No se pudo reiniciar Tomcat."
               read -rp "Presione ENTER para continuar" ;;
            0) break ;;
            *) echo -e "${ROSA}Opcion invalida${RESET}"; sleep 2 ;;
        esac
    done
}
