# The following line is important for the installer:
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
function ExpandEnvironmentVariables( $str )
{
    return [System.Environment]::ExpandEnvironmentVariables( $str )
}

# Split out for mocking.
function SetEnvVar( $name, $val )
{
    Set-Content Env:\$name -Value $val
}

# Split out for mocking.
function UpdateCurrentProcessEnvironment
{
    [CmdletBinding()]
    param( $DiffToApply )

    # There are some not-immediately-obvious things we need to consider:
    #
    #   1. Sometimes people embed "unexpanded" environment variable names into other
    #      environment variable values (like putting the literal string "%NVM_HOME%" into
    #      PATH). So we need to handle expanding values.
    #
    #   2. That means there are "dependencies" between setting values! Because if we have
    #      these values:
    #
    #          PATH=C:\windows\system32;%NVM_HOME%
    #          NVM_HOME=C:\whatever
    #
    #      Then it matters what order we set those values in.
    #
    # One way to deal with that would be to try to determine the "correct" order. But
    # there's a simpler algorithm: just keep applying them all, until there are no more
    # changes (given the problem domain, this is unlikely to result in more than a couple
    # extra passes).

    [bool] $madeAChange = $false
    [int] $numPasses = 0
    do
    {
        $numPasses += 1
        if( $numPasses -gt 10 )
        {
            throw "Unexpected: pathological environment variable dependency depth."
        }

        $madeAChange = $false
        foreach( $name in $DiffToApply.Keys )
        {
            $oldVal = GetEnvVar $name 'Process'

            # Handle expanding environment variables:
            $newVal = ExpandEnvironmentVariables ($DiffToApply[ $name ])

            SetEnvVar $name $newVal

            if( $oldVal -ne $newVal )
            {
                $madeAChange = $true
            }
        }

    } while( $madeAChange )
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
                # Write-Verbose "New key: $key"

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
                # Write-Verbose "Updated key: $key"

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
            else
            {
                # Write-Verbose "Unchanged key: $key"
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

#
# Support for winget.cmd:
#

# Writes the "static" (as stored in the registry) environment block (combines
# the Machine and User values) to a file, and returns the path to that file.
# Note that this may be significantly different than the "live" environment
# values in the memory of the current process.
function StoreStaticPathFromRegistry
{
    [CmdletBinding()]
    param()

    try
    {
        $vars = GetAllEnvVarsFromRegistry

        $f = (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())) + '.clixml'

        Export-CliXml -InputObject $vars -Path $f -EA Stop

        return $f
    }
    finally { }
}

# Generates a .cmd script which the calling cmd.exe process can call to update its
# environment. (Returns the path to the .cmd.)
function GenerateAdditionsCmd
{
    [CmdletBinding()]
    param( [string] $PSModulePathVal, [string] $BeforeFile )

    try
    {
        $before = Import-CliXml $BeforeFile -EA Stop
        $after = GetAllEnvVarsFromRegistry

        Write-Verbose "Have before and after now..."

        # The current PS process has updated the PSModulePath environment variable
        # in-memory. But for the cmd.exe process, we don't want to take those
        # modifications into account (they will be gone as soon as we exit). So we are
        # going to replace the current (in-memory) PSModulePath value with the value from
        # our parent cmd.exe process, for diff'ing purposes.
        #
        # (Modifying PSModulePath like this is somewhat risky to the health of the current
        # PowerShell process... but the idea is that this process has already loaded
        # everything it needs, and will be exiting very shortly.)
        $env:PSModulePath=$PSModulePathVal

        $diff = CalculateDiffToApply $before $after

        if( $diff.Count )
        {
            # We will update the environment variables in the current process first, using
            # UpdateCurrentProcessEnvironment, in order to take advantage of the code to
            # expand dependent variables. (See comments in that function.)
            UpdateCurrentProcessEnvironment $diff

            $f = (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())) + '.cmd'

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add( '@ECHO OFF' )

            foreach( $name in $diff.Keys )
            {
                # N.B. We use the already-resolved value, rather than the raw value in
                # $diff[ $name ].
                $lines.Add( "SET $name=$(GetEnvVar $name 'Process')" )
            }

            [System.IO.File]::WriteAllLines( $f, $lines.ToArray() )

            return $f
        }
    }
    finally { }
}

<# Useful for testing winget.cmd: replace the winget.exe there with a call to:

    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command . %~dp0wingetHelper.ps1 ; FakeDoStuff

function FakeDoStuff
{
    [CmdletBinding()]
    param()

    try
    {
        $oldPath = [System.Environment]::GetEnvironmentVariable( 'PATH', 'User' )
        $newPath = $oldPath + ';NEW_VALUE_WOO'
        [System.Environment]::SetEnvironmentVariable( 'PATH', $newPath, 'User' )

        $oldPath = [System.Environment]::GetEnvironmentVariable( 'PSModulePath', 'User' )
        $newPath = $oldPath + ';OTHER_NEW_VALUE_YEAH'
        [System.Environment]::SetEnvironmentVariable( 'PSModulePath', $newPath, 'User' )
    }
    finally { }
}
#>

