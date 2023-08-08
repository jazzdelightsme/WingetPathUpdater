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
       [switch] $Interactive,

       [switch] $InstallTests,

       [switch] $Uninstall
     )

try
{
    Write-Verbose "Force: $Force"
    Write-Verbose "Silent: $Silent"
    Write-Verbose "SilentWithProgress: $SilentWithProgress"
    Write-Verbose "Interactive: $Interactive"

    [bool] $quiet = $Silent -or $SilentWithProgress

    function Test-Administrator
    {
        [CmdletBinding()]
        param()

        try
        {
            $currentUser = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
            return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        finally { }
    }

    # If we are run from winget/ARP, we should be elevated; but in case anybody tries to
    # run this manually...
    if( !(Test-Administrator) )
    {
        throw "This script must be run elevated."
    }

    $baseUrl = 'https://raw.githubusercontent.com/jazzdelightsme/WingetPathUpdater/v1.0/'

    $fileUrls = [ordered] @{
        # We do the wingetHelper.ps1 first, because if there is a problem getting that,
        # the other two won't work.
        "$env:SystemRoot\System32\wingetHelper.ps1" = "${baseUrl}WingetHelper.ps1"
        # The install script is pretty important, too (for uninstall):
        "$env:SystemRoot\System32\WingetPathUpdaterInstall.ps1" = "${baseUrl}WingetPathUpdaterInstall.ps1"
        "$env:SystemRoot\System32\winget.ps1" = "${baseUrl}Winget.ps1"
        "$env:SystemRoot\System32\winget.cmd" = "${baseUrl}Winget.cmd"
    }

    if( $InstallTests -or $Uninstall )
    {
        $fileUrls[ "$env:SystemRoot\System32\wingetHelper.Tests.ps1" ] = "${baseUrl}WingetHelper.Tests.ps1"
    }

    $fileContents = [ordered] @{ }

    foreach( $path in $fileUrls.Keys )
    {
        if( (Test-Path $path) )
        {
            if( !$quiet -and !$Uninstall )
            {
                Write-Host "Found existing file: " -Fore DarkGray -NoNewline
                Write-Host $path -Fore DarkYellow -NoNewline
                Write-Host " ... " -Fore DarkGray -NoNewline
            }

            # If we're pretty sure it came from us, we'll just allow overwriting without
            # -Force.
            if( (Get-Content $path -Raw) -like "*This file is part of the WingetPathUpdater package*" )
            {
                if( !$quiet -and !$Uninstall )
                {
                    Write-Host "Looks like it came from us, so we'll just overwrite."
                }
            }
            else
            {
                if( $Force )
                {
                    if( !$quiet -and !$Uninstall )
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

        if( !$Uninstall )
        {
            $url = $fileUrls[ $path ]

            if( !$quiet )
            {
                Write-Host "fetching: $url" -Fore DarkGray
            }

            # This will be quick; let's not have a flash of progress bar.
            $oldPref = $global:ProgressPreference
            $global:ProgressPreference = 'SilentlyContinue'
            try
            {
                $response = Invoke-WebRequest $url
            }
            finally
            {
                $global:ProgressPreference = $oldPref
            }

            if( $response.StatusCode -ne 200 )
            {
                throw "Failed to download $(Split-Path -Leaf $path) with error $($response.StatusCode). URL: $url"
            }

            $fileContents[ $path ] = $response.Content
        }
    }

    #
    # Ready to go!
    #

    $keyPath ='HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\WingetPathUpdater'

    if( $Uninstall )
    {
        foreach( $path in $fileUrls.Keys )
        {
            if( !$quiet )
            {
                Write-Host "Removing $path" -Fore DarkCyan
            }

            # The file might not actually be there, like for the test file if the original
            # install didn't install the tests (which would be the common case).
            Remove-Item $path -Force -EA Ignore

            # The important thing is that the file is not there now:
            if( (Test-Path $path) )
            {
                Write-Warning "Failed to remove: $path"
            }
        }

        if( !$quiet )
        {
            Write-Host "Removing ARP entry..." -Fore DarkCyan
        }

        $null = reg.exe delete $keyPath /f
        if( $global:LastExitCode )
        {
            # (if it failed, it already wrote a message to stderr, which we did not
            # capture in the assignment to $null)
            throw "Failed: reg.exe delete $keyPath /f"
        }
    }
    else
    {
        # Install!

        $commonOptions = @{
            # Using the Ascii encoding (which we can do because none of our files have any
            # chars > 7bit ascii) sidesteps the problem of the PS 5.1 UTF8 option emitting a
            # BOM.
            Encoding = 'Ascii'
            NoNewline = $true
            ErrorAction = 'Stop'
        }

        foreach( $path in $fileContents.Keys )
        {
            if( !$quiet )
            {
                Write-Host "Creating: " -NoNewline ; Write-Host $path -Fore Cyan
            }
            Set-Content -Path $path -Value $fileContents[ $path ] @commonOptions
        }

        if( !$quiet )
        {
            Write-Host "Creating ARP entry..." -Fore Cyan
        }

        #
        # Since the winget manifest describes how to install an app, you might think that
        # the winget manifest also describes how to *uninstall* the app. But that's not
        # how it works: once an app is installed, winget depends on "Windows" to know what
        # is installed, and how to uninstall it. And so the way we do that is to create an
        # "Add/Remove Programs" entry (which is just a registry key with a bunch of values
        # describing the app, including the uninstall command line).
        #

        $installDate = (Get-Date).ToString('yyyyMMdd')
        $sizeInKb = [int] (($fileContents.Values | Select-Object -ExpandProperty Length | Measure-Object -Sum).Sum / 1kb)

        $null = reg.exe add $keyPath /f
        if( $global:LastExitCode )
        {
            # (if it failed, it already wrote a message to stderr, which we did not
            # capture in the assignment to $null)
            throw "Failed: reg.exe add $keyPath /f"
        }

        # If the first reg operation succeeded, the others should, too, so we'll
        # have abbreviated checks.
        function checkRegResult { if( $global:LastExitCode ) { throw "reg operation failed" } }

        # Perhaps the most important value:
        $null = reg.exe add $keyPath /f /v UninstallString /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command . { try { & \`"$env:SystemRoot\System32\WingetPathUpdaterInstall.ps1\`" -Uninstall -Interactive } catch { Write-Error `$_ ; Start-Sleep -Seconds 10 ; exit -2 } ; exit `$LastExitCode }" ; checkRegResult

        $null = reg.exe add $keyPath /f /v QuietUninstallString /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command . { try { & \`"$env:SystemRoot\System32\WingetPathUpdaterInstall.ps1\`" -Uninstall -Silent } catch { Write-Error `$_ ; Start-Sleep -Seconds 10 ; exit -2 } ; exit `$LastExitCode }" ; checkRegResult

        $null = reg.exe add $keyPath /f /v InstallLocation /d "$env:SystemRoot\System32" ; checkRegResult
        $null = reg.exe add $keyPath /f /v InstallDate /d $installDate ; checkRegResult
        $null = reg.exe add $keyPath /f /v URLInfoAbout /d "https://github.com/jazzdelightsme/WingetPathUpdater" ; checkRegResult
        $null = reg.exe add $keyPath /f /v DisplayName /d WingetPathUpdater ; checkRegResult
        $null = reg.exe add $keyPath /f /v Publisher /d jazzdelightsme ; checkRegResult
        $null = reg.exe add $keyPath /f /v NoModify /t REG_DWORD /d 1 ; checkRegResult
        $null = reg.exe add $keyPath /f /v NoRepair /t REG_DWORD /d 1 ; checkRegResult
        $null = reg.exe add $keyPath /f /v VersionMajor /t REG_DWORD /d 1 ; checkRegResult
        $null = reg.exe add $keyPath /f /v VersionMinor /t REG_DWORD /d 0 ; checkRegResult
        $null = reg.exe add $keyPath /f /v DisplayVersion /d 1.0 ; checkRegResult
        $null = reg.exe add $keyPath /f /v EstimatedSize /t REG_DWORD /d $sizeInKb ; checkRegResult
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

