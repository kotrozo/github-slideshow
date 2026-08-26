/*==============================================================================
  Ensemble_SCMGCodingWorklists_SSIS.sql
  Server  : schcent20db01
  Creates : SQL Agent job "Ensemble_SCMGCodingWorklists"
  Clones  : JK_EnsembleVisitOwner (SSIS job, \SSISDB\EDJobs\EnsembleVisitOwner)

  This does NOT invent a job step. It reads JK_EnsembleVisitOwner's actual
  /ISSERVER step command and substitutes the project/package name, so every
  other switch - server, LOGGING_LEVEL, SYNCHRONIZED, CALLERINFO, REPORTING -
  is identical to the job that already works. Category, owner, failure-alert
  operator and schedule are inherited the same way.

  PREREQUISITE
  ------------
  The SSIS project must already be deployed to the catalog. See
  sql/ssis/README.md for cloning the existing project and changing the WHERE
  clause. This script REFUSES to create a job pointing at a package that is
  not in SSISDB, so run it after deploying.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

/*==============================================================================
  SETTINGS
==============================================================================*/
DECLARE @JobName         sysname = N'Ensemble_SCMGCodingWorklists',
        @SourceJob       sysname = N'JK_EnsembleVisitOwner',
        @OldProjectName  sysname = N'EnsembleVisitOwner',           -- text to replace
        @NewProjectName  sysname = N'Ensemble_SCMGCodingWorklists', -- replacement
        @JobEnabled      tinyint = 1,
        @ReplaceExisting bit     = 0;   -- 1 = drop + recreate if it exists

/*==============================================================================
  READ THE SOURCE JOB
==============================================================================*/
DECLARE @SrcCmd        nvarchar(max),
        @SrcSubsystem  nvarchar(40),
        @SrcStepDb     sysname,
        @SrcStepName   sysname,
        @SrcProxyId    int,
        @SrcOnSuccess  int,
        @SrcOnFail     int,
        @SrcRetries    int,
        @SrcCategory   sysname,
        @SrcOwner      sysname,
        @SrcOperator   sysname,
        @SrcNotifyEmail    tinyint,
        @SrcNotifyEventlog tinyint;

