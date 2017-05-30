#!/bin/bash

clear
export ORACLE_SID=DEMO1
export ORACLE_HOME=/u01/app/oracle/product/12102/db_1
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH export zdlra_ezconnect="//slcm03ingest-scan3:1521/zdlra2:dedicated"
export WORKDIR=/home/oracle/work

echo "Oracle Zero Data Loss Recovery Appliance - Revoke Delete Demo"

sleep 2

echo " "
echo " "
echo "This database is protected by the Oracle Zero Data Loss Recovery Appliance."
echo "This DEMO shows how delete Revoke stops backups from being removed from the ZDLRA "
echo "  when an RMAN => Drop database including backups noprompt is executed "
echo " "
echo " "

sleep 4 

echo " "
echo " "
echo " Let's backup the database "
echo " "
echo " "
echo "Calling level 1 backup for the database ..."
/bin/sh /home/oracle/work/run_backup_demo1_inc.sh > /dev/null 2>&1 


function backup_init {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 999 create pfile='/home/oracle/work/initDEMO1.ora' from spfile; exit EOF }

backup_init

echo "Lets get the current scn"
sleep 3
function get_scn {
$ORACLE_HOME/bin/sqlplus -s  sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 80 feedback off trimspool on heading off feedback off select current_scn from v\$database; exit; EOF }

until_scn=$(get_scn)

echo "scn is "
echo $until_scn

echo "show all the backups that exist ..."


$ORACLE_HOME/bin/rman target sys/welcome1@\"${ORACLE_SID}\" catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF
   list backup summary;
exit;
EOF


echo "shutdown and startup in restricted mode ..."


$ORACLE_HOME/bin/rman target sys/welcome1 catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF
   shutdown immediate;
   startup mount;
   SQL 'alter SYSTEM enable restricted session'; exit; EOF


echo "Drop database including backups ..."



$ORACLE_HOME/bin/rman target sys/welcome1 catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF
   drop database including backups noprompt; exit; EOF

echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "*                                                                  *"
echo "*  ==> NOTICE - database was dropped successfully                  *"
echo "*                                                                  *"
echo "*                                                                  *"
echo "* ==> NOTICE - RMAN-20301 : operation not supported;               *"
echo "*                           Backup Appliance administrator         *"
echo "*                           should use the DBMS_BA.DELETE_DB_API   *"
echo "*                                                                  *"
echo "*********  BACKUPS ARE NOT DROPPED                                 *"
echo "*                                                                  *"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"
echo "********************************************************************"

echo "now lets start the database nomount and  restore the control file ..."


$ORACLE_HOME/bin/rman target / catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF
  startup nomount pfile='/home/oracle/work/initDEMO1.ora';
   restore controlfile until scn $until_scn; exit; EOF

echo "copy the control file to the second location ..."
mkdir /oradata/flash/DEMO1/DEMO1
cp /oradata/DEMO1/DEMO1/control01.ctl /oradata/flash/DEMO1/DEMO1/control02.ctl

echo "now lets mount the database  and  restore the files ..."


$ORACLE_HOME/bin/rman target / catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF
  alter database mount;
   restore database until scn $until_scn;
   recover database until scn $until_scn;
   alter database open resetlogs;
  create spfile from pfile='/home/oracle/work/initDEMO1.ora';
exit;
EOF


echo "Calling level 1 backup for the database ..."
/bin/sh /home/oracle/work/run_backup_demo1_inc.sh > /dev/null 2>&1 
