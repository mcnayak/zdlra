#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/11.2.0.4/dbhome_2
export ORACLE_SID=cust99dp
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH export logdir=/home/oracle/log export dt=`date +%y%m%d%H%M%S` export NLS_DATE_FORMAT='DD-MM-YYYY HH24:MI:SS'

function drop_aux_db {
export ORACLE_SID=cust99dp
$ORACLE_HOME/bin/sqlplus -s '/ as sysdba' <<EOF2 set pagesize 999 linesize 999 heading off feedback off select name, open_mode from v\$database; shutdown immediate; startup mount exclusive restrict; drop database; exit;
EOF2
}

echo "Cleaning any left over files"
/bin/rm /u01/app/oracle/admin/adump/cust99/*aud
/bin/rm /u01/app/oracle/admin/adump/cust99dp/*aud
##/bin/rm /u01/app/oracle/product/11.2.0.4/dbhome_1/dbs/*cust99dp*


echo "Backup the target database"
function backup_source_db {
$ORACLE_HOME/bin/rman target sys/welcome1@cust99 catalog rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2:dedicated <<EOF RUN { backup as backupset cumulative incremental level 1 database include current controlfile plus archivelog not backed up delete input;} exit; EOF }

sleep 120

echo "List the backup of the target database"
function check_source_db_backup {
$ORACLE_HOME/bin/rman target sys/welcome1@cust99 catalog rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2:dedicated <<EOF LIST BACKUP OF DATABASE COMPLETED AFTER '(SYSDATE-1/24)'; EOF }

echo "Startup the auxiliary database in force nomount"
function nomount_aux_db {
export ORACLE_SID=cust99dp
$ORACLE_HOME/bin/rman target / <<EOF2
startup force nomount pfile='/home/oracle/initcust99dp.ora';
exit;
EOF2
}

echo "Execute the duplication"
function dup_aux_db {
export ORACLE_SID=cust99dp
$ORACLE_HOME/bin/rman catalog rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2:dedicated AUXILIARY / <<EOF run { duplicate database CUST99 to CUST99DP spfile set control_files '+REDO/${ORACLE_SID}/CONTROLFILE/cf3.ctl' 
set db_create_file_dest '+DATA' ;
}
exit;
EOF
}

echo "Check a schema objects on the target"
function check_source_db {
$ORACLE_HOME/bin/sqlplus -s system/welcome1@cust99 <<EOF2 set pagesize 999 linesize 999 heading off feedback off select name, open_mode from v\$database; select table_name, num_rows from dba_tables where owner='SOE'; exit;
EOF2
}

echo "Check a schema objects on the auxiliary to auxiliary"
function check_aux_db {
export ORACLE_SID=cust99dp
$ORACLE_HOME/bin/sqlplus -s '/ as sysdba' <<EOF2 set pagesize 999 linesize 999 heading off feedback off select name, open_mode from v\$database; select table_name, num_rows from dba_tables where owner='SOE'; exit;
EOF2
}

drop_aux_db
backup_source_db
check_source_db_backup
nomount_aux_db
dup_aux_db
check_source_db
check_aux_db
