<#
.SYNOPSIS
    Install script for the WingetPathUpdater winget package.
#>
[CmdletBinding( DefaultParameterSetName = 'AllParams' )]
param( [switch] $Force,

       [Parameter( Mandatory, ParameterSetName = 'Silent' )]
       [switch] $Silent,

       [Parameter( Mandatory, ParameterSetName = 'SilentWithProgress' )]
       [switch] $SilentWithProgress,

       [Parameter( Mandatory, ParameterSetName = 'Interactive' )]
       [switch] $Interactive
     )

try
{
    $cmdWrapperContent = @'
@ECHO off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM This wrapper script is a straight "pass-through" to winget.exe, and then after running
REM an install, it will update your in-process PATH environment variable.

REM This file is part of the WingetPathUpdater package.

IF "%1" == "install" (
    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command . %~dp0wingetHelper.ps1 ; GetStaticPathFromRegistry PATH
    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET StaticPathBefore=%%i
    )
)

winget.exe %*

IF NOT "%StaticPathBefore%" == "" (
    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET StaticPathAfter=%%i
    )

    SET TheHelperCommand=powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command . %~dp0wingetHelper.ps1 ; CalculateAdditions 'PATH' '%StaticPathBefore%' '!StaticPathAfter!'

    FOR /F "tokens=* USEBACKQ" %%i IN (`!TheHelperCommand!`) DO (
        SET Additions=%%i
    )
    REM ECHO Additions are: !Additions!
)

IF NOT "%Additions%" == "" (
    ENDLOCAL & SET PATH=%PATH%;%Additions%
)
'@

###########################################################################
###########################################################################
###########################################################################

    $ps1WrapperContent = @'
# This wrapper script is a straight "pass-through" to winget.exe, and then after running
# an install, it will update your in-process Path environment variables (in your current
# shell).
#
# This file is part of the WingetPathUpdater package.
#
# N.B. This is a "simple function" (as opposed to an "advanced function") (no
# "[CmdletBinding()]" attribute). This is important so that the PowerShell parameter
# binder does not get involved, and we can pass everything straight to winget.exe as-is.

try
{
    $pathBefore = ''
    $psModulePathBefore = ''
    if( $args -and ($args.Length -gt 0) -and ($args[ 0 ] -eq 'install') )
    {
        . $PSScriptRoot\wingetHelper.ps1

        $pathBefore = GetStaticPathFromRegistry 'PATH'
        $psModulePathBefore = GetStaticPathFromRegistry 'PSModulePath'
    }

    winget.exe @args

    if( $pathBefore )
    {
        UpdateCurrentProcessPathBasedOnDiff 'PATH' $pathBefore
        UpdateCurrentProcessPathBasedOnDiff 'PSModulePath' $psModulePathBefore
    }
}
catch
{
    Write-Error $_
}
'@

###########################################################################
###########################################################################
###########################################################################

    $ps1HelperContent = @'
# This file is part of the WingetPathUpdater package.
#
# Split out for mocking.
function GetEnvVar
{
    [CmdletBinding()]
    param( $EnvVarName, $Target )

    # (the cast is so that a null return value gets converted to an empty string)
    return [string] ([System.Environment]::GetEnvironmentVariable( $EnvVarName, $Target ))
}

# Gets the "static" (as stored in the registry) value of a specified PATH-style
# environment variable (combines the Machine and User values with ';'). Note that this may
# be significantly different than the "live" environment value in the memory of the
# current process.
function GetStaticPathFromRegistry
{
    [CmdletBinding()]
    param( $EnvVarName )

    (@( 'Machine', 'User' ) | ForEach-Object { GetEnvVar $EnvVarName $_ }) -join ';'
}

# Split out for mocking.
function UpdateCurrentProcessPath
{
    [CmdletBinding()]
    param( $EnvVarName, $Additions )

    Set-Content Env:\$EnvVarName -Value ((Get-Content Env:\$EnvVarName) + ';' + $additions)
}

