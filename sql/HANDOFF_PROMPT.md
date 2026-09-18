# Handoff prompt

Paste everything below the line into Claude Code on a machine that can reach
`schcent20db01`.

---

I need two SQL Agent jobs created on **schcent20db01**. You have access to that
server; verify everything against it rather than trusting the details below,
which come from an earlier session that had no connectivity.

## Files

Every script is inlined at the bottom of this prompt, under **Scripts**. Write
each one to the path in its heading, then work from them. They are untested -
nothing has ever been run against the server - so treat them as a starting
point, not as known-good. Fix what's wrong.

(They also exist in `kotrozo/github-slideshow`, branch
`claude/ensemble-scmgcodingworklists-job-rl49ft`, under `sql/`, if that is
reachable and you would rather pull them.)

## The model job

`JK_EnsembleVisitOwner` is the existing job these two are modeled on. As of the
last inspection:

| | |
|---|---|
| Step | `stepEnsembleVisitOwner`, subsystem **SSIS**, step database `master` |
| Command | `/ISSERVER "\"\SSISDB\EDJobs\EnsembleVisitOwner\…"` |
| Schedule | `schEnsembleVisitOwner` — weekly, Mondays 04:00 (`freq_type` 8, `freq_interval` 2, `active_start_time` 40000) |
| Owner | `ST_CLAIR\jkotrozoadm` |
| Category | `[Uncategorized (Local)]` |
| On failure | `notify_level_email` 2 → operator **DBA** (`DBAlerts@stclair.org`); `notify_level_eventlog` 0 |
| on_success / on_fail / retries | 1 / 2 / 0 |
| Mail profile | `SQLMail Alerts` (the instance default, and the only one) |

Target database for both reports is **ED**. Several databases on the instance
contain `PatientVisit` / `PatientProfile` / `MedLists`, so don't auto-detect it.

## Naming convention

The `JK_` prefix applies to the **Agent job only** — not the SSIS project or
package, and not the step or schedule names. Compare `JK_EnsembleVisitOwner`
against `\SSISDB\EDJobs\EnsembleVisitOwner`.

| Agent job | SSIS project / package | Schedule |
|---|---|---|
| `JK_EnsembleSCMGCodingWorklists` | `EnsembleSCMGCodingWorklists` | weekly, Mon 04:00 |
| `JK_EnsembleSCMGCodingWorklistsDaily` | `EnsembleSCMGCodingWorklistsDaily` | daily 04:00 |

These names are settled - no underscore after `Ensemble`, matching my other
jobs (`JK_EnsembleVisitOwner`, `JK_EnsembleOfficeProviderCode`). Use them
exactly as written. The SSIS project and package must match `@NewProjectName`
in the job scripts, or the deployment check will reject the job.

## Report 1 — weekly (Mondays 04:00), to me only

```sql
SELECT  pv.TicketNumber, pv.Visit,
        ml2.Description AS [Visit Owner],
        pv.Entered, pp.PatientId, pp.Last, pp.First,
        df.ListName AS [Doctor], df2.ListName AS [Facility], df3.ListName AS [Company],
        pv.CurrentCarrier, pv.[CurrentPICarrierId],
        ml.Description AS [Bill Status],
        pv.Description,
        LEFT(CAST(pv.ApprovalResults AS nvarchar(max)), 255) AS ApprovalResults,
        pv.Created, pv.CreatedBy, pv.LastModified, pv.LastModifiedBy
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = 'BillStatus'
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = 'VisitOwner'
WHERE   pv.VisitOwnerMId IN ('153669', '153695', '153696')
ORDER BY pv.Visit DESC;
```

Recipient: `joe.kotrozo@stclair.org`. More will be added later.

## Report 2 — daily 04:00, to the Ensemble coding team

Same `WHERE` clause. Differences: no `CurrentCarrier` / `CurrentPICarrierId`,
`ApprovalResults` untruncated, sorted `ORDER BY pv.Visit` **ascending**.

