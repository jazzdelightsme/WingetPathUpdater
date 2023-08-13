# This file is part of the WingetPathUpdater package.
#
# Split out for mocking.
function GetAllEnvVars
{
    [CmdletBinding()]
    param( $Target )

    return [System.Environment]::GetEnvironmentVariables( $Target )
}

# Split out for mocking.
function GetEnvVar
{
    [CmdletBinding()]
    param( $EnvVarName, $Target )

    # (the cast is so that a null return value gets converted to an empty string)
    return [string] ([System.Environment]::GetEnvironmentVariable( $EnvVarName, $Target ))
}

# Split out for mocking.
function UpdateCurrentProcessEnvironment
{
    [CmdletBinding()]
    param( $DiffToApply )

    foreach( $name in $DiffToApply.Keys )
    {
        Set-Content Env:\$name -Value ($DiffToApply[ $name ])
    }
}


function UpdateCurrentProcessPathBasedOnDiff
{
    [CmdletBinding()]
    param( $VarsBefore )

    $after = GetAllEnvVarsFromRegistry

    $diff = CalculateDiffToApply $VarsBefore $after

    if( $diff.Count )
    {
        UpdateCurrentProcessEnvironment $diff
    }
}

function Test-IsPathLikeVar
{
    [CmdletBinding()]
    param( $VarName )

    return @( 'PATH', 'PSModulePath' ) -contains $VarName
}

# Returns a hashtable of environment variables that need to be applied. We only handle
# additions (new variables, or added paths to PATH-like variables) and updates (changes to
# existing variables) (so no deletions, nor ordering changes).
function CalculateDiffToApply
{
    [CmdletBinding()]
    param( $Before, $After )

    try
    {
        $diff = @{}

        foreach( $key in $After.Keys )
        {
            if( !$Before.ContainsKey( $key ) )
            {
                $currentInMemory = GetEnvVar $key 'Process'

                if( $currentInMemory )
                {
                    if( $currentInMemory -eq $After[ $key ] )
                    {
                        # The "new" key is actually already present in memory; nothing to
                        # do.
                    }
                    else
                    {
                        Write-Verbose "New environment variable '$key' conflicts with in-memory value; skipping."
                    }
                }
                else
                {
                    $diff.Add( $key, $After[ $key ] )
                }
            }
            elseif( $Before[ $key ] -ne $After[ $key ] )
            {
                if( Test-IsPathLikeVar $key )
                {
                    $addedPaths = @()
                    $setBefore = @( $Before[ $key ].Split( ';', [System.StringSplitOptions]::RemoveEmptyEntries ) )
                    $currentInMemory = GetEnvVar $key 'Process'
                    $currentInMemoryList = @( $currentInMemory.Split( ';', [System.StringSplitOptions]::RemoveEmptyEntries ) )

                    foreach( $p in $After[ $key ].Split( ';', [System.StringSplitOptions]::RemoveEmptyEntries ) )
                    {
                        if( ($setBefore -notcontains $p) -and ($currentInMemoryList -notcontains $p) )
                        {
                            $addedPaths += $p
                        }
                    }

                    # Q: But we checked that $Before[ $key ] was not the same as
                    #    $After[ $key ]. How could $addedPaths be empty?
                    #
                    # A: Many ways!
                    #      * There could have been an insignificant text difference (like
                    #        an extra ';').
                    #      * The difference could be due to something that got *removed*
                    #        (we only handle additions).
                    #      * The difference may already be present in the in-memory value.
                    #
                    if( $addedPaths.Count )
                    {
                        # Note on the pipeline: need to unroll the $addedPaths array
                        $diff[ $key ] = ($currentInMemory, $addedPaths | ForEach-Object { $_ }) -join ';'
                    }
                }
                else
                {
                    # What to do?
                    #
                    # Well... how about: if the current in-memory value matches the
                    # "before" value, then we'll apply the "after" value. (Else the value
                    # was already customized in-memory, and we'd better not fiddle with
                    # it.)

                    $currentInMemory = GetEnvVar $key 'Process'
                    if( $currentInMemory -eq $Before[ $key ] )
                    {
                        $diff[ $key ] = $After[ $key ]
                    }
                    else
                    {
                        Write-Verbose "Updated environment variable '$key' conflicts with in-memory value; skipping."
                    }
                }
            }
        }

        return $diff
    }
    finally { }
}

function GetAllEnvVarsFromRegistry
{
    $allMachine = GetAllEnvVars 'Machine'
    $allUser = GetAllEnvVars 'User'

    # We want to do the combining up-front (before doing diff calculations), because for
    # non-PATH-like variables, User values override Machine values, so a change in a
    # Machine-level value may turn out to become a no-op because it's overridden by a user
    # var.

    # We copy into a fresh hashtable, because PS's hashtables are case-insenstive by
    # default, whereas the hashtable from [Environment]::GetEnvironmentVariables() is
    # case-*sensitive*.
    $combined = @{}
    $allMachine.Keys | ForEach-Object { $combined[ $_ ] = $allMachine[ $_ ] }

    foreach( $key in $allUser.Keys )
    {
        if( $allMachine.ContainsKey( $key ) -and (Test-IsPathLikeVar $key) )
        {
            $combined[ $key ] = @( $allMachine[ $key ], $allUser[ $key ] ) -join ';'
        }
        else
        {
            $combined[ $key ] = $allUser[ $key ]
        }
    }

    return $combined
}

