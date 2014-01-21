#!/bin/sh 

########################################
# configuracion general
# en las rutas no agregar la barra final
########################################

# configuracion de mail, debe estar instalado mailutils, ssmtp y configurar /etc/ssmtp/ssmtp.conf
from=yourmail@yourdomain
to=yourmail@yourdomain
subject="backup failed"

# NFS: en caso de que la carpeta destino sea un montaje NFS, indicar aca el punto de montaje, sino dejar en blanco
MNT_PATH=/media/backup

# LVM, dev de la particion LVM, sino usamos LVM dejar en blanco 
DEV_PATH=/dev/vg-sig/sistema

# LVM, dev del snapshot LVM, sino usamos LVM dejar en blanco 
SNP_NAME=sistema-snap
SNP_PATH=/dev/vg-sig/$SNP_NAME
SNP_SIZE=1G

# carpeta origen del backup, si usamos LVM aca va el punto de montaje del snapshot
SRC_PATH=/media/sistema-snap

# carpeta destino del backup
DES_PATH=$MNT_PATH
DES_NAME=sistema

# archivo de log
LOGFILE=$DES_PATH/backup.log

# carpetas a excluir, relativas a SRC_PATH
EXCLUDE="--exclude=lost+found --exclude=util --exclude=tmp"

########################################
# no tocar nada a partir de aca
########################################

# indico con un flag que estoy haciendo backup, para que scripts en el server lo tengan en cuenta
FLG_NAME=$DES_PATH/--haciendo-backup--

# archivos de control para rotaciones
CRT_WEEK=--backup-week-$(date +"%Y-%W")
CRT_DATE=--backup-date-$(date +"%Y-%m-%d")
CRT_TIME=--backup-time-$(date +"%Y-%m-%d_%H:%M")

rm -f $0.err
rm -f $FLG_NAME 

############################################################################
# en caso de usar NFS, chequeamos que la particion de backup esté montada y si no, la montamos.
############################################################################
if [ "$MNT_PATH" != "" ]; then

  mnt_acti=`mount | grep $MNT_PATH`
  if [ "$mnt_acti" = "" ]; then
    mount $MNT_PATH
  fi

  mnt_acti=`mount | grep $MNT_PATH`
  if [ "$mnt_acti" = "" ]; then
    echo $(date) no se pudo montar la particion $MNT_PATH >> $0.err
    mail -a "From: $from" -s "$subject" $to < $0.err
    exit
  fi

fi

############################################################################
# si usamos LVM, hacemos snapshots
############################################################################
if [ "$SNP_PATH" != "" ]; then

  # me fijo que no exista el snapshot, puede significar que no termino de hacerse un backup anterior
  if [ -e "$SNP_PATH" ]; then
    echo $(date) el snapshot esta activo, no puede crearse uno nuevo >> $0.err
    mail -a "From: $from" -s "$subject" $to < $0.err
    exit
  fi

  # si no existe el directorio SRC_PATH lo creo
  if [ ! -d "$SRC_PATH" ]; then
    mkdir $SRC_PATH
  fi

  # creo el snapshot
  echo $(date) creando snapshot >> $LOGFILE
  /sbin/lvcreate -L$SNP_SIZE -s -n $SNP_NAME $DEV_PATH >> $LOGFILE 2>&1

  # monto el snapshot
  mount $SNP_PATH $SRC_PATH >> $LOGFILE 2>&1

  # si no se monto el directorio, elimino el snapshot de existir y salgo
  mnt_acti=`mount | grep $SRC_PATH`
  if [ "$mnt_acti" = "" ]; then
    echo $(date) no se pudo montar la particion $SRC_PATH >> $0.err
    mail -a "From: $from" -s "$subject" $to < $0.err
    if [ -e "$SNP_PATH" ]; then
      /sbin/lvremove -f $SNP_PATH >> $LOGFILE 2>&1
    fi
    exit
  fi

fi

############################################################################
# realizo backup rotativo
############################################################################

# activo flag
touch $FLG_NAME

# borro cualquier rastro del directorio temporal destino
rm -rf $DES_PATH/backup

# realizo backup a directorio destino backup (creo previamente los directorios necesarios)
echo $(date) generando backup >> $LOGFILE
mkdir -p $DES_PATH/backup/$DES_NAME
mkdir -p $DES_PATH/backup.0/$DES_NAME
rsync -a --delete --stats --quiet --log-file-format="" --log-file=$LOGFILE $EXCLUDE --link-dest=$DES_PATH/backup.0/$DES_NAME $SRC_PATH/ $DES_PATH/backup/$DES_NAME >> $0.err

# hago la rotacion solo si se copio bien
#
# en vez de borrar el ultimo directorio, lo logico seria moverlo al principio para que sea mas rapido,
# pero esta documentado en el manual de rsync que la funcion --link-dest no funciona bien cuando el directorio destino no esta vacio
#
if [ ! -s "$0.err" ]; then

  echo $(date) rotando copias >> $LOGFILE

  # pongo archivos de control con fechas en backup
  touch $DES_PATH/backup/$CRT_WEEK
  touch $DES_PATH/backup/$CRT_DATE
  touch $DES_PATH/backup/$CRT_TIME

  # si la fecha actual de backup coincide con la ultima realizada, hago rotacion simple
  if [ -f "$DES_PATH/backup.0/$CRT_DATE" ]; then

    # si existe el directorio backup.0 lo borro
    rm -rf $DES_PATH/backup.0

  # sino hago rotacion diaria
  else

    # si existe el directorio backup.2 lo borro
    rm -rf $DES_PATH/backup.2

    # si existe el directorio backup.1 lo muevo a backup.2
    if [ -d "$DES_PATH/backup.1" ]; then
      mv $DES_PATH/backup.1 $DES_PATH/backup.2
    fi

    # si existe el directorio backup.0 lo muevo a backup.1
    if [ -d "$DES_PATH/backup.0" ]; then
      mv $DES_PATH/backup.0 $DES_PATH/backup.1
    fi

  fi

  # si existe el directorio backup lo muevo a backup.0
  if [ -d "$DES_PATH/backup" ]; then
    mv $DES_PATH/backup $DES_PATH/backup.0
  fi

fi

# libero el flag
rm -f $FLG_NAME

# mando un mail en caso de error con rsync
if [ -s "$0.err" ]; then
  mail -a "From: $from" -s "$subject" $to < $0.err
fi

############################################################################
# si usamos LVM, eliminamos snapshots
############################################################################
if [ "$SNP_PATH" != "" ]; then

  # desmonto el snapshot
  umount $SRC_PATH >> $LOGFILE 2>&1

  # elimino el snapshot
  echo $(date) borrando snapshot >> $LOGFILE
  /sbin/lvremove -f $SNP_PATH >> $LOGFILE 2>&1

fi

############################################################################

echo $(date) ---- proceso terminado >> $LOGFILE
echo ------------------------------------------------------------------------------------------------------- >> $LOGFILE
