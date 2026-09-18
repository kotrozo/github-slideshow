/*==============================================================================
  Ensemble_SCMGCodingWorklistsDaily.sql
  Server  : schcent20db01
  Creates : SQL Agent job "Ensemble_SCMGCodingWorklistsDaily"

  Runs DAILY at 04:00 and emails the SCMG coding worklist as a dated .csv.

  Distribution
  ------------
  To : Kristie Stuber, Holly Aguilar, Heather Russell, Jessica Apolito
       (all @ensemblehp.com)
  Cc : Dan Krchmar, and you

  The two Cc addresses are placeholders. The script REFUSES to run until they
  are filled in - this report goes to an external vendor domain, so it should
  not send with the Cc list half-configured.

  Before you run it
  -----------------
  1. Fill in @CcDanKrchmar and @CcSelf below.
  2. @DatabaseName: several databases on this instance contain
     PatientVisit/PatientProfile/MedLists, so it cannot be auto-detected.
     Set it explicitly. To list the candidates:

        SELECT d.name
        FROM   sys.databases d
        WHERE  d.state = 0 AND d.database_id > 4
          AND  OBJECT_ID(QUOTENAME(d.name) + '.dbo.PatientVisit')   IS NOT NULL
          AND  OBJECT_ID(QUOTENAME(d.name) + '.dbo.PatientProfile') IS NOT NULL
          AND  OBJECT_ID(QUOTENAME(d.name) + '.dbo.MedLists')       IS NOT NULL;

  Mail profile, owner, category and the failure-alert operator are inherited
  from JK_EnsembleVisitOwner.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

/*==============================================================================
  SETTINGS
==============================================================================*/
DECLARE @JobName         sysname = N'Ensemble_SCMGCodingWorklistsDaily',
        @SourceJob       sysname = N'JK_EnsembleVisitOwner',
        @JobEnabled      tinyint = 1,
        @ReplaceExisting bit     = 0,   -- 1 = drop + recreate if it exists
        @UseCsvSafeQuery bit     = 1;   -- 1 = quote/escape text columns

/*---- REQUIRED ------------------------------------------------------------*/
DECLARE @DatabaseName sysname = NULL,   -- e.g. N'Intergy' - see header
        @CcDanKrchmar sysname = N'<<SET_DAN_KRCHMAR_EMAIL>>',
        @CcSelf       sysname = N'<<SET_YOUR_EMAIL>>';

/*---- OPTIONAL OVERRIDES: leave NULL to inherit ---------------------------*/
DECLARE @MailProfile  sysname = NULL,
        @CategoryName sysname = NULL,
        @OwnerLogin   sysname = NULL;

/*---- schedule: daily at 04:00 --------------------------------------------*/
DECLARE @ActiveStartTime int = 40000;   -- HHMMSS

DECLARE @ToList nvarchar(max) =
        N'Kristie.Stuber@ensemblehp.com;Holly.Aguilar@ensemblehp.com;'
      + N'Heather.Russell@ensemblehp.com;Jessica.Apolito@ensemblehp.com';