/* tolerate a prefix/rename on the source job */
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
   AND (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%') = 1
BEGIN
    SELECT @SourceJob = name FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%';
    PRINT N'Source job resolved to "' + @SourceJob + N'".';
END

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
BEGIN
    RAISERROR (N'Source job "%s" not found - nothing to clone.', 16, 1, @SourceJob);
    RETURN;
END

SELECT TOP (1)
        @SrcCmd       = s.command,
        @SrcSubsystem = s.subsystem,
        @SrcStepDb    = s.database_name,
        @SrcStepName  = s.step_name,
        @SrcProxyId   = s.proxy_id,
        @SrcOnSuccess = s.on_success_action,
        @SrcOnFail    = s.on_fail_action,
        @SrcRetries   = s.retry_attempts
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
SET @SrcOwner          = ISNULL(@SrcOwner, SUSER_SNAME());
SET @SrcCategory       = ISNULL(@SrcCategory, N'[Uncategorized (Local)]');

IF @SrcCmd IS NULL OR @SrcSubsystem <> N'SSIS'
BEGIN
    RAISERROR (N'Source job "%s" has no SSIS step to clone (subsystem is "%s").',
               16, 1, @SourceJob, @SrcSubsystem);
    RETURN;
END

/*==============================================================================
  BUILD THE NEW STEP COMMAND
==============================================================================*/
DECLARE @NewCmd nvarchar(max) = REPLACE(@SrcCmd, @OldProjectName, @NewProjectName);

IF @NewCmd = @SrcCmd
BEGIN
    RAISERROR (N'"%s" does not appear in the source step command, so nothing was substituted. Check @OldProjectName against the command printed below.', 16, 1, @OldProjectName);
    PRINT @SrcCmd;
    RETURN;
END

PRINT N'--- source step command ---';
PRINT @SrcCmd;
PRINT N'--- new step command ------';
PRINT @NewCmd;
PRINT N'---------------------------';

/*==============================================================================
  VERIFY THE PACKAGE IS ACTUALLY DEPLOYED
  Parses \SSISDB\<folder>\<project>\<package>.dtsx out of the new command.
==============================================================================*/
DECLARE @Path      nvarchar(1000),
        @Folder    sysname,
        @Project   sysname,
        @Package   sysname,
        @p1 int, @p2 int, @s1 int, @s2 int;

SET @p1 = CHARINDEX(N'\SSISDB\', @NewCmd);
SET @p2 = CHARINDEX(N'.dtsx', @NewCmd);

IF @p1 > 0 AND @p2 > @p1
BEGIN
    SET @Path = SUBSTRING(@NewCmd, @p1 + LEN(N'\SSISDB\') + 1, @p2 - @p1 - LEN(N'\SSISDB\'));

    SET @s1 = CHARINDEX(N'\', @Path);
    SET @s2 = CHARINDEX(N'\', @Path, @s1 + 1);

    IF @s1 > 0 AND @s2 > @s1
    BEGIN
        SET @Folder  = SUBSTRING(@Path, 1, @s1 - 1);
        SET @Project = SUBSTRING(@Path, @s1 + 1, @s2 - @s1 - 1);
        SET @Package = SUBSTRING(@Path, @s2 + 1, LEN(@Path) - @s2) + N'.dtsx';

        PRINT N'Catalog folder  : ' + @Folder;
        PRINT N'Catalog project : ' + @Project;
        PRINT N'Catalog package : ' + @Package;
    END
END

IF @Folder IS NULL OR @Project IS NULL OR @Package IS NULL
BEGIN
    RAISERROR (N'Could not parse the \SSISDB\folder\project\package.dtsx path out of the step command. Review the command printed above.', 16, 1);
    RETURN;
END

IF DB_ID(N'SSISDB') IS NULL
    PRINT N'WARNING: SSISDB not visible from here - skipping the deployment check.';
ELSE IF NOT EXISTS (
        SELECT 1
        FROM   SSISDB.catalog.packages  pkg
        JOIN   SSISDB.catalog.projects  prj ON prj.project_id = pkg.project_id
        JOIN   SSISDB.catalog.folders   fld ON fld.folder_id  = prj.folder_id
        WHERE  fld.name = @Folder
          AND  prj.name = @Project
          AND  pkg.name = @Package)
BEGIN
    RAISERROR (N'Package "%s" is not deployed under \SSISDB\%s\%s. Deploy the project first (see sql/ssis/README.md), then re-run this script.',
               16, 1, @Package, @Folder, @Project);
    RETURN;
END

/*==============================================================================
  SCHEDULE - inherited from the source job
==============================================================================*/
DECLARE @FreqType             int = 8,   -- weekly
        @FreqInterval         int = 2,   -- Monday
        @FreqSubdayType       int = 1,
        @FreqSubdayInterval   int = 0,
        @FreqRelativeInterval int = 0,
        @FreqRecurrenceFactor int = 1,
        @ActiveStartTime      int = 40000;  -- 04:00:00

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

PRINT N'Category        : ' + @SrcCategory;
PRINT N'Owner           : ' + @SrcOwner;
PRINT N'Failure alert   : ' + ISNULL(@SrcOperator, N'(none)');
PRINT N'Start time      : ' + STUFF(STUFF(RIGHT('000000'
        + CAST(@ActiveStartTime AS varchar(6)), 6), 5, 0, ':'), 3, 0, ':');

/*==============================================================================
  CREATE THE JOB
==============================================================================*/
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName) AND @ReplaceExisting = 0
BEGIN
    RAISERROR (N'Job "%s" already exists. Review it first; set @ReplaceExisting = 1 to drop and recreate it.', 16, 1, @JobName);
    RETURN;
END

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
         @description                = N'Emails the SCMG coding worklist (PatientVisit rows for VisitOwnerMId 153669, 153695, 153696). Cloned from JK_EnsembleVisitOwner.',
         @category_name              = @SrcCategory,
         @owner_login_name           = @SrcOwner,
         @notify_level_eventlog      = @SrcNotifyEventlog,
         @notify_level_email         = @SrcNotifyEmail,
         @notify_email_operator_name = @SrcOperator,
         @job_id                     = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id            = @JobId,
         @step_name         = N'stepEnsemble_SCMGCodingWorklists',
         @step_id           = 1,
         @subsystem         = @SrcSubsystem,     -- SSIS
         @database_name     = @SrcStepDb,        -- as on the source step
         @command           = @NewCmd,
         @proxy_id          = @SrcProxyId,       -- NULL = run as Agent service account
         @on_success_action = @SrcOnSuccess,
         @on_fail_action    = @SrcOnFail,
         @retry_attempts    = @SrcRetries;

    EXEC msdb.dbo.sp_update_job @job_id = @JobId, @start_step_id = 1;

    EXEC msdb.dbo.sp_add_jobschedule
         @job_id                 = @JobId,
         @name                   = N'schEnsemble_SCMGCodingWorklists',
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
