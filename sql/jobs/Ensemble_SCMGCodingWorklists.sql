/*==============================================================================
  Ensemble_SCMGCodingWorklists.sql
  Server  : schcent20db01
  Creates : SQL Agent job "Ensemble_SCMGCodingWorklists"
  Modeled : on the existing job "EnsembleVisitOwner"

  What it does
  ------------
  One TSQL step that calls msdb.dbo.sp_send_dbmail, running the SCMG coding
  worklist query and attaching the result as a dated .csv.

  Before you run it
  -----------------
  1. Run _inspect_EnsembleVisitOwner.sql and read the output.
  2. The settings block below AUTO-COPIES the target database, mail profile,
     category, owner and schedule from EnsembleVisitOwner. Anything it cannot
     read, you set by hand in the OVERRIDES section - the script stops with a
     clear message rather than creating a half-configured job.
  3. Recipients are set to kotrozo@gmail.com only. Add more later with:
        EXEC msdb.dbo.sp_update_jobstep ...   (or just re-run this script
        with @Recipients changed and @ReplaceExisting = 1)

  Idempotency: re-running is safe only with @ReplaceExisting = 1, which DROPS
  and recreates the job. It defaults to 0 so an existing job is never silently
  destroyed.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

/*==============================================================================
  SETTINGS
==============================================================================*/
DECLARE @JobName        sysname       = N'Ensemble_SCMGCodingWorklists',
        @SourceJob      sysname       = N'EnsembleVisitOwner',
        @Recipients     nvarchar(max) = N'kotrozo@gmail.com',
        @JobEnabled     tinyint       = 1,   -- 1 = job runs on schedule
        @ReplaceExisting bit          = 0,   -- 1 = drop + recreate if it exists
        @UseCsvSafeQuery bit          = 1;   -- 1 = quote/escape text columns
                                             --     (see NOTE at bottom)

/*---- OVERRIDES: leave NULL to inherit from EnsembleVisitOwner --------------*/
DECLARE @DatabaseName   sysname  = NULL,    -- e.g. N'Intergy'
        @MailProfile    sysname  = NULL,    -- e.g. N'SQLMail'
        @CategoryName   sysname  = NULL,
        @OwnerLogin     sysname  = NULL,
        @ScheduleTime   int      = NULL;    -- HHMMSS, e.g. 60000 = 06:00:00

/*==============================================================================
  INHERIT SETTINGS FROM THE SOURCE JOB
==============================================================================*/
DECLARE @SrcCmd       nvarchar(max),
        @SrcDb        sysname,
        @SrcProfile   sysname,
        @SrcCategory  sysname,
        @SrcOwner     sysname,
        @q1           int,
        @q2           int;

SELECT TOP (1)
        @SrcDb  = NULLIF(s.database_name, N''),
        @SrcCmd = s.command
FROM    msdb.dbo.sysjobs     j
JOIN    msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE   j.name = @SourceJob
  AND   s.command LIKE N'%sp_send_dbmail%'
ORDER BY s.step_id;

SELECT  @SrcCategory = c.name,
        @SrcOwner    = SUSER_SNAME(j.owner_sid)
FROM    msdb.dbo.sysjobs        j
LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
WHERE   j.name = @SourceJob;

/*-- pull the literal that follows @profile_name = out of the source command --*/
IF @SrcCmd IS NOT NULL
BEGIN
    SET @q1 = CHARINDEX(N'@profile_name', @SrcCmd);
    IF @q1 > 0
    BEGIN
        SET @q1 = CHARINDEX(N'''', @SrcCmd, @q1);
        IF @q1 > 0
        BEGIN
            SET @q2 = CHARINDEX(N'''', @SrcCmd, @q1 + 1);
            IF @q2 > @q1
                SET @SrcProfile = SUBSTRING(@SrcCmd, @q1 + 1, @q2 - @q1 - 1);
        END
    END
END

/* the source may use a variable rather than a literal - only trust a real one */
IF @SrcProfile IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = @SrcProfile)
    SET @SrcProfile = NULL;

IF @SrcDb IS NOT NULL AND DB_ID(@SrcDb) IS NULL
    SET @SrcDb = NULL;

/* if only one mail profile exists on the instance, it is unambiguous */
IF @SrcProfile IS NULL AND (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) = 1
    SELECT @SrcProfile = name FROM msdb.dbo.sysmail_profile;

