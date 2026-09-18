/*==============================================================================
  Creates SQL Agent job  JK_EnsembleSCMGCodingWorklists  on schcent20db01.

  Runs daily at 04:00, queries ED, emails the result as a dated CSV.

    To : Kristie.Stuber@ensemblehp.com, Holly.Aguilar@ensemblehp.com,
         Heather.Russell@ensemblehp.com, Jessica.Apolito@ensemblehp.com
    Cc : Daniel.Krchmar@stclair.org, joe.kotrozo@stclair.org

  Run the whole thing in SSMS. There is an optional test-send at the bottom
  you can highlight and run on its own first.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

DECLARE @JobName sysname = N'JK_EnsembleSCMGCodingWorklists';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    RAISERROR (N'Job "%s" already exists. Delete it first if you want to recreate it.', 16, 1, @JobName);
    RETURN;
END

/*---- the query -------------------------------------------------------------
  Text columns are wrapped in quotes and escaped, because Description and
  ApprovalResults contain commas that would otherwise shift the CSV columns.
----------------------------------------------------------------------------*/
DECLARE @Query nvarchar(max) = N'
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

/*---- the job step ----------------------------------------------------------*/
DECLARE @Command nvarchar(max) =
N'SET NOCOUNT ON;

DECLARE @FileName sysname       = N''SCMG_Coding_Worklists_''
                                + CONVERT(varchar(8), GETDATE(), 112) + N''.csv'';
DECLARE @Subject  nvarchar(255) = N''SCMG Coding Worklists - ''
                                + CONVERT(varchar(10), GETDATE(), 101);

EXEC msdb.dbo.sp_send_dbmail
     @profile_name                = N''SQLMail Alerts'',
     @recipients                  = N''Kristie.Stuber@ensemblehp.com;Holly.Aguilar@ensemblehp.com;Heather.Russell@ensemblehp.com;Jessica.Apolito@ensemblehp.com'',
     @copy_recipients             = N''Daniel.Krchmar@stclair.org;joe.kotrozo@stclair.org'',
     @subject                     = @Subject,
     @body                        = N''Attached is the SCMG coding worklist report.'',
     @body_format                 = ''TEXT'',
     @query                       = N''$QUERY$'',
     @execute_query_database      = N''ED'',
     @attach_query_result_as_file = 1,
     @query_attachment_filename   = @FileName,
     @query_result_header         = 1,
     @query_result_separator      = '','',
     @query_result_no_padding     = 1,
     @query_result_width          = 32767,
     @exclude_query_output        = 1;';

SET @Command = REPLACE(@Command, N'$QUERY$', REPLACE(@Query, N'''', N''''''));

/*---- create it -------------------------------------------------------------*/
DECLARE @JobId uniqueidentifier;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC msdb.dbo.sp_add_job
         @job_name                   = @JobName,
         @enabled                    = 1,
         @description                = N'Daily 04:00. Emails the SCMG coding worklist as a CSV.',
         @category_name              = N'[Uncategorized (Local)]',
         @owner_login_name           = N'ST_CLAIR\jkotrozoadm',
         @notify_level_email         = 2,          -- on failure
         @notify_email_operator_name = N'DBA',
         @job_id                     = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id            = @JobId,
         @step_name         = N'stepEnsembleSCMGCodingWorklists',
         @step_id           = 1,
         @subsystem         = N'TSQL',
         @database_name     = N'msdb',
         @command           = @Command,
         @on_success_action = 1,
         @on_fail_action    = 2;

    EXEC msdb.dbo.sp_update_job @job_id = @JobId, @start_step_id = 1;

    EXEC msdb.dbo.sp_add_jobschedule
         @job_id            = @JobId,
         @name              = N'schEnsembleSCMGCodingWorklists',
         @enabled           = 1,
         @freq_type         = 4,        -- daily
         @freq_interval     = 1,
         @freq_subday_type  = 1,
         @active_start_time = 40000;    -- 04:00:00

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';

    COMMIT TRANSACTION;
    PRINT N'Created job: ' + @JobName;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO


/*==============================================================================
  OPTIONAL - test send to yourself only. Highlight this block and run it.
  Sends nothing to the Ensemble addresses and does not touch the job.
==============================================================================*/
/*
EXEC msdb.dbo.sp_send_dbmail
     @profile_name                = N'SQLMail Alerts',
     @recipients                  = N'joe.kotrozo@stclair.org',
     @subject                     = N'[TEST] SCMG Coding Worklists',
     @body                        = N'Test send.',
     @query                       = N'SELECT TOP 100 pv.TicketNumber, pv.Visit, pv.Entered, pp.PatientId, pp.Last, pp.First
FROM PatientVisit pv
JOIN PatientProfile pp ON pp.PatientProfileId = pv.PatientProfileId
WHERE pv.VisitOwnerMId IN (''153669'', ''153695'', ''153696'')
ORDER BY pv.Visit;',
     @execute_query_database      = N'ED',
     @attach_query_result_as_file = 1,
     @query_attachment_filename   = N'test.csv',
     @query_result_header         = 1,
     @query_result_separator      = ',',
     @query_result_no_padding     = 1,
     @query_result_width          = 32767,
     @exclude_query_output        = 1;
*/

/*==============================================================================
  Run the job now:
      EXEC msdb.dbo.sp_start_job @job_name = N'JK_EnsembleSCMGCodingWorklists';

  Did the mail go out?
      SELECT TOP 5 sent_status, sent_date, recipients, copy_recipients, subject
      FROM msdb.dbo.sysmail_allitems ORDER BY mailitem_id DESC;
==============================================================================*/
