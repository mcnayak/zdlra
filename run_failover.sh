#!/bin/bash

clear
export ORACLE_SID=FAILOVER
export ORACLE_HOME=/u01/app/oracle/product/12102/db_1
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH export zdlra_ezconnect_primary="//slcm03ingest-scan1:1521/zdlra1:dedicated"
export zdlra_ezconnect_alt="//slcm03ingest-scan3:1521/zdlra2:dedicated"
export WORKDIR=/home/oracle/work
export NLS_DATE_FORMAT='MM/DD/YY HH24:MI:SS'

echo "Oracle Zero Data Loss Recovery Appliance - Alternative Destination Failover demo  AKA Store and Forward" 


echo "*************************************************************************************************"
echo "*                                                                                               *"
echo "* This database is protected by the Oracle Zero Data Loss Recovery Appliance.                   *"
echo "*                                                                                               *"
echo "* In this demo, FAILOVER DB's incremental and redo are normally sent                            *"
echo "* to RA in New York (Primary RA).  RA San Francisco is the Alternate RA                         *"
echo "*                                                                                               *"
echo "* STEP 1 - Steady State                                                                         *"
echo "*                                                                                               *"
echo "* - Primary Appliance is 'rauser12' VPC user and is  running in New York                        *"
echo "* - Alternate Appliance is 'repuser_from_sfo' and is running in San Francisco                   *"
echo "* - Replication is READY from 'rauser12' to 'repuser_from_sfo' (the alternate can contact       *"
echo "* -                                                             the primary)                    *"
echo "* - Real-Time Redo is VALID for 'rauser12'                                                      *"
echo "*                                                                                               *"
echo "*************************************************************************************************"



function nyc_ra_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_nyc <<EOF set pagesize 999 linesize 999 set heading off select 'Current State for NYC Ra is : ' || state from ra_server; exit EOF }

function sf_ra_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_sf <<EOF set pagesize 999 linesize 999 set heading off select 'Current State for SF Ra is : ' || state from ra_server; exit EOF } echo " "
echo " Lets check the state for both RA. Remember NYC is Primary, SF is alternative "
echo " "
echo "NYC State "
nyc_ra_status
echo "SF State "
sf_ra_status

echo " "
echo " STORE_AND_FORWARD setting for database FAILOVER "
echo "        on Primary Appliance(NYC) "
echo " "

function nyc_db_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_nyc <<EOF set pagesize 999 linesize 999 column db_unique_name format a10 heading 'DB Unique name'
column policy_name format a15 heading 'Policy Name'
column store_and_forward format a20 heading 'Store and Forward?"'

select db_unique_name ,policy_name,store_and_forward 
   from ra_database where db_unique_name='FAILOVER' ; exit; EOF }

function sf_db_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_sf <<EOF set pagesize 999 linesize 999 column db_unique_name format a10 heading 'DB Unique name'
column policy_name format a15 heading 'Policy Name'
column store_and_forward format a20 heading 'Store and Forward?"'

select db_unique_name ,policy_name,store_and_forward 
   from ra_database where db_unique_name='FAILOVER' ; exit; EOF }

sf_db_status
nyc_db_status

echo " "
echo " STORE_AND_FORWARD setting for database FAILOVER "
echo "        on Alternate Appliance(SFO) "
echo " "

function sf_db_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_sf <<EOF set pagesize 999 linesize 999 column db_unique_name format a10 heading 'DB Unique name'
column policy_name format a15 heading 'Policy Name'
column store_and_forward format a20 heading 'Store and Forward?"'

select db_unique_name ,policy_name,store_and_forward 
   from ra_database where db_unique_name='FAILOVER' ; exit; EOF } sf_db_status






echo " "



function sf_rep_status {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_sf <<EOF set pagesize 999 linesize 999 column replication_server_name format a30 heading 'Replication Server Name'
column replication_server_state format a15 heading 'status'

select replication_server_name,replication_server_state 
   from ra_replication_server;
exit;
EOF
}

echo "           Current Replication Server Status "
echo "             on Alternate Appliance  "
echo " "

sf_rep_status


function log_dest_status {
$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF 

column db_unique_name format a10 heading 'DB Unique name'
column destination format a50 heading 'EZ Connect String'
column status format a15 heading 'LAD Status'


select db_unique_name,status,destination 
   from v\$archive_dest where dest_name in ('LOG_ARCHIVE_DEST_2','LOG_ARCHIVE_DEST_3');
exit;
EOF
}

echo "           Current Log Archive Dest (LAD) settings "
echo "             for database FAILOVER  "
echo " "

log_dest_status



function nyc_stop {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_nyc <<EOF set pagesize 999 linesize 999 set heading off set serveroutput on exec dbms_ra.shutdown; exit EOF }

