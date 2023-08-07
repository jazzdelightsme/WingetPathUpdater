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

       [switch] $InstallTests
     )

try
{

    Write-Verbose "Force: $Force"
    Write-Verbose "Silent: $Silent"
    Write-Verbose "SilentWithProgress: $SilentWithProgress"
    Write-Verbose "Interactive: $Interactive"

    [bool] $quiet = $Silent -or $SilentWithProgress

    $baseUrl = 'https://raw.githubusercontent.com/jazzdelightsme/WingetPathUpdater/main/'

    $fileUrls = [ordered] @{
        # We do the wingetHelper.ps1 first, because if there is a problem getting that,
        # the other two won't work.
        "$env:SystemRoot\System32\wingetHelper.ps1" = "${baseUrl}WingetHelper.ps1"
        "$env:SystemRoot\System32\winget.ps1" = "${baseUrl}Winget.ps1"
        "$env:SystemRoot\System32\winget.cmd" = "${baseUrl}Winget.cmd"
    }

    if( $InstallTests )
    {
        $fileUrls[ "$env:SystemRoot\System32\wingetHelper.Tests.ps1" ] = "${baseUrl}WingetHelper.Tests.ps1"
    }

    $fileContents = [ordered] @{ }

    foreach( $path in $fileUrls.Keys )
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

        $url = $fileUrls[ $path ]

        if( !$quiet )
        {
            Write-Host "fetching: $url" -Fore DarkGray
        }

        $response = Invoke-WebRequest $url

        if( $response.StatusCode -ne 200 )
        {
            throw "Failed to download $(Split-Path -Leaf $path) with error $($response.StatusCode). URL: $url"
        }

        $fileContents[ $path ] = $response.Content
    }

    #
    # We have all the files, let's go!
    #

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

