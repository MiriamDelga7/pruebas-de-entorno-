#!/bin/bash

# VALIDAR ROOT

if [ "$EUID" -ne 0 ]; then
 echo "Ejecuta como root"
 exit 1
fi


# CARGAR MODULOS

source ../lasfun/fundhcp.sh
source ../lasfun/fundns.sh


# CONTROL POR PARAMETROS
case "$1" in


# DHCP

dhcp)

 case "$2" in

 verificar) verificar_dhcp_rango ;;

 instalar) instalar_dhcp_rango ;;

 configurar) configurar_dhcp_rango ;;

 reiniciar) guardar ;;

 monitoreo) monitoreo_rango ;;

 reset) reset_dhcp_rango ;;

 interfaz) verificar_interfaz_dhcp ;;

 *)
 echo "Uso DHCP:"
 echo "./main.sh dhcp verificar"
 echo "./main.sh dhcp instalar"
 echo "./main.sh dhcp configurar"
 echo "./main.sh dhcp reiniciar"
 echo "./main.sh dhcp monitoreo"
 echo "./main.sh dhcp reset"
 echo "./main.sh dhcp interfaz"
 ;;

 esac
;;


# DNS

dns)

 case "$2" in

 instalar) activar_dns ;;

 estado) ver_estado ;;

 crear) crear_zona "$3" "$4" ;;

 listar) mostrar_zonas ;;

 eliminar) borrar_zona "$3" ;;

 remover) remover_dns ;;

 *)
 echo "Uso DNS:"
 echo "./main.sh dns instalar"
 echo "./main.sh dns estado"
 echo "./main.sh dns crear dominio IP"
 echo "./main.sh dns listar"
 echo "./main.sh dns eliminar dominio"
 echo "./main.sh dns remover"
 ;;

 esac
;;


# AYUDA GENERAL

*)
echo " SERVIDOR AUTOMATIZADO"
echo "DHCP:"
echo "./main.sh dhcp verificar"
echo "./main.sh dhcp instalar"
echo "./main.sh dhcp configurar"
echo "./main.sh dhcp reiniciar"
echo "./main.sh dhcp monitoreo"
echo "./main.sh dhcp reset"
echo ""
echo "DNS:"
echo "./main.sh dns instalar"
echo "./main.sh dns estado"
echo "./main.sh dns crear dominio.com 192.168.50.10"
echo "./main.sh dns listar"
echo "./main.sh dns elminar dominio"
echo ""
;;

esac
