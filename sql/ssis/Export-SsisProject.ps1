<#
.SYNOPSIS
    Exports a deployed SSIS project from the SSISDB catalog as an .ispac file.

.DESCRIPTION
    Used to get a copy of EnsembleVisitOwner so it can be cloned into
    Ensemble_SCMGCodingWorklists with a different WHERE clause.

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
