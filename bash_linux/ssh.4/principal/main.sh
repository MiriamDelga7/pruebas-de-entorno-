#!/bin/bash

if [ "$EUID" -ne 0 ]; then
 echo "usar root"
 exit
fi

source ../lasfun/fundhcp.sh
source ../lasfun/fundns.sh

case "$1" in

 dhcp)

  if [ -z "$2" ]; then
   echo "opciones dhcp:"
   echo "./main.sh dhcp verificar"
   echo "./main.sh dhcp instalar"
   echo "./main.sh dhcp configurar"
   echo "./main.sh dhcp reiniciar"
   echo "./main.sh dhcp monitoreo"
   echo "./main.sh dhcp reset"
   exit
  fi

  case "$2" in
   verificar) verificar_dhcp ;;
   instalar) instalar_dhcp ;;
   configurar) configurar_dhcp ;;
   reiniciar) guardaryreiniciar ;;
   monitoreo) monitoreo ;;
   reset) reset_dhcp ;;
   *) echo "opcion dhcp no valida" ;;
  esac
 ;;

 dns)

  if [ -z "$2" ]; then
   echo "opciones dns:"
   echo "./main.sh dns instalar"
   echo "./main.sh dns estado"
   echo "./main.sh dns agregar dominio ip"
   echo "./main.sh dns listar"
   echo "./main.sh dns eliminar dominio"
   echo "./main.sh dns desinstalar"
   exit
  fi

  case "$2" in
   instalar) instalar ;;
   estado) estado ;;
   agregar) agregar "$3" "$4" ;;
   listar) listar ;;
   eliminar) eliminar_dominio "$3" ;;
   desinstalar) desinstalar ;;
   *) echo "opcion dns no valida" ;;
  esac
 ;;

 *)
  echo "uso general:"
  echo "./main.sh dhcp"
  echo "./main.sh dns"
 ;;

esac
