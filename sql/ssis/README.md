# SCMG Coding Worklists — SSIS clone procedure

`JK_EnsembleVisitOwner` runs an SSIS package from `\SSISDB\EDJobs\EnsembleVisitOwner`.
Both new reports are that same package with a different query, so the path is
clone → edit → deploy → create job. Run it twice, once per report.

| Agent job | SSIS project / package | Runs | Query | Goes to |
|---|---|---|---|---|
| `JK_EnsembleSCMGCodingWorklists` | `EnsembleSCMGCodingWorklists` | weekly, Mon 04:00 | `query.sql` | you |
| `JK_EnsembleSCMGCodingWorklistsDaily` | `EnsembleSCMGCodingWorklistsDaily` | daily 04:00 | `query_daily_coding_worklist.sql` | Ensemble coding team |

The two queries share a `WHERE` clause and differ in their column list and sort:
the daily one drops `CurrentCarrier` / `CurrentPICarrierId`, keeps
`ApprovalResults` untruncated, and sorts by `pv.Visit` ascending.

**Daily distribution list** (set in the package's mail task, not in the Agent job):

- **To** — Kristie.Stuber@ensemblehp.com, Holly.Aguilar@ensemblehp.com,
  Heather.Russell@ensemblehp.com, Jessica.Apolito@ensemblehp.com
- **Cc** — Daniel.Krchmar@stclair.org, joe.kotrozo@stclair.org

`@ensemblehp.com` is external. Confirm the profile relays off-domain before the
first scheduled run, and check `msdb.dbo.sysmail_event_log` — a blocked relay
shows up there while the job still reports success.

The target database is **ED**.

Note the naming split, which follows `JK_EnsembleVisitOwner` →
`\SSISDB\EDJobs\EnsembleVisitOwner`: the **Agent job** carries the `JK_`
prefix, the **SSIS project and package** do not.

## What the source job looks like

| | |
|---|---|
| Job | `JK_EnsembleVisitOwner` |
| Step | `stepEnsembleVisitOwner`, subsystem **SSIS**, `/ISSERVER "\"\SSISDB\EDJobs\EnsembleVisitOwner\…"` |
| Schedule | `schEnsembleVisitOwner` — weekly, **Mondays at 04:00** |
| Owner | `ST_CLAIR\jkotrozoadm` |
| Category | `[Uncategorized (Local)]` |
| On failure | emails operator **DBA** (`DBAlerts@stclair.org`) |
| Mail profile | `SQLMail Alerts` (instance default) |

The new job inherits all of the above.

## 1. Get the existing project into Visual Studio

If the project is already in source control, use that copy — it has the
original `.dtproj` and is the best starting point. Otherwise:

> **File → New → Project → "Integration Services Import Project Wizard"**

An `.ispac` cannot be opened directly — it's a deployment artifact, not a
project file. This wizard converts one back into an editable project. It
accepts either source:

- **Integration Services Catalog** — point it at `schcent20db01`, folder
  `EDJobs`, project `EnsembleVisitOwner`. No export needed.
- **Project deployment file** — an `.ispac` you exported first, via SSMS
  (Integration Services Catalogs → SSISDB → EDJobs → Projects → right-click
  → **Export…**) or `Export-SsisProject.ps1` in this folder:

  ```powershell
  .\Export-SsisProject.ps1 -OutFile C:\temp\EnsembleVisitOwner.ispac
  ```

Since the wizard reads the catalog directly, the export is only worth doing
to keep a backup of the original before you start.

Requires the **SQL Server Integration Services Projects** extension (VS
Marketplace, for VS 2019/2022) or SSDT on older versions — without it the
project template does not exist.

To just read an `.ispac` without Visual Studio: it's a zip. Copy it, rename
to `.zip` and extract — you get the `.dtsx` files, `Project.params` and
`@Project.manifest` as plain XML. Fine for inspection; don't edit and re-zip
for this job, since renaming the project properly means editing the manifest.

## 2. Clone and rename

Save the **project** and the **package** under the same name — either
`EnsembleSCMGCodingWorklists` or `EnsembleSCMGCodingWorklistsDaily`
depending on which report you're building.

Both names matter: the job script builds its step command by substituting
`EnsembleVisitOwner` → the new name in the source job's command, so the
deployed path must end up as, for the daily report,
`\SSISDB\EDJobs\EnsembleSCMGCodingWorklistsDaily\EnsembleSCMGCodingWorklistsDaily.dtsx`.

If you name them differently, set `@NewProjectName` in the matching job script
to suit. Each script verifies the package exists in the catalog before creating
the job, so a mismatch fails loudly instead of producing a job that errors on
its first run.

## 3. Change the query and recipients

For the weekly report the `WHERE` clause is the only functional edit:

```sql
WHERE pv.VisitOwnerMId IN ('153669', '153695', '153696')
```

For the daily one the column list and sort change too — paste in
`query_daily_coding_worklist.sql` wholesale.

Then update the recipients, output file name and email subject wherever the
package sets them. The daily list is in the table at the top of this file;
the weekly one goes to you alone for now.

Both query files differ from the queries as originally supplied:

- `order by pv.visit desc and and` → `ORDER BY pv.Visit DESC` (weekly). The
  trailing `and and` was a typo and will not parse.
- Aliases use `[brackets]` instead of `"double quotes"`, which depend on
  `QUOTED_IDENTIFIER` being ON.

One thing worth checking while you're in there: if the package writes a plain
comma-separated file, commas inside `Description` and `ApprovalResults` will
shift every column to their right. A Flat File destination with a text
qualifier of `"` handles it. This matters more for the daily report, which
keeps `ApprovalResults` untruncated.

## 4. Deploy

Deploy the project to the **EDJobs** folder, alongside the original.

## 5. Create the Agent job

```
../jobs/EnsembleSCMGCodingWorklists_SSIS.sql        -- weekly, Mon 04:00
../jobs/EnsembleSCMGCodingWorklistsDaily_SSIS.sql   -- daily 04:00
```

Run the matching one on `schcent20db01`. Each clones the source job's step
command rather than inventing one, so `/SERVER`, `LOGGING_LEVEL`,
`SYNCHRONIZED`, `CALLERINFO` and `REPORTING` are whatever already works, and
each prints the old and new command before creating anything.

The weekly script inherits the source job's schedule (weekly Mondays). The
daily script does not — it sets daily 04:00 explicitly.

Then test:

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'JK_EnsembleSCMGCodingWorklistsDaily';
```

For the daily report, test it before the first scheduled run: create it with
`@JobEnabled = 0`, point the package's mail task at your own address, confirm
the file looks right, then set the real list and enable.

---

## Alternative: no SSIS at all

Both reports also exist as self-contained T-SQL jobs that do the same work with
`sp_send_dbmail` — no package, no deployment:

- `../jobs/EnsembleSCMGCodingWorklists.sql`
- `../jobs/EnsembleSCMGCodingWorklistsDaily.sql` (recipients already filled in)

These are **not** the chosen approach and are kept only as a fallback; they
break the EDJobs convention the other Ensemble reports follow. They are
runnable today, so they're useful for proving out the query or the mail relay
before the packages are built.