/*==============================================================================
  INHERIT FROM THE SOURCE JOB
==============================================================================*/
DECLARE @SrcCmd      nvarchar(max),
        @SrcDb       sysname,
        @SrcQueryDb  sysname,
        @SrcProfile  sysname,
        @SrcCategory sysname,
        @SrcOwner    sysname,
        @SrcOperator sysname,
        @SrcNotifyEmail    tinyint,
        @SrcNotifyEventlog tinyint,
        @q1 int, @q2 int;

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
   AND (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%') = 1
    SELECT @SourceJob = name FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%';

SELECT TOP (1)
        @SrcDb  = NULLIF(s.database_name, N''),
        @SrcCmd = s.command
FROM    msdb.dbo.sysjobs     j
JOIN    msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE   j.name = @SourceJob
ORDER BY s.step_id;

SELECT  @SrcCategory       = c.name,
        @SrcOwner          = SUSER_SNAME(j.owner_sid),
        @SrcOperator       = o.name,
        @SrcNotifyEmail    = j.notify_level_email,
        @SrcNotifyEventlog = j.notify_level_eventlog
FROM    msdb.dbo.sysjobs        j
LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
LEFT JOIN msdb.dbo.sysoperators  o ON o.id          = j.notify_email_operator_id
WHERE   j.name = @SourceJob;

IF @SrcOperator IS NULL SET @SrcNotifyEmail = 0;
SET @SrcNotifyEmail    = ISNULL(@SrcNotifyEmail, 0);
SET @SrcNotifyEventlog = ISNULL(@SrcNotifyEventlog, 0);

/* the source is an SSIS job, so there is no @profile_name literal to parse;
   fall back to the instance default Database Mail profile */
IF @SrcCmd IS NOT NULL
BEGIN
    SET @q1 = CHARINDEX(N'@execute_query_database', @SrcCmd);
    IF @q1 > 0
    BEGIN
        SET @q1 = CHARINDEX(N'''', @SrcCmd, @q1);
        IF @q1 > 0
        BEGIN
            SET @q2 = CHARINDEX(N'''', @SrcCmd, @q1 + 1);
            IF @q2 > @q1 SET @SrcQueryDb = SUBSTRING(@SrcCmd, @q1 + 1, @q2 - @q1 - 1);
        END
    END
END

IF @SrcDb IN (N'msdb', N'master', N'model', N'tempdb') SET @SrcDb = NULL;
IF @SrcQueryDb IS NOT NULL AND DB_ID(@SrcQueryDb) IS NULL SET @SrcQueryDb = NULL;
SET @SrcDb = COALESCE(@SrcQueryDb, @SrcDb);

SELECT TOP (1) @SrcProfile = p.name
FROM   msdb.dbo.sysmail_profile           p
JOIN   msdb.dbo.sysmail_principalprofile pp ON pp.profile_id = p.profile_id
WHERE  pp.is_default = 1;

IF @SrcProfile IS NULL AND (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) = 1
    SELECT @SrcProfile = name FROM msdb.dbo.sysmail_profile;

SELECT  @DatabaseName = COALESCE(@DatabaseName, @SrcDb),
        @MailProfile  = COALESCE(@MailProfile,  @SrcProfile),
        @CategoryName = COALESCE(@CategoryName, @SrcCategory, N'[Uncategorized (Local)]'),
        @OwnerLogin   = COALESCE(@OwnerLogin,   @SrcOwner,    SUSER_SNAME());

/*==============================================================================
  VALIDATE
==============================================================================*/
IF @CcDanKrchmar LIKE N'<<%' OR @CcSelf LIKE N'<<%'
BEGIN
    RAISERROR (N'Set @CcDanKrchmar and @CcSelf before running. This report goes to an external domain and should not send with the Cc list unset.', 16, 1);
    RETURN;
END

IF @DatabaseName IS NULL
BEGIN
    RAISERROR (N'Set @DatabaseName - the database holding PatientVisit / PatientProfile / DoctorFacility / MedLists. The header of this script has a query that lists the candidates.', 16, 1);
    RETURN;
END

IF DB_ID(@DatabaseName) IS NULL
BEGIN
    RAISERROR (N'Database "%s" does not exist on this instance.', 16, 1, @DatabaseName);
    RETURN;
END

IF @MailProfile IS NULL
BEGIN
    RAISERROR (N'Could not determine a Database Mail profile. Set @MailProfile.', 16, 1);
    RETURN;
END

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName) AND @ReplaceExisting = 0
BEGIN
    RAISERROR (N'Job "%s" already exists. Review it first; set @ReplaceExisting = 1 to drop and recreate it.', 16, 1, @JobName);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories
               WHERE name = @CategoryName AND category_class = 1)
    SET @CategoryName = N'[Uncategorized (Local)]';

DECLARE @CcList nvarchar(max) = @CcDanKrchmar + N';' + @CcSelf;

