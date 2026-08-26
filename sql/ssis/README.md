# Ensemble_SCMGCodingWorklists — SSIS clone procedure

`JK_EnsembleVisitOwner` runs an SSIS package from `\SSISDB\EDJobs\EnsembleVisitOwner`.
The new report is the same package with a different `WHERE` clause, so the path is
clone → edit → deploy → create job.

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

## 1. Get the existing project

Either the GUI:

> SSMS → Integration Services Catalogs → SSISDB → EDJobs → Projects →
> right-click **EnsembleVisitOwner** → **Export…**

or `Export-SsisProject.ps1` in this folder:

```powershell
.\Export-SsisProject.ps1 -OutFile C:\temp\EnsembleVisitOwner.ispac
```

If the project is already in source control, use that copy instead — it will
have the original `.dtproj` and is the better starting point.

## 2. Clone and rename

Open the project in SSDT/Visual Studio, then:

- Save the **project** as `Ensemble_SCMGCodingWorklists`
- Rename the **package** to `Ensemble_SCMGCodingWorklists.dtsx`

Both names matter: the job script builds the new step command by substituting
`EnsembleVisitOwner` → `Ensemble_SCMGCodingWorklists` in the source job's
command, so the deployed path must end up as
`\SSISDB\EDJobs\Ensemble_SCMGCodingWorklists\Ensemble_SCMGCodingWorklists.dtsx`.

If you name them differently, set `@NewProjectName` in
`../jobs/Ensemble_SCMGCodingWorklists_SSIS.sql` to match. The script verifies
the package exists in the catalog before creating the job, so a mismatch fails
loudly instead of producing a job that errors on its first run.

## 3. Change the WHERE clause

In the package's source query, that's the only functional edit:

```sql
WHERE pv.VisitOwnerMId IN ('153669', '153695', '153696')
```

Also update the recipient (currently just you) and the output file name /
email subject wherever the package sets them.

`query.sql` in this folder has the full query if the `SELECT` needs to change
too. Two things there differ from the query as originally supplied:

- `order by pv.visit desc and and` → `ORDER BY pv.Visit DESC`. The trailing
  `and and` was a typo and will not parse.
- Aliases use `[brackets]` instead of `"double quotes"`, which depend on
  `QUOTED_IDENTIFIER` being ON.

One thing worth checking while you're in there: if the package writes a plain
comma-separated file, commas inside `Description` and `ApprovalResults` will
shift every column to their right. A Flat File destination with a text
qualifier of `"` handles it.

## 4. Deploy

Deploy the project to the **EDJobs** folder, alongside the original.

## 5. Create the Agent job

```
../jobs/Ensemble_SCMGCodingWorklists_SSIS.sql
```

Run it on `schcent20db01`. It clones the source job's step command rather than
inventing one, so `/SERVER`, `LOGGING_LEVEL`, `SYNCHRONIZED`, `CALLERINFO` and
`REPORTING` are whatever already works. It prints both the old and new command
before creating anything.

Then test:

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'Ensemble_SCMGCodingWorklists';
```

---

## Alternative: no SSIS at all

`../jobs/Ensemble_SCMGCodingWorklists.sql` creates a self-contained T-SQL job
that does the same work with `sp_send_dbmail` — no package, no deployment. It
is **not** the chosen approach and is kept only as a fallback; it breaks the
EDJobs convention the other Ensemble reports follow.