```sql
SELECT  pv.TicketNumber, pv.Visit,
        ml2.Description AS [Visit Owner],
        pv.Entered, pp.PatientId, pp.Last, pp.First,
        df.ListName AS [Doctor], df2.ListName AS [Facility], df3.ListName AS [Company],
        ml.Description AS [Bill Status],
        pv.Description,
        CAST(pv.ApprovalResults AS nvarchar(max)) AS ApprovalResults,
        pv.Created, pv.CreatedBy, pv.LastModified, pv.LastModifiedBy
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = 'BillStatus'
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = 'VisitOwner'
WHERE   pv.VisitOwnerMId IN ('153669', '153695', '153696')
ORDER BY pv.Visit;
```

- **To** — Kristie.Stuber@ensemblehp.com, Holly.Aguilar@ensemblehp.com,
  Heather.Russell@ensemblehp.com, Jessica.Apolito@ensemblehp.com
- **Cc** — Daniel.Krchmar@stclair.org, joe.kotrozo@stclair.org

Output is a dated CSV attachment.

## Two ways to build these — I picked SSIS

`JK_EnsembleVisitOwner` runs an SSIS package, and both reports are that same
package with a different query, so the intended path is:

1. Clone `\SSISDB\EDJobs\EnsembleVisitOwner` (Visual Studio → *Integration
   Services Import Project Wizard* reads the catalog directly; an `.ispac`
   can't be opened as a project)
2. Rename project and package, swap in the query and recipients
3. Deploy to the `EDJobs` folder
4. Create the Agent job with an `/ISSERVER` step

`sql/jobs/*_SSIS.sql` do step 4. They clone `JK_EnsembleVisitOwner`'s actual
step command and substitute the project name, so `/SERVER`, `LOGGING_LEVEL`,
`SYNCHRONIZED`, `CALLERINFO` and `REPORTING` match what already works, and they
refuse to create a job whose package isn't in the catalog.

`sql/jobs/EnsembleSCMGCodingWorklists*.sql` (no `_SSIS`) are self-contained
T-SQL alternatives using `sp_send_dbmail` — no package needed. They're a
fallback but they run today, so they're useful for proving the query and the
mail relay first.

**If you can drive Visual Studio/SSDT on this machine, do the SSIS route.** If
you can't, tell me so rather than quietly substituting the T-SQL version — then
I'll decide.

## Verify these before you finish

1. **Test to me first.** `sql/jobs/test_send_daily_to_me.sql` sends the daily
   report to `joe.kotrozo@stclair.org` only and creates no job. Run it and
   confirm the CSV opens with columns intact before anything goes to
   `@ensemblehp.com`.
2. **External relay.** `@ensemblehp.com` is an outside domain. A blocked relay
   shows up in `msdb.dbo.sysmail_event_log` while the job still reports
   success, so check `sysmail_allitems.sent_status` explicitly.
3. **CSV escaping.** `Description` and `ApprovalResults` are free text and will
   contain commas and line breaks, which shift every column to their right in a
   plain comma-separated file. The scripts quote and escape text columns; an
   SSIS Flat File destination needs a `"` text qualifier. Confirm against real
   data, not an empty result.
4. **`ApprovalResults` length.** The daily report asks for it untruncated, but
   as `nvarchar(max)` it's a LOB that `sp_send_dbmail` truncates unless you add
   `@query_no_truncate`, which conflicts with the padding settings that keep the
   CSV clean. The T-SQL script casts to `nvarchar(4000)` as a compromise. Check
   the real maximum length in ED and tell me if 4000 isn't enough.
5. **Row count.** Confirm the query actually returns rows in ED:
   `SELECT COUNT(*) FROM ED.dbo.PatientVisit WHERE VisitOwnerMId IN ('153669','153695','153696');`

Don't enable either job on its schedule until I've seen a test send.

---

# Scripts

Write each block to the path in its heading.

## `sql/jobs/test_send_daily_to_me.sql`

One-off test send. Creates no job. Run this FIRST.

```sql
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
```

## `sql/jobs/_inspect_EnsembleVisitOwner.sql`

Read-only. Dumps the model job so you can verify the details above.

```sql
/*==============================================================================
  _inspect_EnsembleVisitOwner.sql
  Server : schcent20db01
  Purpose: Dump the definition of the existing SQL Agent job "EnsembleVisitOwner"
           so the new job (EnsembleSCMGCodingWorklists) can be built to match.

  Run this FIRST. Read the output, then run EnsembleSCMGCodingWorklists.sql.
  Read-only - this script changes nothing.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

DECLARE @SourceJob sysname = N'JK_EnsembleVisitOwner';

/* tolerate a prefix/rename: if the exact name is gone but exactly one job
   matches, use that one instead of failing */
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
   AND (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%') = 1
BEGIN
    SELECT @SourceJob = name FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%';
    PRINT N'Exact name not found; using "' + @SourceJob + N'" instead.';
END

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
```

## `sql/jobs/EnsembleSCMGCodingWorklistsDaily.sql`

T-SQL daily job. Self-contained, runs today.

```sql
/*==============================================================================
  EnsembleSCMGCodingWorklistsDaily.sql
  Server  : schcent20db01
  Creates : SQL Agent job "JK_EnsembleSCMGCodingWorklistsDaily"

  Runs DAILY at 04:00 and emails the SCMG coding worklist as a dated .csv.

  Distribution
  ------------
  To : Kristie Stuber, Holly Aguilar, Heather Russell, Jessica Apolito
       (all @ensemblehp.com)
  Cc : Daniel.Krchmar@stclair.org, joe.kotrozo@stclair.org

  Ready to run as-is. Target database is ED; mail profile, owner, category
  and the failure-alert operator are inherited from JK_EnsembleVisitOwner.

  Test before the first scheduled run - see the POST-CREATE block at the
  bottom. This sends to an external domain.
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

/*==============================================================================
  SETTINGS
==============================================================================*/
DECLARE @JobName         sysname = N'JK_EnsembleSCMGCodingWorklistsDaily',
        @SourceJob       sysname = N'JK_EnsembleVisitOwner',
        @JobEnabled      tinyint = 1,
        @ReplaceExisting bit     = 0,   -- 1 = drop + recreate if it exists
        @UseCsvSafeQuery bit     = 1;   -- 1 = quote/escape text columns

/*---- REQUIRED ------------------------------------------------------------*/
DECLARE @DatabaseName sysname = N'ED',
        @CcDanKrchmar sysname = N'Daniel.Krchmar@stclair.org',
        @CcSelf       sysname = N'joe.kotrozo@stclair.org';

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
         @name              = N'schEnsembleSCMGCodingWorklistsDaily',
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
      WHERE  j.name = 'JK_EnsembleSCMGCodingWorklistsDaily'
      ORDER  BY h.run_date DESC, h.run_time DESC;

  Confirm the mail actually left the server:
      SELECT TOP (5) sent_status, sent_date, recipients, copy_recipients, subject
      FROM   msdb.dbo.sysmail_allitems
      ORDER  BY mailitem_id DESC;

  Failed sends and the reason:
      SELECT TOP (20) * FROM msdb.dbo.sysmail_event_log ORDER BY log_id DESC;
==============================================================================*/
```

## `sql/jobs/EnsembleSCMGCodingWorklists.sql`

T-SQL weekly job. Self-contained, runs today.

```sql
/*==============================================================================
  EnsembleSCMGCodingWorklists.sql
  Server  : schcent20db01
  Creates : SQL Agent job "JK_EnsembleSCMGCodingWorklists"
  Modeled : on the existing job "JK_EnsembleVisitOwner"

  What it does
  ------------
  One TSQL step that calls msdb.dbo.sp_send_dbmail, running the SCMG coding
  worklist query and attaching the result as a dated .csv.

  NOTE ON "MODELED ON"
  --------------------
  JK_EnsembleVisitOwner is an SSIS job - its step runs a package from
  \SSISDB\EDJobs\EnsembleVisitOwner. This job is NOT an SSIS package; it does
  the same work directly in T-SQL, which needs no package build or deployment.
  What it does inherit from the source job is everything at the Agent level:
  schedule (weekly Mon 04:00), owner, category, failure alert operator, and
  the Database Mail profile.

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
DECLARE @JobName        sysname       = N'JK_EnsembleSCMGCodingWorklists',
        @SourceJob      sysname       = N'JK_EnsembleVisitOwner',
        @Recipients     nvarchar(max) = N'kotrozo@gmail.com',
        @JobEnabled     tinyint       = 1,   -- 1 = job runs on schedule
        @ReplaceExisting bit          = 0,   -- 1 = drop + recreate if it exists
        @UseCsvSafeQuery bit          = 1;   -- 1 = quote/escape text columns
                                             --     (see NOTE at bottom)

/*---- OVERRIDES: leave NULL to inherit from EnsembleVisitOwner --------------*/
DECLARE @DatabaseName   sysname  = N'ED',
        @MailProfile    sysname  = NULL,    -- e.g. N'SQLMail Alerts'
        @CategoryName   sysname  = NULL,
        @OwnerLogin     sysname  = NULL,
        @ScheduleTime   int      = NULL;    -- HHMMSS, e.g. 60000 = 06:00:00

/*==============================================================================
  INHERIT SETTINGS FROM THE SOURCE JOB
==============================================================================*/
DECLARE @SrcCmd       nvarchar(max),
        @SrcDb        sysname,
        @SrcQueryDb   sysname,
        @SrcProfile   sysname,
        @SrcCategory  sysname,
        @SrcOwner     sysname,
        @SrcOperator  sysname,
        @SrcNotifyEmail    tinyint,
        @SrcNotifyEventlog tinyint,
        @q1           int,
        @q2           int;

/* tolerate a prefix/rename on the source job */
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
   AND (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%') = 1
BEGIN
    SELECT @SourceJob = name FROM msdb.dbo.sysjobs WHERE name LIKE N'%EnsembleVisitOwner%';
    PRINT N'Source job resolved to "' + @SourceJob + N'".';
END

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @SourceJob)
    PRINT N'WARNING: source job "' + @SourceJob
        + N'" not found - nothing to inherit; the OVERRIDES block must supply the settings.';

SELECT TOP (1)
        @SrcDb  = NULLIF(s.database_name, N''),
        @SrcCmd = s.command
FROM    msdb.dbo.sysjobs     j
JOIN    msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE   j.name = @SourceJob
  AND   s.command LIKE N'%sp_send_dbmail%'
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

/* an operator alert on failure is only valid if the operator resolved */
IF @SrcOperator IS NULL SET @SrcNotifyEmail = 0;
SET @SrcNotifyEmail    = ISNULL(@SrcNotifyEmail, 0);
SET @SrcNotifyEventlog = ISNULL(@SrcNotifyEventlog, 2);

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

    /*-- same for @execute_query_database. A mail job's step usually runs in
         msdb and names the real application database here, so this is the
         more reliable source of the two.                                    --*/
    SET @q1 = CHARINDEX(N'@execute_query_database', @SrcCmd);
    IF @q1 > 0
    BEGIN
        SET @q1 = CHARINDEX(N'''', @SrcCmd, @q1);
        IF @q1 > 0
        BEGIN
            SET @q2 = CHARINDEX(N'''', @SrcCmd, @q1 + 1);
            IF @q2 > @q1
                SET @SrcQueryDb = SUBSTRING(@SrcCmd, @q1 + 1, @q2 - @q1 - 1);
        END
    END
END

/* the step's own database is only meaningful if it is a real user database */
IF @SrcDb IN (N'msdb', N'master', N'model', N'tempdb') SET @SrcDb = NULL;
IF @SrcQueryDb IS NOT NULL AND DB_ID(@SrcQueryDb) IS NULL SET @SrcQueryDb = NULL;
SET @SrcDb = COALESCE(@SrcQueryDb, @SrcDb);

/* the source may use a variable rather than a literal - only trust a real one */
IF @SrcProfile IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = @SrcProfile)
    SET @SrcProfile = NULL;

IF @SrcDb IS NOT NULL AND DB_ID(@SrcDb) IS NULL
    SET @SrcDb = NULL;

/* an SSIS source job has no @profile_name to parse, so fall back to the
   instance default profile, then to the only profile if there is just one */
IF @SrcProfile IS NULL
    SELECT TOP (1) @SrcProfile = p.name
    FROM   msdb.dbo.sysmail_profile            p
    JOIN   msdb.dbo.sysmail_principalprofile  pp ON pp.profile_id = p.profile_id
    WHERE  pp.is_default = 1;

IF @SrcProfile IS NULL AND (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) = 1
    SELECT @SrcProfile = name FROM msdb.dbo.sysmail_profile;

SELECT  @DatabaseName = COALESCE(@DatabaseName, @SrcDb),
        @MailProfile  = COALESCE(@MailProfile,  @SrcProfile),
        @CategoryName = COALESCE(@CategoryName, @SrcCategory, N'[Uncategorized (Local)]'),
        @OwnerLogin   = COALESCE(@OwnerLogin,   @SrcOwner,    SUSER_SNAME());

/*---- last resort: find the database that actually holds these tables ------*/
DECLARE @Candidates TABLE (name sysname);

IF @DatabaseName IS NULL
BEGIN
    INSERT INTO @Candidates (name)
    SELECT  d.name
    FROM    sys.databases d
    WHERE   d.state = 0              -- ONLINE
      AND   d.database_id > 4        -- skip system databases
      AND   OBJECT_ID(QUOTENAME(d.name) + N'.dbo.PatientVisit')   IS NOT NULL
      AND   OBJECT_ID(QUOTENAME(d.name) + N'.dbo.PatientProfile') IS NOT NULL
      AND   OBJECT_ID(QUOTENAME(d.name) + N'.dbo.MedLists')       IS NOT NULL;

    IF (SELECT COUNT(*) FROM @Candidates) = 1
    BEGIN
        SELECT @DatabaseName = name FROM @Candidates;
        PRINT N'Target database auto-detected by schema: ' + @DatabaseName;
    END
    ELSE IF (SELECT COUNT(*) FROM @Candidates) > 1
    BEGIN
        PRINT N'Several databases contain PatientVisit/PatientProfile/MedLists.';
        PRINT N'Pick one and set @DatabaseName in the OVERRIDES block:';
        SELECT name AS [Candidate databases] FROM @Candidates ORDER BY name;
    END
END

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
PRINT N'Failure alert   : ' + ISNULL(@SrcOperator, N'(none)');
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
         @notify_level_eventlog = @SrcNotifyEventlog,
         @notify_level_email    = @SrcNotifyEmail,      -- inherited: 2 = on failure
         @notify_email_operator_name = @SrcOperator,    -- inherited: e.g. DBA
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
         @name                   = N'EnsembleSCMGCodingWorklists_Schedule',
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
      EXEC msdb.dbo.sp_start_job @job_name = N'JK_EnsembleSCMGCodingWorklists';

  Check the outcome:
      SELECT TOP (5) h.run_date, h.run_time, h.run_status, h.message
      FROM   msdb.dbo.sysjobhistory h
      JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
      WHERE  j.name = 'JK_EnsembleSCMGCodingWorklists'
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
```

## `sql/jobs/EnsembleSCMGCodingWorklistsDaily_SSIS.sql`

SSIS daily job. Needs the package deployed first.

```sql
/*==============================================================================
  EnsembleSCMGCodingWorklistsDaily_SSIS.sql
  Server  : schcent20db01
  Creates : SQL Agent job "JK_EnsembleSCMGCodingWorklistsDaily"
  Clones  : JK_EnsembleVisitOwner (SSIS job, \SSISDB\EDJobs\EnsembleVisitOwner)

  Same clone-the-step-command approach as EnsembleSCMGCodingWorklists_SSIS.sql,
  with one difference: the schedule is NOT inherited. This report runs DAILY at
  04:00, where the source job runs weekly on Mondays.

  Deliberately a separate script rather than a mode flag on the weekly one -
  running the wrong file cannot silently produce the wrong job.

  PREREQUISITE
  ------------
  The SSIS project must already be deployed to \SSISDB\EDJobs. See
  sql/ssis/README.md - this is the second of two packages, the one with the
  daily query and the Ensemble distribution list. This script REFUSES to
  create a job pointing at a package that is not in the catalog.

  Recipients live in the PACKAGE, not here:
      To : Kristie.Stuber@ensemblehp.com, Holly.Aguilar@ensemblehp.com,
           Heather.Russell@ensemblehp.com, Jessica.Apolito@ensemblehp.com
      Cc : Daniel.Krchmar@stclair.org, joe.kotrozo@stclair.org
==============================================================================*/

USE [msdb];
GO

SET NOCOUNT ON;

/*==============================================================================
  SETTINGS
==============================================================================*/
DECLARE @JobName         sysname = N'JK_EnsembleSCMGCodingWorklistsDaily',
        @SourceJob       sysname = N'JK_EnsembleVisitOwner',
        @OldProjectName  sysname = N'EnsembleVisitOwner',                -- text to replace
        @NewProjectName  sysname = N'EnsembleSCMGCodingWorklistsDaily', -- replacement
        @JobEnabled      tinyint = 1,
        @ReplaceExisting bit     = 0;   -- 1 = drop + recreate if it exists

/*---- schedule: DAILY at 04:00 (not inherited) ----------------------------*/
DECLARE @ActiveStartTime int = 40000;   -- HHMMSS

/*==============================================================================
  READ THE SOURCE JOB
==============================================================================*/
DECLARE @SrcCmd       nvarchar(max),
        @SrcSubsystem nvarchar(40),
        @SrcStepDb    sysname,
        @SrcProxyId   int,
        @SrcOnSuccess int,
        @SrcOnFail    int,
        @SrcRetries   int,
        @SrcCategory  sysname,
        @SrcOwner     sysname,
        @SrcOperator  sysname,
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
==============================================================================*/
DECLARE @Path    nvarchar(1000),
        @Folder  sysname,
        @Project sysname,
        @Package sysname,
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

PRINT N'Category        : ' + @SrcCategory;
PRINT N'Owner           : ' + @SrcOwner;
PRINT N'Failure alert   : ' + ISNULL(@SrcOperator, N'(none)');
PRINT N'Schedule        : daily at ' + STUFF(STUFF(RIGHT('000000'
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
         @description                = N'Daily 04:00. Runs the SCMG coding worklist SSIS package and emails the file to the Ensemble coding team. Cloned from JK_EnsembleVisitOwner.',
         @category_name              = @SrcCategory,
         @owner_login_name           = @SrcOwner,
         @notify_level_eventlog      = @SrcNotifyEventlog,
         @notify_level_email         = @SrcNotifyEmail,
         @notify_email_operator_name = @SrcOperator,
         @job_id                     = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
         @job_id            = @JobId,
         @step_name         = N'stepEnsembleSCMGCodingWorklistsDaily',
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
         @job_id            = @JobId,
         @name              = N'schEnsembleSCMGCodingWorklistsDaily',
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
```

## `sql/jobs/EnsembleSCMGCodingWorklists_SSIS.sql`

SSIS weekly job. Needs the package deployed first.

```sql
/*==============================================================================
  EnsembleSCMGCodingWorklists_SSIS.sql
  Server  : schcent20db01
  Creates : SQL Agent job "JK_EnsembleSCMGCodingWorklists"
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
DECLARE @JobName         sysname = N'JK_EnsembleSCMGCodingWorklists',
        @SourceJob       sysname = N'JK_EnsembleVisitOwner',
        @OldProjectName  sysname = N'EnsembleVisitOwner',           -- text to replace
        @NewProjectName  sysname = N'EnsembleSCMGCodingWorklists', -- replacement
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
         @step_name         = N'stepEnsembleSCMGCodingWorklists',
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
         @name                   = N'schEnsembleSCMGCodingWorklists',
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
```

## `sql/ssis/query_daily_coding_worklist.sql`

Daily query, for pasting into the cloned package.

```sql
/*==============================================================================
  SCMG Coding Worklists - DAILY report query

  Same WHERE clause as the weekly report, but a different column set:
    - no CurrentCarrier, no CurrentPICarrierId
    - ApprovalResults in full (not truncated to 255)
    - ORDER BY pv.Visit ASCENDING

  Corrections against the query as supplied:
    - aliases use [brackets] rather than "double quotes", which depend on
      QUOTED_IDENTIFIER being ON
==============================================================================*/

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
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = 'BillStatus'
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = 'VisitOwner'
WHERE   pv.VisitOwnerMId IN ('153669', '153695', '153696')
ORDER BY pv.Visit;
```

## `sql/ssis/query.sql`

Weekly query, for pasting into the cloned package.

```sql
/*==============================================================================
  SCMG Coding Worklists - report query
  Goes into the cloned SSIS package (the OLE DB source / Execute SQL task that
  EnsembleVisitOwner already uses).

  If the existing package's SELECT is already identical, the ONLY edit needed
  is the WHERE clause:

      WHERE pv.VisitOwnerMId IN ('153669', '153695', '153696')

  Two corrections against the query as originally supplied:
    - "order by pv.visit desc and and" -> "ORDER BY pv.Visit DESC"
      (the trailing "and and" was a typo and will not parse)
    - column aliases use [brackets] rather than "double quotes", which depend
      on QUOTED_IDENTIFIER being ON
==============================================================================*/

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
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = 'BillStatus'
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = 'VisitOwner'
WHERE   pv.VisitOwnerMId IN ('153669', '153695', '153696')
ORDER BY pv.Visit DESC;
```

## `sql/ssis/Export-SsisProject.ps1`

Optional: exports the existing project as an .ispac for backup.

```powershell
<#
.SYNOPSIS
    Exports a deployed SSIS project from the SSISDB catalog as an .ispac file.

.DESCRIPTION
    Used to get a copy of EnsembleVisitOwner so it can be cloned into
    EnsembleSCMGCodingWorklists with a different WHERE clause.

    Equivalent GUI path, if you'd rather not run this:
        SSMS -> Integration Services Catalogs -> SSISDB -> EDJobs -> Projects
             -> right-click EnsembleVisitOwner -> Export...

    Run on a machine with SSMS or the SSIS client tools installed, under an
    account with read access to the catalog.

.EXAMPLE
    .\Export-SsisProject.ps1
    .\Export-SsisProject.ps1 -OutFile C:\temp\EnsembleVisitOwner.ispac
#>
[CmdletBinding()]
param(
    [string] $Server  = 'schcent20db01',
    [string] $Folder  = 'EDJobs',
    [string] $Project = 'EnsembleVisitOwner',
    [string] $OutFile = "$PWD\EnsembleVisitOwner.ispac"
)

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName 'Microsoft.SqlServer.Management.IntegrationServices'
}
catch {
    throw ("Could not load the Integration Services management assembly. " +
           "Install SSMS or the SQL Server client tools on this machine, " +
           "or use the SSMS Export... menu path instead. ($($_.Exception.Message))")
}

$connStr = "Data Source=$Server;Initial Catalog=master;Integrated Security=SSPI;"
$conn    = New-Object System.Data.SqlClient.SqlConnection $connStr

try {
    $isSvc = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $conn
    $cat   = $isSvc.Catalogs['SSISDB']
    if (-not $cat) { throw "No SSISDB catalog on $Server." }

    $fld = $cat.Folders[$Folder]
    if (-not $fld) {
        throw "Folder '$Folder' not found. Available: $($cat.Folders.Name -join ', ')"
    }

    $prj = $fld.Projects[$Project]
    if (-not $prj) {
        throw "Project '$Project' not found in '$Folder'. Available: $($fld.Projects.Name -join ', ')"
    }

    [System.IO.File]::WriteAllBytes($OutFile, $prj.GetProjectBytes())

    Write-Host "Exported \SSISDB\$Folder\$Project" -ForegroundColor Green
    Write-Host "     -> $OutFile ($((Get-Item $OutFile).Length) bytes)"
    Write-Host ""
    Write-Host "An .ispac is a zip archive. To inspect it without SSDT:"
    Write-Host "     Expand-Archive -Path '$OutFile' -DestinationPath '.\ispac' -Force"
}
finally {
    if ($conn.State -ne 'Closed') { $conn.Close() }
}
```

