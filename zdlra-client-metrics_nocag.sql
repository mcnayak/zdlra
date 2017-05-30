prompt ####################################################################################################################################
prompt # Author        : Oracle High Availability Systems Development, Server Technologies - Oracle Corporation		  					   
prompt # Version       : 1.4																						  					   
prompt # Purpose       : Script to gather information from a client database that will be used to estimate the ZDLRA  					   
prompt #     			 resources that are required to service this database.										  					   
prompt ####################################################################################################################################
prompt #  Disclaimer:																													   
prompt #  -----------                                                                                                                      
prompt #  Although this program has been tested and used successfully, it is not supported by Oracle Support Services.                     
prompt #  It has been tested internally, however, and works as documented. We do not guarantee that it will work for you,                  
prompt #  so be sure to test it in your environment before relying on it.  We do not clam any responsibility for any problems              
prompt #  and/or damage caused by this program.  This program comes "as is" and any use of this program is at your own risk!!              
prompt #  Proofread this script before using it! Due to the differences in the way text editors, e-mail packages and operating systems     
prompt #  handle text formatting (spaces, tabs and carriage returns).                                                                      
prompt ####################################################################################################################################
prompt #  Usage:																														   
prompt #  -----------                                                                                                                      
prompt #  To execute this script, please follow the steps below:                                                                           
prompt #   1)- Copy this script to the desired location.                                                                                   
prompt #   2)- Execute the script at the SQL prompt (SQL> @zdlra-client-metrics.sql) as a privileged user.                                 
prompt #   3)- Please provide the script's output to the Oracle resource assisting you with ZDLRA sizing.                             	   
prompt #   This script needs to run individually on each database that you are planning to configure with ZDLRA.                           
prompt ####################################################################################################################################
 
SET SERVEROUTPUT ON
DECLARE
  dbcf_total_bytes              NUMBER;
  db_free_bytes                 NUMBER;
  db_incr_history_days          NUMBER;
  db_incr_backup_bytes_per_day  NUMBER;
  db_incr_backup_pct            NUMBER;
  protdb_recovery_window_days   NUMBER;
  redo_backup_bytes_per_day     NUMBER;
  online_redo_bytes             NUMBER;
  db_total_blocks               NUMBER;
  db_free_blocks                NUMBER;
  protdb_name                   V$DATABASE.NAME%TYPE;
  PROCEDURE Pv(n IN VARCHAR2, v IN NUMBER) IS
  BEGIN
    dbms_output.Put_line(n || '=' || v);
  END;
BEGIN
  dbms_output.Put_line('********* Start of ZDLRA Client Sizing Metrics ****************');
/*Gather protected database information */
  SELECT NAME
    INTO protdb_name
    FROM V$DATABASE;

  SELECT (SELECT SUM(bytes) FROM DBA_DATA_FILES) +
         (SELECT block_size * file_size_blks
            FROM V$CONTROLFILE
           WHERE status IS NULL
             AND ROWNUM = 1)
    INTO dbcf_total_bytes
    FROM DUAL;

  SELECT SUM(bytes), SUM(blocks)
    INTO db_free_bytes, db_free_blocks
    FROM DBA_FREE_SPACE;

  SELECT Trunc(SUM(block_size * blocks) /
               (Max(Trunc(completion_time)) - Min(Trunc(completion_time))))
    INTO db_incr_backup_bytes_per_day
    FROM V$BACKUP_DATAFILE
   WHERE incremental_level = 1;

SELECT min(TO_NUMBER(REGEXP_SUBSTR(value, '([[:digit:]]+)', 1, 1))) 
 INTO protdb_recovery_window_days
  FROM V$RMAN_CONFIGURATION
 WHERE name = 'RETENTION POLICY';

  SELECT Trunc(Avg(day_redo_size))
    INTO redo_backup_bytes_per_day
    FROM (SELECT day_finished, SUM(block_size * blocks) day_redo_size
            FROM (SELECT Max(block_size) block_size,
                         Max(blocks) blocks,
                         Max(Trunc(completion_time)) day_finished
                    FROM V$ARCHIVED_LOG al
                   GROUP BY thread#, sequence#)
           GROUP BY day_finished);

/*Display protected database information */
  dbms_output.Put_line('* Protected Database name                              ='||protdb_name);

  Pv('* datafile_full_backup_bytes - Database Size (TB)      ',
     ROUND((dbcf_total_bytes - db_free_bytes)/POWER(1024,4),6));

  Pv('* db_incr_backup_bytes_per_day - Incremental Size (TB) ', round((db_incr_backup_bytes_per_day)/POWER(1024,4),6));
  IF db_incr_backup_bytes_per_day IS NULL THEN
    dbms_output.Put_line('* NO RMAN INCREMENTALS. NEED CUSTOMER ESTIMATE OF DAILY CHANGE RATE.');
  END IF;

  db_incr_backup_pct := round((db_incr_backup_bytes_per_day /
                              (dbcf_total_bytes - db_free_bytes)) * 100,
                              2);
  Pv('* db_incr_backup_pct - Incremental Size Pct (%)        ', db_incr_backup_pct);
  IF db_incr_backup_pct = 0 THEN
    dbms_output.Put_line('* NO RMAN INCREMENTALS. NEED CUSTOMER ESTIMATE OF DAILY CHANGE RATE.');
  END IF;

  Pv('* protdb_recovery_window_days -(Backup Retention)      ', protdb_recovery_window_days);
  IF protdb_recovery_window_days IS NULL THEN
    dbms_output.Put_line('* NO RMAN RECOVERY WINDOW. NEED CUSTOMER RECOVERY WINDOW.');
  END IF;

  Pv('* redo_backup_bytes_per_day - Archive Log Size (TB)    ', ROUND((redo_backup_bytes_per_day)/POWER(1024,4),6));
  dbms_output.Put_line('********* End of ZDLRA Client Sizing Metrics ******************');
END;
/