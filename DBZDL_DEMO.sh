#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/11.2.0.4/dbhome_1
export ORACLE_SID=dbnzdl
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH

function get_final_change_num {
$ORACLE_HOME/bin/sqlplus -s rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2 <<EOF2 set pagesize 999 linesize 999 heading off feedback off select final_change# from rc_database where name='DBNZDL'; exit;
EOF2
}

echo "Oracle Zero Data Loss Recovery Appliance Provides Zero Data Loss RECOVERY"

echo
echo
echo "This database is protected by the Oracle Zero Data Loss Recovery Appliance."
echo "Let's view the content of the database and insert a row into a new table."
echo " "
echo " "

sleep 3

#$ORACLE_HOME/bin/sqlplus  -s '/ as sysdba' <<EOF #set pagesize 999 linesize 80 feedback off trimspool on #set echo on #col name heading "DB Name"
#col current_scn heading "Current SCN"
#col time format a34 heading "SCN_to_TimeStamp"
#select name,current_scn,scn_to_timestamp(current_scn) Time from v\$database; #exit; #EOF

echo
echo
echo "Now we will insert a row in a table."
echo

sleep 2 

#$ORACLE_HOME/bin/sqlplus '/ as sysdba' <<EOF #set pagesize 999 linesize 999 echo on feedback off #select name, insert_time from customer; #exit; #EOF

##read -p "Enter your name and press <enter>: " name

$ORACLE_HOME/bin/sqlplus '/ as sysdba' <<EOF set pagesize 999 linesize 999 echo on feedback off insert into customer (name,insert_time) values ('Test For ZDL',systimestamp); commit; exit; EOF

sleep 2

$ORACLE_HOME/bin/sqlplus '/ as sysdba' <<EOF set pagesize 999 linesize 999 echo on feedback off select name, insert_time from customer; exit; EOF

sleep 1 

$ORACLE_HOME/bin/sqlplus  -s '/ as sysdba' <<EOF set pagesize 999 linesize 80 feedback off trimspool on set echo on col name heading "DB Name"
col current_scn heading "Current SCN"
col time format a34 heading "SCN_to_TimeStamp"
select name,current_scn,scn_to_timestamp(current_scn) Time from v\$database; exit; EOF


sleep 2

echo " "
echo "Let's now crash the database and remove all database files. "
echo " "
echo " "

##read -p "Crashing the database!!! - Please press <enter> to continue"

sqlplus -s '/ as sysdba' <<EOF
set pagesize 999 linesize 80 feedback on trimspool on shutdown abort; exit; EOF

echo
echo

sleep 2
echo "Removing all database files!!!" 
sleep 2

export ORACLE_HOME=/u01/app/12.1.0.1/grid
export ORACLE_SID=+ASM
export PATH=/u01/app/12.1.0.1/grid/bin:$PATH

echo "Listing files"
echo
/u01/app/12.1.0.1/grid/bin/asmcmd <<EOF
ls -l  +data/dbnzdl/controlfile/*
ls -l  +data/dbnzdl/datafile/*
ls -l  +data/dbnzdl/onlinelog/*
ls -l  +reco/dbnzdl/onlinelog/*
EOF

echo
echo
echo "Deleting files"
sleep 2

asmcmd <<EOF
rm -rf +data/dbnzdl/controlfile/*
rm -rf +data/dbnzdl/datafile/*
rm -rf +data/dbnzdl/onlinelog/*
rm -rf +reco/dbnzdl/onlinelog/*
EOF

echo
echo
echo "Files removed"
sleep 2
asmcmd <<EOF
ls -l  +data/dbnzdl/controlfile/*
ls -l  +data/dbnzdl/datafile/*
ls -l  +data/dbnzdl/onlinelog/*
ls -l  +reco/dbnzdl/onlinelog/*
EOF


sleep 2
export ORACLE_HOME=/u01/app/oracle/product/11.2.0.4/dbhome_1
export ORACLE_SID=dbnzdl
export PATH=$PATH:$HOME/bin:$ORACLE_HOME/bin:$ORACLE_HOME/Opatch
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$ORACLE_HOME/rdbms/lib:/lib:/usr/lib; export LD_LIBRARY_PATH

echo
echo
echo "Restore and recover the database using the Oracle Zero Data Loss Recovery Appliance"
echo " "
echo " "

sleep 5

echo
echo

$ORACLE_HOME/bin/rman target / catalog rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2 <<EOF startup force nomount; set dbid=1107973384; restore controlfile; alter database mount; exit; EOF

 
sleep 5

echo
echo

until_scn=$(get_final_change_num)

$ORACLE_HOME/bin/rman target / catalog rauser11/welcome1@//slcm03ingest-scan3:1521/zdlra2 <<EOF run {
     set until scn $until_scn;
     restore database;
     recover database;
    }
exit;
EOF

echo
echo
    
sleep 2
echo "Opening the database resetlogs, comparing SCNs and checking for committed row" 
sleep 5

echo
echo

##echo "Last SCN before crash =  $until_scn " 
##echo
##echo
sleep 3
$ORACLE_HOME/bin/sqlplus -s '/ as sysdba' <<EOF set pagesize 999 linesize 999 echo off feedback off alter database open resetlogs; select RESETLOGS_CHANGE# from v\$database; exit; EOF

echo
echo
sleep 2

echo "What about the data we inserted just prior to the crash?"

$ORACLE_HOME/bin/sqlplus '/ as sysdba' <<EOF set pagesize 999 linesize 999 echo on feedback off select name, insert_time from customer; exit; EOF

echo
echo
sleep 3

echo "Zero Data Loss Demo completed."

##read -p "Please press <enter> to exit  "

echo " "
echo " "


sleep 5

echo "Calling backup database DBNZDL Script..."
sleep 2
/bin/sh /home/oracle/BKP_INCRL0_DBNZDL.sh

