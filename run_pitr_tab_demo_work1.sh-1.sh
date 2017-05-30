#!/bin/bash

clear
export ORACLE_SID=TABLERECO
export ORACLE_HOME=/u01/app/oracle/product/12102/db_1
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH export zdlra_ezconnect="//slcm03ingest-scan3:1521/zdlra2:dedicated"
export WORKDIR=/home/oracle/work

echo "Oracle Zero Data Loss Recovery Appliance - Table Restore and Recovery"

sleep 2

echo " "
echo " "
echo "This database is protected by the Oracle Zero Data Loss Recovery Appliance."
echo "This DEMO shows how we can recover a table content uing RMAN RECOVER after it was lost."
echo "Let's create a table and insert some rows in it."
echo " "
echo " "

function create_load_table {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 999 start ${WORKDIR}/pitr_tab_demo_cre_load.sql;
exit
EOF
}

create_load_table

sleep 4 

echo " "
echo " "
echo "The table got truncated by mistake!!"
echo " "
echo " "

sleep 3

function get_scn {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 80 feedback off trimspool on heading off feedback off select current_scn from v\$database; exit; EOF }

until_scn=$(get_scn)

function truncate_table {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 999 truncate table pitr.pitr_demo; select count(*) from pitr.pitr_demo; exit EOF }

truncate_table

sleep 3

echo " "
echo "We need to recover the table content back."
echo "With Oracle Database 12c, RMAN enables you to recover one or more tables or table partitions to a "
echo "specified point in time without affecting the remaining database objects."
echo " "
echo " "
echo " "
echo "RMAN uses the RECOVER command to recover tables or table partitions to a specified point in time."
echo "To recover tables and table partitions from an RMAN backup, you need to provide the following information:"
echo "1)-Names of tables or table partitions that must be recovered."
echo "2)-Point in time to which the tables or table partitions must be recovered."
echo "3)-Whether the recovered tables or table partitions must be imported into the target database."
echo " "
echo " "
echo " "
echo "Our table is called PITR_DEMO and we want to recover it back unde a different name called PITR_DEMO1"
echo "Let's get the scn we want to recover back to "
sleep 10 

echo " "
echo " "
echo "The SCN we need is:" $until_scn

sleep 3

echo " "
echo " "
echo "Let's start the recovery...."
echo " "
echo " "

sleep 3

$ORACLE_HOME/bin/rman target sys/welcome1@\"${ORACLE_SID}\" catalog rauser12/welcome1@${zdlra_ezconnect} <<EOF run {
    set auxiliary instance parameter file to '/home/oracle/work/initpitr.ora';
    recover table 'PITR'.'PITR_DEMO' until scn $until_scn AUXILIARY DESTINATION '/oradata/TABPITR' REMAP TABLE 'PITR'.'PITR_DEMO':'PITR_DEMO1';
    }
exit;
EOF

echo " "
echo " "
echo "Let's check the content of the PITR_DEMO1 table.."
echo " "
echo " "

function check_pitr {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 999 select count(*) "COUNT_PITR_DEMO1" from pitr.pitr_demo1; exit EOF }

check_pitr

echo " "
echo " "
echo "The table has been recovered."
echo " "
echo " "


echo "Calling level 1 backup for the database ..."
/bin/sh /home/oracle/work/run_backup_pitrtab.sh > /dev/null 2>&1 

