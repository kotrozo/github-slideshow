/*==============================================================================
  _inspect_EnsembleVisitOwner.sql
  Server : schcent20db01
  Purpose: Dump the definition of the existing SQL Agent job "EnsembleVisitOwner"
           so the new job (Ensemble_SCMGCodingWorklists) can be built to match.

  Run this FIRST. Read the output, then run Ensemble_SCMGCodingWorklists.sql.
  Read-only - this script changes nothing.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

DECLARE @SourceJob sysname = N'EnsembleVisitOwner';

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
BEGIN
    PRINT '*** Job "' + @SourceJob + '" not found under that exact name.';
    PRINT '*** Similar job names on this instance:';
    SELECT name, enabled, date_created, date_modified
    FROM   msdb.dbo.sysjobs
    WHERE  name LIKE '%Ensemble%'
    ORDER  BY name;
    RETURN;
END

/*--- 1. Job header: owner, category, notifications --------------------------*/
SELECT  [Section]      = '1. Job header',
        j.name,
        j.enabled,
        j.description,
        Category       = c.name,
        Owner          = SUSER_SNAME(j.owner_sid),
        j.notify_level_email,
        NotifyOperator = o.name,
        OperatorEmail  = o.email_address,
        j.notify_level_eventlog,
        j.date_created,
        j.date_modified
FROM    msdb.dbo.sysjobs        j
LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
LEFT JOIN msdb.dbo.sysoperators  o ON o.id          = j.notify_email_operator_id
WHERE   j.name = @SourceJob;

/*--- 2. Job steps: this is where the sp_send_dbmail call lives --------------*/
/*     Look for: @profile_name, @recipients, @query_result_separator,         */
/*               @query_attachment_filename, and the target database.         */
SELECT  [Section]  = '2. Job steps',
        s.step_id,
        s.step_name,
        SubSystem  = s.subsystem,
        TargetDb   = s.database_name,
        s.on_success_action,
        s.on_fail_action,
        s.retry_attempts,
        s.output_file_name,
        s.command
FROM    msdb.dbo.sysjobs      j
JOIN    msdb.dbo.sysjobsteps  s ON s.job_id = j.job_id
WHERE   j.name = @SourceJob
ORDER BY s.step_id;

/*--- 3. Schedule ------------------------------------------------------------*/
/*     freq_type: 1=Once 4=Daily 8=Weekly 16=Monthly 32=MonthlyRelative       */
/*     active_start_time is HHMMSS as an int (e.g. 60000 = 06:00:00)          */
SELECT  [Section] = '3. Schedule',
        sch.name  AS schedule_name,
        sch.enabled,
        sch.freq_type,
        sch.freq_interval,
        sch.freq_subday_type,
        sch.freq_subday_interval,
        sch.freq_relative_interval,
        sch.freq_recurrence_factor,
        sch.active_start_date,
        sch.active_start_time,
        StartTimeReadable = STUFF(STUFF(RIGHT('000000'
              + CAST(sch.active_start_time AS varchar(6)), 6), 5, 0, ':'), 3, 0, ':')
FROM    msdb.dbo.sysjobs          j
JOIN    msdb.dbo.sysjobschedules  js  ON js.job_id      = j.job_id
JOIN    msdb.dbo.sysschedules     sch ON sch.schedule_id = js.schedule_id
WHERE   j.name = @SourceJob;

/*--- 4. Database Mail profiles available on this instance -------------------*/
SELECT  [Section] = '4. Mail profiles',
        p.name    AS profile_name,
        p.description,
        IsDefaultForGuest = CASE WHEN pp.is_default = 1 THEN 'yes' ELSE 'no' END
FROM    msdb.dbo.sysmail_profile p
LEFT JOIN msdb.dbo.sysmail_principalprofile pp ON pp.profile_id = p.profile_id
ORDER BY p.name;

/*--- 5. Recent run history for the source job -------------------------------*/
SELECT TOP (10)
        [Section]  = '5. Recent history',
        RunDate    = h.run_date,
        RunTime    = h.run_time,
        Outcome    = CASE h.run_status WHEN 0 THEN 'Failed'
                                       WHEN 1 THEN 'Succeeded'
                                       WHEN 2 THEN 'Retry'
                                       WHEN 3 THEN 'Canceled'
                                       ELSE 'In progress' END,
        h.message
FROM    msdb.dbo.sysjobs        j
JOIN    msdb.dbo.sysjobhistory  h ON h.job_id = j.job_id
WHERE   j.name = @SourceJob
  AND   h.step_id = 0
ORDER BY h.run_date DESC, h.run_time DESC;
GO
