 /************************************************************************************************************************************
 * Name		: zdlra-client-metrics-catalog.sql
 * Author	: David Robbins, Senior Sales Engineer - Oracle Corporation		  					   
 * Version	: 1.5 (26-FEB-2016)
 * Purpose	: Script to gather information from an RMAN Catalog that will be used to estimate the ZDLRA  					   
 *		  resources that are required to service the databases registered in the catalog.										  					   
 ************************************************************************************************************************************
 *  Disclaimer:
 *  -----------                                                                                                                      
 *  Although this program has been tested and used successfully, it is not supported by Oracle Support Services.                     
 *  It has been tested internally, however, and works as documented. We do not guarantee that it will work for you,                  
 *  so be sure to test it in your environment before relying on it.  We do not clam any responsibility for any problems              
 *  and/or damage caused by this program.  This program comes "as is" and any use of this program is at your own risk!!              
 *  Proofread this script before using it! Due to the differences in the way text editors, e-mail packages and operating systems     
 *  handle text formatting (spaces, tabs and carriage returns).                                                                      
 ************************************************************************************************************************************
 *
 *  Usage:
 *  ------                                                                                                                      
 *  To execute this script, please follow the steps below:                                                                           
 *   1)- Copy this script to the desired location.                                                                                   
 *   2)- OPTIONAL - Modify the file name for the SPOOL file. (Default: zdlra-client-metrics-catalog.lst in the working directory)
 *   2)- Execute the script at the SQL prompt (SQL> @zdlra-client-metrics-catalog.sql) as the RMAN Catalog owner.
 *   3)- Please provide the script's output to the Oracle resource assisting you with ZDLRA sizing.                             	   
 *
 *   This script needs to run in each RMAN Catalog that contains databases that will be migrated to the ZDLRA.
 *
 *   This script will report all databases in the catalog that have had a full, incremental, or achivelog backup in the past 30 days.
 *
 *   *** ANY DATABASE THAT HAS HAD NO BACKUPS IN THE PAST 30 DAYS WILL BE EXCLUDED FROM THE REPORT. ***
 * 
 *   NOTE: If databases without a backup in the past 30 days need to be included, modify the backup_age_limit variable near the top
 *         of the script to reflect the desired number of days to include.
 *
 *   A compression ratio is defined near the top of the DECLARE list. This will be used to estimate the uncompressed size of a full backup
 *   when the backupset sizing method is used and the backupset is compressed. The compression ratio can be manually modified if a better
 *   ratio is known. (See the definition of the Method output column below for more information.)
 *
 *   If any reported databases are not to be included in the sizing, they must be manually deleted from the report 
 *   before sending it the Oracle resource assisting you with the ZDLRA sizing.
 *
 * Definitions of output columns
 * -----------------------------
 *
 * NOTE: An "*" in any column indicates the value was NULL.
 *       If incremntal backups are not being run, redo generation is used for the incremental size.
 *
 * DBID - database id of the database. (Not needed for sizing, but reported for clarification, in case multiple databases have the same name.)
 * DBKey - primary key within the recovery catalog. (Not needed for sizing, but recorded for ease in drilling down into any anomolies in the data.)
 * DBName - database name.
 * DBUnqName - database unique name.
 * DBRole - database role.
 * DB Size GB - Size of the database; not including tempfiles.
 * Method - the method used to caculate the full backup size.
 *   BDF - BLOCKS field from RC_BACKUP_DATAFILE - this is the preferred method
 *   BSET - BYTES field from RC_BACKUP_PIECE - this is used when a datafile is backed up in multiple pieces. The BLOCKS field from RC_BACKUP_DATAFILE is not reliable in these cases.
 *   COMP BSET - BYTES field from RC_BACKUP_PIECE * compression_ratio - this is used if the backupset is compressed. The reported size is an estimate of the uncompressed size.
 * Full GB - Size of a full/incremental level 0 backup. (Does not include empty blocks.)
 * Incr GB/Day - Average daily size of an incremental level 1 backup. 
 * Incr Pct/Day - Ratio of daily size of a level 1 backup to a full/level 0 backup.
 * Redo GB/Day - Average daily redo generation. 
 * Redo Pct/Day - Ration of daily size of redo to a full/level 0 backup.
 * Rcvry Window - Recovery window for the database.
 * Last Full - Date of the last full/level 0 backup.
 * Last Incr - Date of the last incremental level 1 backup.
 * Last Arch - Date of the last archivelog backup.
 * Incr Days - Number of days between the oldest and newest level 1 backup.
 * Arch Days - Number of days between the oldest and newest archivelog backup.
 *
 ************************************************************************************************************************************/
 