PRINT N'Target database : ' + @DatabaseName;
PRINT N'Mail profile    : ' + @MailProfile;
PRINT N'Owner           : ' + @OwnerLogin;
PRINT N'To              : ' + @ToList;
PRINT N'Cc              : ' + @CcList;
PRINT N'Failure alert   : ' + ISNULL(@SrcOperator, N'(none)');
PRINT N'Schedule        : daily at ' + STUFF(STUFF(RIGHT('000000'
        + CAST(@ActiveStartTime AS varchar(6)), 6), 5, 0, ':'), 3, 0, ':');

/*==============================================================================
  THE QUERY
  No CurrentCarrier / CurrentPICarrierId; ApprovalResults in full; ORDER BY
  pv.Visit ascending.
==============================================================================*/
DECLARE @Query nvarchar(max);

IF @UseCsvSafeQuery = 0
BEGIN
    SET @Query = N'
SELECT  pv.TicketNumber,
        pv.Visit,
        ml2.Description  AS [Visit Owner],
        pv.Entered,
        pp.PatientId,
        pp.Last,
        pp.First,
        df.ListName      AS [Doctor],
        df2.ListName     AS [Facility],
        df3.ListName     AS [Company],
        ml.Description   AS [Bill Status],
        pv.Description,
        CAST(pv.ApprovalResults AS nvarchar(max)) AS ApprovalResults,
        pv.Created,
        pv.CreatedBy,
        pv.LastModified,
        pv.LastModifiedBy
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = ''BillStatus''
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = ''VisitOwner''
WHERE   pv.VisitOwnerMId IN (''153669'', ''153695'', ''153696'')
ORDER BY pv.Visit;';
END
ELSE
BEGIN
    /*-- text columns quoted and escaped, CR/LF flattened. ApprovalResults is
         free text and the most likely column to contain commas and line
         breaks, which would otherwise shift every column to its right.
         Cast to nvarchar(4000) rather than max: a LOB column would need
         @query_no_truncate, and 4000 chars is far more than the 255 the
         weekly report keeps.                                              --*/
    SET @Query = N'
SELECT  pv.TicketNumber,
        pv.Visit,
        [Visit Owner]    = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(ml2.Description AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.Entered,
        pp.PatientId,
        [Last]           = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pp.Last AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [First]          = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pp.First AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Doctor]         = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(df.ListName AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Facility]       = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(df2.ListName AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Company]        = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(df3.ListName AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Bill Status]    = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(ml.Description AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Description]    = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.Description AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [ApprovalResults]= ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.ApprovalResults AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.Created,
        [CreatedBy]      = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.CreatedBy AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.LastModified,
        [LastModifiedBy] = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.LastModifiedBy AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"''
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = ''BillStatus''
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = ''VisitOwner''
WHERE   pv.VisitOwnerMId IN (''153669'', ''153695'', ''153696'')
ORDER BY pv.Visit;';
END

/*==============================================================================
  THE JOB STEP COMMAND
  Flat template with $TOKENS$, filled in afterwards - nothing below opens or
  closes a quote outside the template itself.
==============================================================================*/
DECLARE @Command nvarchar(max);

SET @Command =
N'SET NOCOUNT ON;

DECLARE @FileName sysname       = N''SCMG_Coding_Worklists_''
                                + CONVERT(varchar(8), GETDATE(), 112) + N''.csv'';
DECLARE @Subject  nvarchar(255) = N''SCMG Coding Worklists - ''
                                + CONVERT(varchar(10), GETDATE(), 101);
DECLARE @Body     nvarchar(max) =
        N''Attached is the SCMG coding worklist report for ''
      + CONVERT(varchar(10), GETDATE(), 101) + N''.''
      + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
      + N''Visits owned by VisitOwnerMId 153669, 153695 and 153696.''
      + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
      + N''Generated automatically by SQL Agent job $JOBNAME$ on '' + @@SERVERNAME + N''.'';

EXEC msdb.dbo.sp_send_dbmail
     @profile_name                = N''$PROFILE$'',
     @recipients                  = N''$RECIPIENTS$'',
     @copy_recipients             = N''$CCLIST$'',
     @subject                     = @Subject,
     @body                        = @Body,
     @body_format                 = ''TEXT'',
     @query                       = N''$QUERY$'',
     @execute_query_database      = N''$DATABASE$'',
     @attach_query_result_as_file = 1,
     @query_attachment_filename   = @FileName,
     @query_result_header         = 1,
     @query_result_separator      = '','',
     @query_result_no_padding     = 1,
     @query_result_width          = 32767,
     @append_query_error          = 0,
     @exclude_query_output        = 1;';

