<#
.SYNOPSIS
    Runs the tests, including checking code coverage.

    This file is part of the WingetPathUpdater package.
#>
[CmdletBinding()]
param()

try
{
    pushd $PSScriptRoot

    if( !(Get-Module Pester) )
    {
        Import-Module Pester
    }

    $pesterMod = Get-Module Pester

    if( $pesterMod.Version -lt ([Version] '5.4.1') )
    {
        throw "You need a newer Pester: Install-Module Pester -Force -SkipPublisherCheck"
    }

    Remove-Item .\coverage.xml -Force -EA Ignore
    $result = invoke-pester .\WingetHelper.Tests.ps1 -CodeCoverage .\WingetHelper.ps1 -PassThru

    # These commands *should* NOT be covered by code coverage:
    $shouldBeMissed = @(
        # These are mocked:
        'GetAllEnvVars',
        'GetEnvVar',
        'UpdateCurrentProcessEnvironment'

        # Only used by winget.cmd (winget.cmd tested manually):
        'StoreStaticPathFromRegistry'
        'GenerateAdditionsCmd'
    )

    $missedCodePaths = @( $result.CodeCoverage.CommandsMissed | Where-Object Function -NotIn $shouldBeMissed )

    if( $missedCodePaths.Count )
    {
        Write-Host "`nUh-oh; missed code paths:" -Fore Red

        $missedCodePaths | Format-Table Function, Line, Command
    }
    else
    {
        Write-Host "(code coverage: no [important] missed code paths)" -Fore DarkGreen
    }
}
catch
{
    Write-Error $_
}
finally
{
    popd
}

