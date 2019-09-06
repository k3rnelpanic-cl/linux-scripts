#!/bin/bash
#       Script desarrollado por Victor Vidal
#       Automatizacion generacion respaldos de BD HANA y limpia logs de catalogo HANA en base a X dias
#
#       INST            Acronimo de Instancia de BD Hana
#       COD             Codigo numerico de Instancia Hana
#       BACKUP_RUTADATA Ruta de destino de respaldos Hana BD
#       RETENCION       Dias a mantener en logs de hana BD
#       SEMANAS         Semanas a listar de comparar datos
INST="NDD"
COD="04"
NUM="HDB$COD"
RETENCION=55
SEMANAS=7
BACKUP_RUTADATA=/hana/backup/$INST/databackup
SQLBIN=/usr/sap/$INST/$NUM/exe/hdbsql
#       VARIABLES
TIMESTAMP="$(date +\%F\_%H\%M)"
MESBKP=$(date +%Y%m)
NAMEDATA=$(date +%Y%m%d)
RUTADATA=/hana/backup/$INST/databackup
BACKUP_PREFIX="$INST"_"$TIMESTAMP"
OBJETIVO="BACKUPBD"
PROC=$OBJETIVO
#       VARIABLES
#FUNCIONES
tiempo() {
echo -n "$( date +"%b %d %T") $OBJETIVO"
}
checkok() {
if [ "$?" -ne "0" ]; then
        echo "$PROC con ERROR. Abortando script"
        exit 1
        elif [ "$?" -ge "1" ]; then
        echo "$PROC OK."
fi
}
#       Chequeo de rutas de respaldo
if [ -d "$BACKUP_RUTADATA" ]; then
        echo "Ruta de respaldo $BACKUP_RUTADATA OK"
        else
        echo "Ruta de respaldo $BACKUP_RUTADATA NO existe. Creando Ruta"
        mkdir -pv $BACKUP_RUTADATA
fi
#       Revisa existencia de rutas mensuales para DATA y LOG
if [ ! -d "$BACKUP_RUTADATA"/"$MESBKP" ]; then
        mkdir $BACKUP_RUTADATA/$MESBKP
fi
checkok
#################
# GENERA RESPALDO DE BD HANA
#################
#Establece nombre en base a fecha para el respaldo y lo guarda en un archivo .sql
echo -e "$(tiempo)    ****************** INICIO BACKUPBD ***************"
PROC="Generacion backup desde Instancia HANA"
/usr/sap/$INST/$NUM/exe/hdbsql -U BACKUP "backup data using file ('$RUTADATA/$BACKUP_PREFIX')"
checkok
###########################
# BUSCA RESPALDO BD Y COMPRIME
###########################

#       genera HASH en md5 para comprobar integridad de archivo.
LISTA1=$(ls $RUTADATA|  grep $BACKUP_PREFIX)
for lista1 in $LISTA1; do
        echo -e "$(tiempo)    Calculando hash md5 de $lista1"
        md5sum $RUTADATA/$lista1 >> $RUTADATA/$BACKUP_PREFIX.md5
done
echo -e "$(tiempo) INICIA COMPRESION BACKUP BD HANA"
#       Genera archivo comprimido
tar zcf $BACKUP_RUTADATA/$MESBKP/${HOST}_${INST}${COD}_${NAMEDATA}.tar.gz $RUTADATA/$BACKUP_PREFIX\_* $RUTADATA/$BACKUP_PREFIX.md5
PROC="Compresion de archivos"
checkok
#       Elimina archivos de backup Data BD de entre 0 y 24 horas antiguedad"
find $RUTADATA -iname "$BACKUP_PREFIX*" -type f -mtime 0 -exec rm -rf {} \;
PROC="Elimina archivos resudios de backup"
checkok
#       Busca archivos de antiguedad mayores a 10 dias y los elimina."
find $BACKUP_RUTADATA -mtime +10 -iname '*.tar.gz' -exec rm -rf {} \;
PROC="Elimina respaldos mayores a 7 dias"
checkok
#
echo -e "$(tiempo)    ****************** FIN BACKUPBD ***************"
echo -e "$(tiempo)    ****************** INICIA LIMPIEZA CATALOGO ***************"
PROC="Obtencion de BACKUP_ID"
#       TARGETID es el ID de BACKUP_ID del penultimo catalogo valido.
TARGETID=$(${SQLBIN} -ajx -U BACKUP -i $COD -n localhost:3${COD}15 "SELECT BACKUP_ID FROM "PUBLIC"."M_BACKUP_CATALOG" WHERE SYS_START_TIME >= ADD_DAYS(CURRENT_DATE, -$RETENCION) AND SYS_START_TIME <= CURRENT_TIMESTAMP AND ENTRY_TYPE_NAME = 'complete data backup' AND STATE_NAME = 'successful';" | head -1)
#       TARGET_TIME es la hora en la cual se ejecutó el ultimo backup valido.
TARGETTIME=$(${SQLBIN} -ajx -U BACKUP -i $COD -n localhost:3${COD}15 "SELECT SYS_START_TIME FROM "PUBLIC"."M_BACKUP_CATALOG" WHERE SYS_START_TIME >= ADD_DAYS(CURRENT_DATE, -$RETENCION) AND SYS_START_TIME <= CURRENT_TIMESTAMP AND ENTRY_TYPE_NAME = 'complete data backup' AND STATE_NAME = 'successful';" | head -1)
COUNTTARGET=$(${SQLBIN} -ajx -U BACKUP -i $COD -n localhost:3${COD}15 "SELECT BACKUP_ID FROM "PUBLIC"."M_BACKUP_CATALOG" WHERE SYS_START_TIME <= CURRENT_TIMESTAMP AND ENTRY_TYPE_NAME = 'complete data backup' AND STATE_NAME = 'successful';" | wc -l)
#       LISTA_TARGET es la lista full de los catalogos
LISTATARGET=$(${SQLBIN} -jx -U BACKUP -i $COD -n localhost:3${COD}15 "SELECT BACKUP_ID,SYS_START_TIME FROM "PUBLIC"."M_BACKUP_CATALOG" WHERE SYS_START_TIME <= CURRENT_TIMESTAMP AND ENTRY_TYPE_NAME = 'complete data backup' AND STATE_NAME = 'successful';" | tr ',' '\t')
if [ ${COUNTTARGET} -le ${SEMANAS} ];then
        echo -e "\nERROR: existen actualmente $COUNTTARGET catalogos registrados. Minimo $SEMANAS"
        echo -e "${LISTATARGET}\n\nSaliendo..."
        exit 1
fi
echo -e "Eliminando todos los catalogos de antes de ${TARGETTIME}"
PROC="Limpia Catalogo"
${SQLBIN} -ajx -U BACKUP -i $COD -n localhost:3${COD}15 "BACKUP CATALOG DELETE ALL BEFORE BACKUP_ID $TARGETID COMPLETE;"
checkok
echo -e "$(tiempo)    ****************** FIN LIMPIEZA CATALOGO ***************"
###########################
