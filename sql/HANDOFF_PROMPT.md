# Handoff prompt

Paste everything below the line into Claude Code on a machine that can reach
`schcent20db01`.

---

I need two SQL Agent jobs created on **schcent20db01**. You have access to that
server; verify everything against it rather than trusting the details below,
which come from an earlier session that had no connectivity.

## Existing work

Scripts are already written and pushed to GitHub:

- repo `kotrozo/github-slideshow`, branch `claude/ensemble-scmgcodingworklists-job-rl49ft`
- everything is under `sql/`

Start by reading `sql/ssis/README.md`, then the scripts in `sql/jobs/`. They are
untested — nothing has ever been run against the server. Treat them as a
starting point, not as known-good. Fix what's wrong.

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
| `JK_Ensemble_SCMGCodingWorklists` | `Ensemble_SCMGCodingWorklists` | weekly, Mon 04:00 |
| `JK_Ensemble_SCMGCodingWorklistsDaily` | `Ensemble_SCMGCodingWorklistsDaily` | daily 04:00 |

**Ask me before creating anything**: my other jobs are `JK_EnsembleVisitOwner`
and `JK_EnsembleOfficeProviderCode`, with no underscore after `Ensemble`. I may
want `JK_EnsembleSCMGCodingWorklists` / `JK_EnsembleSCMGCodingWorklistsDaily`
instead. Confirm which, then use it consistently.

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

`sql/jobs/Ensemble_SCMGCodingWorklists*.sql` (no `_SSIS`) are self-contained
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
