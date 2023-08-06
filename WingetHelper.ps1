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