SET SERVEROUTPUT ON
SET LINES 260 TRIMS ON
SET TIMING ON
SET FEEDBACK OFF

SPOOL zdlra-client-metrics-catalog.lst

DECLARE
  backup_age_limit              CONSTANT NUMBER := 30;
  compression_ratio             CONSTANT NUMBER := 5;
  script_version                CONSTANT VARCHAR2(30) := '1.5 - 26-FEB-2016 ';
  db_size_bytes                 NUMBER;
  db_full_backup_bytes          NUMBER;
  cf_total_bytes                NUMBER;
  full_backup_bytes             NUMBER;
  full_backupset_bytes          NUMBER;
  incr_history_days             NUMBER;
  incr_backup_bytes_per_day     NUMBER;
  incr_backup_pct               NUMBER;
  redo_bytes_per_day            NUMBER;
  redo_pct                      NUMBER;
  recovery_window_days          NUMBER;
  incr_days                     NUMBER;
  arch_days                     NUMBER;
  db_tot_cnt                    NUMBER := 0;
  db_rpt_cnt                    NUMBER := 0;
  incr_begin_date               DATE;
  incr_end_date                 DATE;
  min_completion_time           DATE;
  max_completion_time           DATE;
  full_last_completion_time     DATE;
  incr_last_completion_time     DATE;
  arch_last_completion_time     DATE;
  max_last_completion_time      DATE;
  begin_time                    DATE;
  cat_dbname                    VARCHAR2(30);
  cat_host                      VARCHAR2(30);
  cat_schema                    VARCHAR2(30);
  pieces                        NUMBER;

  db_size_bytes_out             VARCHAR2(20);
  full_backup_bytes_out         VARCHAR2(20);
  full_backupset_bytes_out      VARCHAR2(20);
  incr_backup_bytes_per_day_out VARCHAR2(20);
  incr_backup_pct_out           VARCHAR2(20);
  redo_bytes_per_day_out        VARCHAR2(20);
  redo_pct_out                  VARCHAR2(20);
  recovery_window_days_out      VARCHAR2(20);
  full_last_completion_time_out	VARCHAR2(20);
  incr_last_completion_time_out	VARCHAR2(20);
  arch_last_completion_time_out	VARCHAR2(20);
  incr_days_out                 VARCHAR2(20);
  arch_days_out                 VARCHAR2(20);
  method_out                    VARCHAR2(9);
  
  CURSOR databases IS 
    SELECT rd.db_key,
           rd.dbid,
           rd.name,
           rs.db_unique_name,
           rs.database_role
      FROM
           rc_database rd,
           rc_site rs
     WHERE rd.db_key = rs.db_key
    ORDER BY rs.database_role,
             rd.name,
             rs.db_unique_name,
             dbid;

BEGIN
  -- Record the begin time
  begin_time := SYSDATE;

  -- Record catalog information
 SELECT sys_context('userenv','db_name'),
        sys_context('userenv', 'server_host'),
        sys_context ('userenv', 'session_user')
   INTO cat_dbname,
        cat_host,
        cat_schema
   FROM dual;

  -- Write out the report header
  dbms_output.put_line('********* Start of ZDLRA Client Sizing Metrics ****************');
  dbms_output.put_line(RPAD('-',234,'-'));
  dbms_output.put_line(RPAD('|DBID',16)||'|'||
                       RPAD('DBKey',15)||'|'||
                       RPAD('DBName',8)||'|'||
                       RPAD('DBUnqName',30)||'|'||
                       RPAD('DBRole',7)||'|'||
                       LPAD('DB Size GB',11)||'|'||
                       LPAD('Full GB',11)||'|'||
                       LPAD('Method',9)||'|'||
                       LPAD('Incr GB/Day',11)||'|'||
                       LPAD('Incr Pct/Day',12)||'|'||
                       LPAD('Redo GB/Day',11)||'|'||
                       LPAD('Redo Pct/Day',12)||'|'||
                       LPAD('Rcvry Window',12)||'|'||
                       LPAD('Last Full',11)||'|'||
                       LPAD('Last Incr',11)||'|'||
                       LPAD('Last Arch',11)||'|'||
                       LPAD('Incr Days',9)||'|'||
                       LPAD('Arch Days',9)||'|');
  dbms_output.put_line(RPAD('-',234,'-'));

