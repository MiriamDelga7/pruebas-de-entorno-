#!/bin/bash
# http2main.sh - Menu principal HTTP Server
# Practica - Mageia Linux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ! -f "$SCRIPT_DIR/fun3http.sh" ]] && { echo "[ERROR] No se encontro fun3http.sh"; exit 1; }

source "$SCRIPT_DIR/fun3http.sh"

ROSA="\033[1;35m"
RESET="\033[0m"

menu_principal() {

    clear

    echo -e "${ROSA}"
    echo "======================================"
    echo "        PARAMETROS HTTP SERVER"
    echo "  Sistema: $(uname -n)  |  $(date '+%Y-%m-%d %H:%M')"
    echo "======================================"
    echo -e "${RESET}"

    verificar_HTTP

    echo -e "${ROSA}1) Apache${RESET}"
    echo -e "${ROSA}2) Nginx${RESET}"
    echo -e "${ROSA}3) Tomcat${RESET}"
    echo -e "${ROSA}4) Estado servidores${RESET}"
    echo -e "${ROSA}0) Salir${RESET}"
    echo
}

ejecutar_menu() {

    local OPCION

    while true; do

        menu_principal
        read -rp "Seleccione opcion: " OPCION
        OPCION="${OPCION//[^0-9]/}"

        case "$OPCION" in

            1)
                apache_menu
                read -rp "Presione ENTER para continuar"
                ;;

            2)
                nginx_menu
                read -rp "Presione ENTER para continuar"
                ;;

            3)
                tomcat_menu
                read -rp "Presione ENTER para continuar"
                ;;

            4)
                verificar_HTTP
                read -rp "Presione ENTER para continuar"
                ;;

            0)
                echo -e "${ROSA}Hasta luego.${RESET}"
                exit 0
                ;;

            *)
                echo -e "${ROSA}Opcion invalida${RESET}"
                sleep 2
                ;;

        esac

    done
}

validar_root
detectar_entorno
ejecutar_menu