echo " "
echo " Lets stop the NYC Primary RA to see what happens"
echo " "

nyc_stop

echo " "
echo " Lets check the state for both RA. Remember NYC is Primary, SF is alternative "
echo " "
echo "NYC State "
nyc_ra_status
echo "SF State "
sf_ra_status



echo "           Current Log Archive Dest (LAD) settings "
echo "             for database FAILOVER  "
echo " "

log_dest_status
#


sleep 3
function get_scn {
$ORACLE_HOME/bin/sqlplus -s  sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 80 feedback off trimspool on heading off feedback off select current_scn from v\$database; exit; EOF }

start_scn=$(get_scn)
start_date=`date "+%m/%d/%y %T"`
sleep 2
echo "****************************************************"
echo "*"
echo "* Step 2  -- Primary RA is not available -- Now what"
echo "*"
echo "****************************************************"


echo "****************************************************"
echo "*"
echo "* Now we backup to the alternate RA - SFO           "
echo "*"
echo "****************************************************"


$ORACLE_HOME/bin/rman log=$LOG_TRACE_DIR/rman_failover_log_sf_inc.log  <<EOF connect target / connect catalog rauser12/welcome1@ra_sf RUN { ALLOCATE CHANNEL c1 DEVICE TYPE sbt_tape PARMS='SBT_LIBRARY=/u01/app/oracle/product/12102/db_1/lib/libra.so,ENV=(RA_WALLET=location=file:/u01/app/oracle/product/12102/db_1/dbs/zdlra credential_alias=slcm03ingest-scan3:1521/zdlra2:dedicated)'  FORMAT'%U_%d'; ALLOCATE CHANNEL c2 DEVICE TYPE sbt_tape PARMS='SBT_LIBRARY=/u01/app/oracle/product/12102/db_1/lib/libra.so,ENV=(RA_WALLET=location=file:/u01/app/oracle/product/12102/db_1/dbs/zdlra credential_alias=slcm03ingest-scan3:1521/zdlra2:dedicated)'  FORMAT'%U_%d'; ALLOCATE CHANNEL c3 DEVICE TYPE sbt_tape PARMS='SBT_LIBRARY=/u01/app/oracle/product/12102/db_1/lib/libra.so,ENV=(RA_WALLET=location=file:/u01/app/oracle/product/12102/db_1/dbs/zdlra credential_alias=slcm03ingest-scan3:1521/zdlra2:dedicated)'  FORMAT'%U_%d'; ALLOCATE CHANNEL c4 DEVICE TYPE sbt_tape PARMS='SBT_LIBRARY=/u01/app/oracle/product/12102/db_1/lib/libra.so,ENV=(RA_WALLET=location=file:/u01/app/oracle/product/12102/db_1/dbs/zdlra credential_alias=slcm03ingest-scan3:1521/zdlra2:dedicated)'  FORMAT'%U_%d'; BACKUP AS BACKUPSET INCREMENTAL LEVEL 1 CUMULATIVE DATABASE INCLUDE CURRENT CONTROLFILE PLUS ARCHIVELOG NOT BACKED UP; } EOF

echo "****************************************************"
echo "*"
echo "* Now we lets to a couple of log switches           "
echo "*"
echo "****************************************************"

function log_switch {
$ORACLE_HOME/bin/sqlplus -s sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 80 feedback off trimspool on heading off feedback off alter system archive log current; exit; EOF }


log_switch
log_switch
log_switch

echo $start_date
$ORACLE_HOME/bin/rman  <<EOF
connect target /
connect catalog rauser12/welcome1@ra_sf
list backup summary completed after "to_date('$start_date','mm/dd/yy hh24:mi:ss')"; list backup of  archivelog from time "to_date('$start_date','mm/dd/yy hh24:mi:ss')" ; exit EOF


function nyc_start {
$ORACLE_HOME/bin/sqlplus -s rasys/ra\@ra_nyc <<EOF set pagesize 999 linesize 999 set heading off set serveroutput on exec dbms_ra.startup; exit EOF }

echo " "
echo " Lets start the NYC Primary RA to see what happens"
echo " "

nyc_start

echo " "
echo " Lets check the status of the NYC RA"
echo " "

nyc_ra_status

echo "           Re-enable primary (LAD) settings "
echo " "
$ORACLE_HOME/bin/sqlplus -s  sys/welcome1@\"${ORACLE_SID}\" as sysdba <<EOF set pagesize 999 linesize 80 feedback off trimspool on heading off feedback off alter system set log_archive_dest_state_2='ENABLE';
exit;
EOF


echo "           Current Log Archive Dest (LAD) settings "
echo "             for database FAILOVER  "
echo " "

log_dest_status