SELECT  @DatabaseName = COALESCE(@DatabaseName, @SrcDb),
        @MailProfile  = COALESCE(@MailProfile,  @SrcProfile),
        @CategoryName = COALESCE(@CategoryName, @SrcCategory, N'[Uncategorized (Local)]'),
        @OwnerLogin   = COALESCE(@OwnerLogin,   @SrcOwner,    SUSER_SNAME());

/*---- schedule: copy the source job's, else default to daily 06:00 ---------*/
DECLARE @FreqType              int = 4,   -- 4 = daily
        @FreqInterval          int = 1,
        @FreqSubdayType        int = 1,
        @FreqSubdayInterval    int = 0,
        @FreqRelativeInterval  int = 0,
        @FreqRecurrenceFactor  int = 0,
        @ActiveStartTime       int = 60000;

SELECT TOP (1)
        @FreqType             = sch.freq_type,
        @FreqInterval         = sch.freq_interval,
        @FreqSubdayType       = sch.freq_subday_type,
        @FreqSubdayInterval   = sch.freq_subday_interval,
        @FreqRelativeInterval = sch.freq_relative_interval,
        @FreqRecurrenceFactor = sch.freq_recurrence_factor,
        @ActiveStartTime      = sch.active_start_time
FROM    msdb.dbo.sysjobs         j
JOIN    msdb.dbo.sysjobschedules js  ON js.job_id       = j.job_id
JOIN    msdb.dbo.sysschedules    sch ON sch.schedule_id = js.schedule_id
WHERE   j.name = @SourceJob
ORDER BY sch.schedule_id;

/* a one-time source schedule would leave this report running exactly once */
IF @FreqType = 1
BEGIN
    PRINT N'Source schedule is one-time only - defaulting new job to daily instead.';
    SELECT @FreqType = 4, @FreqInterval = 1, @FreqSubdayType = 1,
           @FreqSubdayInterval = 0, @FreqRelativeInterval = 0, @FreqRecurrenceFactor = 0;
END

SET @ActiveStartTime = COALESCE(@ScheduleTime, @ActiveStartTime);

/*==============================================================================
  VALIDATE - fail loudly rather than build a broken job
==============================================================================*/
IF @DatabaseName IS NULL
BEGIN
    RAISERROR (N'Could not determine the target database from "%s". Set @DatabaseName in the OVERRIDES block (the DB holding PatientVisit / PatientProfile / DoctorFacility / MedLists).', 16, 1, @SourceJob);
    RETURN;
END

IF @MailProfile IS NULL
BEGIN
    RAISERROR (N'Could not determine a Database Mail profile from "%s". Set @MailProfile in the OVERRIDES block (see section 4 of _inspect_EnsembleVisitOwner.sql).', 16, 1, @SourceJob);
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

PRINT N'Target database : ' + @DatabaseName;
PRINT N'Mail profile    : ' + @MailProfile;
PRINT N'Category        : ' + @CategoryName;
PRINT N'Owner           : ' + @OwnerLogin;
PRINT N'Recipients      : ' + @Recipients;
PRINT N'Start time      : ' + STUFF(STUFF(RIGHT('000000'
        + CAST(@ActiveStartTime AS varchar(6)), 6), 5, 0, ':'), 3, 0, ':');

/*==============================================================================
  THE QUERY
==============================================================================*/
DECLARE @Query nvarchar(max);

IF @UseCsvSafeQuery = 0
BEGIN
    /*-- verbatim as supplied (trailing "and and" typo removed from ORDER BY) --*/
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
        pv.CurrentCarrier,
        pv.[CurrentPICarrierId],
        ml.Description   AS [Bill Status],
        pv.Description,
        LEFT(CAST(pv.ApprovalResults AS nvarchar(max)), 255) AS ApprovalResults,
        pv.Created,
        pv.CreatedBy,
        pv.LastModified,
        pv.LastModifiedBy
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code       = pv.BillStatus    AND ml.TableName  = ''BillStatus''
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = ''VisitOwner''
WHERE   pv.VisitOwnerMId IN (''153669'', ''153695'', ''153696'')
ORDER BY pv.Visit DESC;';
END
ELSE
BEGIN
    /*-- same query, but every free-text column is wrapped in double quotes,
         embedded quotes doubled, and CR/LF flattened to spaces. Without this,
         a comma inside Description / ApprovalResults / a carrier name shifts
         every column to its right when the .csv is opened.                  --*/
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
        [CurrentCarrier] = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.CurrentCarrier AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.[CurrentPICarrierId],
        [Bill Status]    = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(ml.Description AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [Description]    = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.Description AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        [ApprovalResults]= ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(LEFT(CAST(pv.ApprovalResults AS nvarchar(max)), 255), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.Created,
        [CreatedBy]      = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.CreatedBy AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"'',
        pv.LastModified,
        [LastModifiedBy] = ''"'' + REPLACE(REPLACE(REPLACE(ISNULL(CAST(pv.LastModifiedBy AS nvarchar(4000)), N''''), ''"'', ''""''), CHAR(13), '' ''), CHAR(10), '' '') + ''"''
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code       = pv.BillStatus    AND ml.TableName  = ''BillStatus''
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = ''VisitOwner''
WHERE   pv.VisitOwnerMId IN (''153669'', ''153695'', ''153696'')
ORDER BY pv.Visit DESC;';
END