SET @Command = REPLACE(@Command, N'$JOBNAME$',    REPLACE(@JobName,      N'''', N''''''));
SET @Command = REPLACE(@Command, N'$PROFILE$',    REPLACE(@MailProfile,  N'''', N''''''));
SET @Command = REPLACE(@Command, N'$RECIPIENTS$', REPLACE(@ToList,       N'''', N''''''));
SET @Command = REPLACE(@Command, N'$CCLIST$',     REPLACE(@CcList,       N'''', N''''''));
SET @Command = REPLACE(@Command, N'$DATABASE$',   REPLACE(@DatabaseName, N'''', N''''''));
SET @Command = REPLACE(@Command, N'$QUERY$',      REPLACE(@Query,        N'''', N''''''));

/*==============================================================================
  CREATE THE JOB
==============================================================================*/
DECLARE @JobId uniqueidentifier;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
    BEGIN
        PRINT N'Dropping existing job "' + @JobName + N'"...';
        EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
    END

    EXEC msdb.dbo.sp_add_job
         @job_name                   = @JobName,
         @enabled                    = @JobEnabled,
         @description                = N'Daily 04:00. Emails the SCMG coding worklist (VisitOwnerMId 153669, 153695, 153696) as a CSV attachment to the Ensemble coding team.',
         @category_name              = @CategoryName,
         @owner_login_name           = @OwnerLogin,
         @notify_level_eventlog      = @SrcNotifyEventlog,
         @notify_level_email         = @SrcNotifyEmail,
         @notify_email_operator_name = @SrcOperator,
         @job_id                     = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id            = @JobId,
         @step_name         = N'Send SCMG Coding Worklists (daily)',
         @step_id           = 1,
         @subsystem         = N'TSQL',
         @database_name     = N'msdb',
         @command           = @Command,
         @on_success_action = 1,
         @on_fail_action    = 2,
         @retry_attempts    = 1,
         @retry_interval    = 5;

    EXEC msdb.dbo.sp_update_job @job_id = @JobId, @start_step_id = 1;

    EXEC msdb.dbo.sp_add_jobschedule
         @job_id            = @JobId,
         @name              = N'schEnsemble_SCMGCodingWorklistsDaily',
         @enabled           = 1,
         @freq_type         = 4,            -- daily
         @freq_interval     = 1,            -- every 1 day
         @freq_subday_type  = 1,            -- at the specified time
         @active_start_time = @ActiveStartTime;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';

    COMMIT TRANSACTION;
    PRINT N'Job "' + @JobName + N'" created successfully.';
    PRINT N'Test it with:  EXEC msdb.dbo.sp_start_job @job_name = N''' + @JobName + N''';';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    PRINT N'Job creation FAILED - nothing was left behind.';
    THROW;
END CATCH
GO

/*==============================================================================
  POST-CREATE

  IMPORTANT - test before the first scheduled run. This sends to an external
  domain (@ensemblehp.com). Consider creating it with @JobEnabled = 0, then
  temporarily swapping @ToList for your own address to check the attachment
  before letting it go out to the vendor.

  Check the outcome:
      SELECT TOP (5) h.run_date, h.run_time, h.run_status, h.message
      FROM   msdb.dbo.sysjobhistory h
      JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
      WHERE  j.name = 'Ensemble_SCMGCodingWorklistsDaily'
      ORDER  BY h.run_date DESC, h.run_time DESC;

  Confirm the mail actually left the server:
      SELECT TOP (5) sent_status, sent_date, recipients, copy_recipients, subject
      FROM   msdb.dbo.sysmail_allitems
      ORDER  BY mailitem_id DESC;

  Failed sends and the reason:
      SELECT TOP (20) * FROM msdb.dbo.sysmail_event_log ORDER BY log_id DESC;
==============================================================================*/