--Gather protected database information 
  FOR d in databases LOOP
    -- Initialize all variables to null
    db_full_backup_bytes := '';
    db_size_bytes := '';
    cf_total_bytes := '';
    full_backup_bytes := '';
    full_backupset_bytes :='';
    pieces := '';
    incr_history_days := '';
    incr_backup_bytes_per_day := '';
    incr_backup_pct := '';
    redo_bytes_per_day := '';
    redo_pct := '';
    recovery_window_days := '';
    incr_begin_date := '';
    incr_end_date := '';
    full_last_completion_time := '';
    incr_last_completion_time := '';
    arch_last_completion_time := '';
    max_last_completion_time := '';
    incr_days := '';
    arch_days := '';
    method_out := 'BDF';

    -- Get the latest full backup size, based on actual blocks written per datafile to the backup;
    -- not the size of the datafile itself. This method does not count empty blocks that have never 
    -- contained data.
    SELECT SUM(rbd.blocks * rbd.block_size),
           SUM(rbd.datafile_blocks * rbd.block_size),
           MAX(pieces),
           MAX(rbd.completion_time)
      INTO db_full_backup_bytes,
           db_size_bytes,
	   pieces,
           full_last_completion_time
      FROM rc_backup_datafile rbd,
           (SELECT file#,
                   MAX(completion_time) completion_time
              FROM rc_backup_datafile
             WHERE db_key = d.db_key
               AND (incremental_level = 0 OR incremental_level IS NULL)
             GROUP BY file#) mct
     WHERE db_key = d.db_key
       AND rbd.file# = mct.file#
       AND rbd.completion_time = mct.completion_time
       AND (rbd.incremental_level = 0 OR rbd.incremental_level IS NULL);
	   
	-- The blocks column in rc_backup_datafile is not reliable for multi-piece backups. So, use the backupset size. 
	-- If the backupset is compressed, use a standard compression ratio to report an estimated uncompressed size.
	
	IF pieces > 1 THEN
	  SELECT SUM(bytes * TO_NUMBER(DECODE(compressed,'YES',compression_ratio,'NO','1','1'))),
	         DECODE(MAX(compressed),'YES','COMP BSET','NO','BSET','BSET')
	    INTO db_full_backup_bytes,
	         method_out
	    FROM rc_backup_piece
	   WHERE bs_key IN (SELECT bs_key
	                      FROM rc_backup_datafile rbd,
                               (SELECT file#,
                                       MAX(completion_time) completion_time
                                  FROM rc_backup_datafile
                                 WHERE db_key = d.db_key
                                   AND (incremental_level = 0 OR incremental_level IS NULL)
                                GROUP BY file#) mct
                         WHERE db_key = d.db_key
                           AND rbd.file# = mct.file#
                           AND rbd.completion_time = mct.completion_time
                           AND (rbd.incremental_level = 0 OR rbd.incremental_level IS NULL));
	END IF;

    -- Track last completion of any type of backup for excluding old backups from the report.
    max_last_completion_time := full_last_completion_time;

    -- Get the size of the controlfile backup.
    SELECT MAX(blocks * block_size)
      INTO cf_total_bytes
      FROM rc_backup_controlfile
     WHERE db_key = d.db_key;

    -- Add the size of the latest full backup and controlfile backup
    full_backup_bytes := db_full_backup_bytes + cf_total_bytes;

    -- Get the average daily size of the incremental backups.	
     SELECT SUM(avg_incr_bytes),
            MAX(max_completion_time),
            ROUND(MAX(incr_days),0)
       INTO incr_backup_bytes_per_day,
            incr_last_completion_time,
            incr_days
       FROM (SELECT file#,
                    SUM(incr_bytes) / SUM(incr_days) AS avg_incr_bytes,
                    MAX(completion_time) AS max_completion_time,
                    SUM(incr_days) AS incr_days
               FROM (SELECT rbd.file#,
                            SUM(blocks * block_size) AS incr_bytes,
                            MAX(rbd.completion_time) AS completion_time,
                            MAX(rbd.completion_time) - fct.last_full_time AS incr_days    
                       FROM rc_backup_datafile rbd,
                            (SELECT file#, 
                                    db_key,
                                    completion_time AS last_full_time,
                                    LEAD(rbd.completion_time, 1, SYSDATE) OVER (PARTITION BY rbd.file# ORDER BY rbd.completion_time) AS next_full_time
                               FROM rc_backup_datafile rbd
                              WHERE db_key = d.db_key
                                AND (incremental_level = 0 OR incremental_level IS NULL)
                                AND rbd.completion_time >= SYSDATE - backup_age_limit) fct
                      WHERE rbd.db_key = fct.db_key
                        AND rbd.file# = fct.file#
                        AND rbd.incremental_level = 1
                        AND rbd.completion_time BETWEEN fct.last_full_time AND fct.next_full_time
                     GROUP BY rbd.file#,
                              fct.last_full_time,
                              fct.next_full_time) 
             GROUP BY file#)
;
    -- Track last completion of any type of backup for excluding old backups from the report.
    IF incr_last_completion_time > max_last_completion_time THEN
      max_last_completion_time := incr_last_completion_time;
    END IF;

    -- Get the average daily redo generation
    SELECT SUM(blocks*block_size) / GREATEST(MAX(next_time) - MIN(first_time),1),
           MAX(next_time),
           ROUND(GREATEST(MAX(next_time) - MIN(first_time),1),0)
      INTO redo_bytes_per_day,
           arch_last_completion_time,
           arch_days
      FROM rc_backup_redolog 
     WHERE db_key = d.db_key
       AND first_time >= SYSDATE - backup_age_limit;

    -- Track last completion of any type of backup for excluding old backups from the report.
    IF arch_last_completion_time > max_last_completion_time THEN
      max_last_completion_time := arch_last_completion_time;
    END IF;

    -- Get the recovery window
    SELECT MAX(TO_NUMBER(REGEXP_SUBSTR(value, '([[:digit:]]+)', 1, 1)))
      INTO recovery_window_days
      FROM rc_rman_configuration 
     WHERE db_key = d.db_key
       AND  name = 'RETENTION POLICY';

    -- Use the redo generation for incremental, if incrementals are not being run
    IF incr_backup_bytes_per_day IS NULL THEN
      incr_backup_bytes_per_day := redo_bytes_per_day;
    END IF;

    -- Calculate the incremental change percentage
    IF incr_backup_bytes_per_day IS NOT NULL THEN
      incr_backup_pct := ROUND(incr_backup_bytes_per_day / full_backup_bytes * 100,2);
    END IF;
    
    -- Calculate the redo percentage
    IF redo_bytes_per_day IS NOT NULL THEN
      redo_pct := ROUND(redo_bytes_per_day / full_backup_bytes * 100,2);
    END IF;
    
    -- Convert all bytes to GB
    IF db_size_bytes IS NOT NULL THEN
      db_size_bytes := ROUND(db_size_bytes/POWER(1024,3),3);
    END IF;

    IF full_backup_bytes IS NOT NULL THEN
      full_backup_bytes := ROUND(full_backup_bytes/POWER(1024,3),3);
    END IF;
	
	IF full_backupset_bytes IS NOT NULL THEN
      full_backupset_bytes := ROUND(full_backupset_bytes/POWER(1024,3),3);
    END IF;

    IF incr_backup_bytes_per_day IS NOT NULL THEN
      incr_backup_bytes_per_day := ROUND(incr_backup_bytes_per_day/POWER(1024,3),3);
    END IF;

    IF redo_bytes_per_day IS NOT NULL THEN
      redo_bytes_per_day := ROUND(redo_bytes_per_day/POWER(1024,3),3);
    END IF;

    -- Convert values to character for output, ensuring null values are handled for reporting purposes
    IF db_size_bytes IS NOT NULL THEN
      db_size_bytes_out := TO_CHAR(db_size_bytes);
    ELSE
      db_size_bytes_out := '*';
    END IF;

    IF full_backup_bytes IS NOT NULL THEN
      full_backup_bytes_out := TO_CHAR(full_backup_bytes);
    ELSE
      full_backup_bytes_out := '*';
    END IF;
	
	IF full_backupset_bytes IS NOT NULL THEN
      full_backupset_bytes_out := TO_CHAR(full_backupset_bytes);
    ELSE
      full_backupset_bytes_out := '*';
    END IF;

    IF incr_backup_bytes_per_day IS NOT NULL THEN
      incr_backup_bytes_per_day_out := TO_CHAR(incr_backup_bytes_per_day);
    ELSE
      incr_backup_bytes_per_day_out := '*';
    END IF;

    IF incr_backup_pct IS NOT NULL THEN
      incr_backup_pct_out := TO_CHAR(incr_backup_pct);
    ELSE
      incr_backup_pct_out := '*';
    END IF;

    IF recovery_window_days IS NOT NULL THEN
      recovery_window_days_out := TO_CHAR(recovery_window_days);
    ELSE
      recovery_window_days_out := '*';
    END IF;

    IF redo_bytes_per_day IS NOT NULL THEN
      redo_bytes_per_day_out := TO_CHAR(redo_bytes_per_day);
    ELSE
      redo_bytes_per_day_out := '*';
    END IF;

    IF redo_pct IS NOT NULL THEN
      redo_pct_out := TO_CHAR(redo_pct);
    ELSE
      redo_pct_out := '*';
    END IF;

    IF full_last_completion_time IS NOT NULL THEN
      full_last_completion_time_out := TO_CHAR(full_last_completion_time,'DD-MON-YYYY');
    ELSE
      full_last_completion_time_out := '*';
    END IF;

    IF incr_last_completion_time IS NOT NULL THEN
      incr_last_completion_time_out := TO_CHAR(incr_last_completion_time,'DD-MON-YYYY');
    ELSE
      incr_last_completion_time_out := '*';
    END IF;

    IF arch_last_completion_time IS NOT NULL THEN
      arch_last_completion_time_out := TO_CHAR(arch_last_completion_time,'DD-MON-YYYY');
    ELSE
      arch_last_completion_time_out := '*';
    END IF;

    IF arch_days IS NOT NULL THEN
      arch_days_out := TO_CHAR(arch_days);
    ELSE
      arch_days_out := '*';
    END IF;

    IF incr_days IS NOT NULL THEN
      incr_days_out := TO_CHAR(incr_days);
    ELSE
      incr_days_out := '*';
    END IF;

    -- Output the data
    IF max_last_completion_time >= SYSDATE - backup_age_limit THEN
      dbms_output.put_line('|'||RPAD(d.dbid,15)||'|'||
                           RPAD(d.db_key,15)||'|'||
                           RPAD(d.name,8)||'|'||
                           RPAD(d.db_unique_name,30)||'|'||
                           RPAD(d.database_role,7)||'|'||
                           LPAD(db_size_bytes_out,11)||'|'||
                           LPAD(full_backup_bytes_out,11)||'|'||
                           RPAD(method_out,9)||'|'||
                           LPAD(incr_backup_bytes_per_day_out,11)||'|'||
                           LPAD(incr_backup_pct_out,12)||'|'||
                           LPAD(redo_bytes_per_day_out,11)||'|'||
                           LPAD(redo_pct_out,12)||'|'||
                           LPAD(recovery_window_days_out,12)||'|'||
                           LPAD(full_last_completion_time_out,11)||'|'||
                           LPAD(incr_last_completion_time_out,11)||'|'||
                           LPAD(arch_last_completion_time_out,11)||'|'||
                           LPAD(incr_days_out,9)||'|'||
                           LPAD(arch_days_out,9)||'|');
      db_rpt_cnt := db_rpt_cnt + 1;
    ELSE
      db_tot_cnt := db_tot_cnt + 1;
    END IF;
  END LOOP;
  dbms_output.put_line(RPAD('-',234,'-'));
  dbms_output.put_line('********* End of ZDLRA Client Sizing Metrics ****************');
  dbms_output.put_line('Catalog schema        : '||cat_schema);
  dbms_output.put_line('Catalog database      : '||cat_dbname);
  dbms_output.put_line('Catalog host          : '||cat_host);
  dbms_output.put_line('Begin time            : '||TO_CHAR(begin_time,'DD-MON-YYYY HH24:MI:SS'));
  dbms_output.put_line('End time              : '||TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  dbms_output.put_line('Databases reported    : '||db_rpt_cnt);
  dbms_output.put_line('Databases not reported: '||db_tot_cnt||' (No backups in past '||backup_age_limit||' days.)');
  dbms_output.put_line('Script version        : '||script_version);
END;
/
EXIT
