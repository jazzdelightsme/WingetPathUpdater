# This wrapper script is a straight "pass-through" to winget.exe, and then after running
# an install, it will update your in-process environment variables (in your current
# shell).
#
# The following line is important for the installer:
# This file is part of the WingetPathUpdater package.
#
# N.B. This is a "simple function" (as opposed to an "advanced function") (no
# "[CmdletBinding()]" attribute). This is important so that the PowerShell parameter
# binder does not get involved, and we can pass everything straight to winget.exe as-is.

try
{
    $varsBefore = $null
    if( $args -and ($args.Length -gt 0) -and ($args[ 0 ] -eq 'install') )
    {
        . $PSScriptRoot\wingetHelper.ps1

        $varsBefore = GetAllEnvVarsFromRegistry
    }

    winget.exe @args

    if( $varsBefore )
    {
        UpdateCurrentProcessPathBasedOnDiff $varsBefore
    }
}
catch
{
    Write-Error $_
}