/*==============================================================================
  THE JOB STEP COMMAND
==============================================================================*/
/* Built as one flat template with $TOKENS$, then filled in. Splicing outer
   concatenation into the middle of a quoted literal is how these scripts break,
   so nothing below opens or closes a quote outside the template itself.        */
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

/* $QUERY$ last: its replacement text is the only one that can be large.
   Every replacement is quote-doubled so it survives as a literal inside the
   step command.                                                              */
SET @Command = REPLACE(@Command, N'$JOBNAME$',    REPLACE(@JobName,      N'''', N''''''));
SET @Command = REPLACE(@Command, N'$PROFILE$',    REPLACE(@MailProfile,  N'''', N''''''));
SET @Command = REPLACE(@Command, N'$RECIPIENTS$', REPLACE(@Recipients,   N'''', N''''''));
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
         @job_name              = @JobName,
         @enabled               = @JobEnabled,
         @description           = N'Emails the SCMG coding worklist (PatientVisit rows for VisitOwnerMId 153669, 153695, 153696) as a CSV attachment. Modeled on EnsembleVisitOwner.',
         @category_name         = @CategoryName,
         @owner_login_name      = @OwnerLogin,
         @notify_level_eventlog = 2,          -- log on failure
         @job_id                = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id           = @JobId,
         @step_name        = N'Send SCMG Coding Worklists',
         @step_id          = 1,
         @subsystem        = N'TSQL',
         @database_name    = N'msdb',         -- the step calls msdb.dbo.sp_send_dbmail;
                                              -- the query itself runs in @DatabaseName
         @command          = @Command,
         @on_success_action = 1,              -- quit reporting success
         @on_fail_action    = 2,              -- quit reporting failure
         @retry_attempts    = 1,
         @retry_interval    = 5;

    EXEC msdb.dbo.sp_update_job @job_id = @JobId, @start_step_id = 1;

    EXEC msdb.dbo.sp_add_jobschedule
         @job_id                 = @JobId,
         @name                   = N'Ensemble_SCMGCodingWorklists_Schedule',
         @enabled                = 1,
         @freq_type              = @FreqType,
         @freq_interval          = @FreqInterval,
         @freq_subday_type       = @FreqSubdayType,
         @freq_subday_interval   = @FreqSubdayInterval,
         @freq_relative_interval = @FreqRelativeInterval,
         @freq_recurrence_factor = @FreqRecurrenceFactor,
         @active_start_time      = @ActiveStartTime;

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

  Run it now:
      EXEC msdb.dbo.sp_start_job @job_name = N'Ensemble_SCMGCodingWorklists';

  Check the outcome:
      SELECT TOP (5) h.run_date, h.run_time, h.run_status, h.message
      FROM   msdb.dbo.sysjobhistory h
      JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
      WHERE  j.name = 'Ensemble_SCMGCodingWorklists'
      ORDER  BY h.run_date DESC, h.run_time DESC;

  Check the mail actually went out:
      SELECT TOP (5) sent_status, sent_date, recipients, subject
      FROM   msdb.dbo.sysmail_allitems
      ORDER  BY mailitem_id DESC;

  Add recipients later (no need to rebuild the job):
      -- easiest: re-run this script with @Recipients updated and
      --          @ReplaceExisting = 1

  NOTE on @UseCsvSafeQuery
  ------------------------
  Default is 1. Description and ApprovalResults are free text and will contain
  commas (and possibly line breaks), which shift columns in a plain comma-
  separated attachment. With 1, those columns are quoted and escaped so Excel
  parses them correctly. Set it to 0 if you want the attachment byte-for-byte
  in the style EnsembleVisitOwner produces.
==============================================================================*/