function UpdateCurrentProcessPathBasedOnDiff
{
    [CmdletBinding()]
    param( $EnvVarName, $Before )

    $pathAfter = GetStaticPathFromRegistry $EnvVarName

    $additions = CalculateAdditions $EnvVarName $Before $pathAfter

    if( $additions )
    {
        UpdateCurrentProcessPath $EnvVarName $additions
    }
}

# Given two strings representing PATH-like environment variables (a set of strings
# separated by ';'), returns the PATHs that are present in the second ($After) but not in
# the first ($Before) and not in the current (in-memory) variable, in PATH format (joined
# by ';'). (Does not do anything about removals or reordering.)
function CalculateAdditions
{
    [CmdletBinding()]
    param( [string] $EnvVarName, [string] $Before, [string] $After )

    try
    {
        $additions = @()
        $setBefore = @( $Before.Split( ';' ) )
        $currentInMemory = @( (GetEnvVar $EnvVarName 'Process').Split( ';' ) )

        foreach( $p in $After.Split( ';' ) )
        {
            if( ($setBefore -notcontains $p) -and ($currentInMemory -notcontains $p) )
            {
                $additions += $p
            }
        }

        return $additions -join ';'
    }
    finally { }
}
'@

###########################################################################
###########################################################################
###########################################################################

    Write-Verbose "Force: $Force"
    Write-Verbose "Silent: $Silent"
    Write-Verbose "SilentWithProgress: $SilentWithProgress"
    Write-Verbose "Interactive: $Interactive"

    [bool] $quiet = $Silent -or $SilentWithProgress

    $fileMap = [ordered] @{
        # We do the wingetHelper.ps1 first, because if there is a problem getting that,
        # the other two won't work.
        "$env:SystemRoot\System32\wingetHelper.ps1" = $ps1HelperContent
        "$env:SystemRoot\System32\winget.cmd" = $cmdWrapperContent
        "$env:SystemRoot\System32\winget.ps1" = $ps1WrapperContent
    }

    foreach( $path in $fileMap.Keys )
    {
        if( (Test-Path $path) )
        {
            if( !$quiet )
            {
                Write-Host "Found existing file: " -Fore DarkGray -NoNewline
                Write-Host $path -Fore DarkYellow -NoNewline
                Write-Host " ... " -Fore DarkGray -NoNewline
            }

            # If we're pretty sure it came from us, we'll just allow overwriting without
            # -Force.
            if( (Get-Content $path -Raw) -like "*This file is part of the WingetPathUpdater package*" )
            {
                if( !$quiet )
                {
                    Write-Host "Looks like it came from us, so we'll just overwrite."
                }
            }
            else
            {
                if( $Force )
                {
                    if( !$quiet )
                    {
                        Write-Host "Honoring -Force switch to allow overwriting." -Fore Yellow
                    }
                }
                else
                {
                    if( !$quiet )
                    {
                        Write-Host "I don't recognize this file; use -Force if you want to clobber it." -Fore Yellow
                    }
                    throw "File already exists: $path"
                }
            }
        }
    }

    # Okay, let's go!

    $commonOptions = @{
        # Using the Ascii encoding sidesteps the problem of the PS 5.1 UTF8 option emitting a
        # BOM.
        Encoding = 'Ascii'
        NoNewline = $true
        ErrorAction = 'Stop'
    }

    foreach( $path in $fileMap.Keys )
    {
        if( !$quiet )
        {
            Write-Host "Creating: " -NoNewline ; Write-Host $path -Fore Cyan
        }
        Set-Content -Path $path -Value $fileMap[ $path ] @commonOptions
    }

    if( !$quiet )
    {
        Write-Host "All done!" -Fore Green

        if( $Interactive )
        {
            Write-Host "(hit any key to exit...)" -Fore DarkGray
            $null = Read-Host
        }
        else
        {
            # Give someone a chance to see the success message.
            Start-Sleep -Seconds 3
        }
    }
}
catch
{
    Write-Error $_

    if( $Interactive )
    {
        Write-Host "(hit any key to exit...)" -Fore DarkGray
        $null = Read-Host
    }
    else
    {
        # Give someone a chance to see the error message.
        Start-Sleep -Seconds 10
    }

    exit -1
}

