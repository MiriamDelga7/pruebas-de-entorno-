#!/bin/bash

instalar_servicio() {

 if rpm -q openssh-server &>/dev/null; then
  echo "ssh presente"
 else
  echo "instalando ssh"
  sudo urpmi --auto openssh-server
 fi

 sudo systemctl enable sshd
 sudo systemctl start sshd

 echo "ssh listo"
}

estado_servicio() {

 if ! rpm -q openssh-server &>/dev/null; then
  echo "ssh no instalado"
  return
 fi

 systemctl is-active --quiet sshd && echo "activo" || echo "inactivo"
 systemctl is-enabled --quiet sshd && echo "habilitado" || echo "no habilitado"
}

detener_servicio() {

 if systemctl is-active --quiet sshd; then
  sudo systemctl stop sshd
  echo "ssh detenido"
 else
  echo "ssh ya estaba detenido"
 fi
}

activar_servicio() {

 sudo systemctl enable sshd
 sudo systemctl start sshd
 echo "ssh activado"
}

case "$1" in

 instalar)
  instalar_servicio
 ;;

 verificar)
  estado_servicio
 ;;

 detener)
  detener_servicio
 ;;

 activar)
  activar_servicio
 ;;

 *)
  echo "uso: $0 {instalar|verificar|detener|activar}"
 ;;

esac