/*==============================================================================
  test_send_daily_to_me.sql
  Server : schcent20db01

  ONE-OFF TEST SEND - creates no job, changes nothing.

  Runs the daily SCMG coding worklist query against ED and emails the CSV to
  joe.kotrozo@stclair.org only. No Cc, nothing to the Ensemble addresses.

  Point of the exercise:
    1. does the query run clean against ED
    2. does the CSV open with columns intact
    3. does Database Mail actually deliver

  Run it, then run the verification queries at the bottom.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

DECLARE @TestRecipient sysname = N'joe.kotrozo@stclair.org',
        @DatabaseName  sysname = N'ED',
        @MailProfile   sysname = NULL;   -- NULL = use the instance default

/*---- resolve the mail profile --------------------------------------------*/
IF @MailProfile IS NULL
    SELECT TOP (1) @MailProfile = p.name
    FROM   msdb.dbo.sysmail_profile           p
    JOIN   msdb.dbo.sysmail_principalprofile pp ON pp.profile_id = p.profile_id
    WHERE  pp.is_default = 1;

IF @MailProfile IS NULL AND (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) = 1
    SELECT @MailProfile = name FROM msdb.dbo.sysmail_profile;

IF @MailProfile IS NULL
BEGIN
    RAISERROR (N'No Database Mail profile resolved. Set @MailProfile explicitly.', 16, 1);
    RETURN;
END

IF DB_ID(@DatabaseName) IS NULL
BEGIN
    RAISERROR (N'Database "%s" not found on this instance.', 16, 1, @DatabaseName);
    RETURN;
END

PRINT N'Profile   : ' + @MailProfile;
PRINT N'Database  : ' + @DatabaseName;
PRINT N'Sending to: ' + @TestRecipient;

/*==============================================================================
  THE QUERY
  Only one level of quoting here - this calls sp_send_dbmail directly rather
  than building a job step, so the query is a plain variable.
==============================================================================*/
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

DECLARE @FileName sysname       = N'SCMG_Coding_Worklists_'
                                + CONVERT(varchar(8), GETDATE(), 112) + N'.csv';
DECLARE @Subject  nvarchar(255) = N'[TEST] SCMG Coding Worklists - '
                                + CONVERT(varchar(10), GETDATE(), 101);

EXEC msdb.dbo.sp_send_dbmail
     @profile_name                = @MailProfile,
     @recipients                  = @TestRecipient,
     @subject                     = @Subject,
     @body                        = N'Test send. If the attachment opens with clean columns, the daily job is good to build.',
     @body_format                 = 'TEXT',
     @query                       = @Query,
     @execute_query_database      = @DatabaseName,
     @attach_query_result_as_file = 1,
     @query_attachment_filename   = @FileName,
     @query_result_header         = 1,
     @query_result_separator      = ',',
     @query_result_no_padding     = 1,
     @query_result_width          = 32767,
     @append_query_error          = 0,
     @exclude_query_output        = 1;

PRINT N'Queued. Database Mail sends asynchronously - check below.';
GO

/*==============================================================================
  VERIFY - run these a few seconds later
==============================================================================*/

-- did it send?  sent_status: sent / unsent / retrying / failed
SELECT TOP (5) mailitem_id, sent_status, sent_date, recipients, subject
FROM   msdb.dbo.sysmail_allitems
ORDER  BY mailitem_id DESC;

-- if sent_status is anything but 'sent', the reason is here
SELECT TOP (20) log_date, event_type, description
FROM   msdb.dbo.sysmail_event_log
ORDER  BY log_id DESC;
GO

/*==============================================================================
  WHAT TO LOOK FOR

  - sent_status = 'sent'  -> relay works, and to your own domain at least.
    That does NOT yet prove @ensemblehp.com will work; to test that, rerun
    with @TestRecipient set to one external address you're comfortable
    pinging, or ask whoever runs the mail relay.

  - sent_status = 'failed' -> read sysmail_event_log. A relay refusal names
    the recipient domain; a profile/account problem names the SMTP server.

  - Attachment arrives but columns are shifted -> the CSV escaping is not
    holding; send me a sample row and I'll adjust.

  - Attachment is empty apart from headers -> the query returned no rows for
    VisitOwnerMId 153669 / 153695 / 153696 in ED. Worth checking ED is the
    right database before building anything on it:

        SELECT COUNT(*) FROM ED.dbo.PatientVisit
        WHERE VisitOwnerMId IN ('153669', '153695', '153696');
==============================================================================*/
