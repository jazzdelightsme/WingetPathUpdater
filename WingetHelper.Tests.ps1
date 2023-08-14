# The following line is important for the installer:
# This file is part of the WingetPathUpdater package.

BeforeAll {
    $parentDir = Split-Path $PSCommandPath -Parent

    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')

    function ResetFakeRegistry
    {
        $script:FakeRegistry = @{
            User = @{
                Path = ''
                PSModulePath = ''
                dircmd = '/a'
                FOO = 'user-override'
            }
            Machine = @{
                Path = 'testPath1;testPath2;testPath3'
                PSModulePath = 'testPsModulePath1'
                windir = 'C:\WINDOWS'
                VIMRUNTIME = 'C:\vim\vim90'
                FOO = 'default-val'
            }
            Process = @{
                Path = 'testPath1;testPath2;testPath3;runtimePath1'
                PSModulePath = 'testPsModulePath1;runtimePsModulePath1'
                windir = 'C:\WINDOWS'
                VIMRUNTIME = 'C:\vim\vim90'
                dircmd = '/a'
                FOO = 'user-override'
            }
        }
    }

    Mock GetAllEnvVars {
        return ($script:FakeRegistry)[ $Target ]
    }

    Mock GetEnvVar {
        return ($script:FakeRegistry)[ $Target ][ $EnvVarName ]
    }

    Mock UpdateCurrentProcessEnvironment {
        # (nothing)
    }

    # Hide the real winget.exe:
    function winget.exe
    {
        # (nothing)
    }
}

Describe 'winget.ps1' {
    BeforeEach {
        ResetFakeRegistry
    }

    It 'should do nothing if not an install command' {

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 some other command

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 0
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 0
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should do nothing if no change in environment' {

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 0
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should update current process paths if install updated paths' {

        $newPaths = 'newPath1;newPath2'
        $newPsModulePaths = 'newPath3'
        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'User' ][ 'PATH' ] = $newPaths
            $script:FakeRegistry[ 'Machine' ][ 'PSModulePath' ] = $newPsModulePaths
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 2 # one for each of the changed vars, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 1 -ParameterFilter {
            ($DiffToApply.Count -eq 2) -and
            $DiffToApply.ContainsKey( 'PATH' ) -and
            $DiffToApply.ContainsKey( 'PSModulePath' ) -and
            # Should just add new paths to end of current in-process value:
            ($DiffToApply[ 'PATH' ] -eq ($script:FakeRegistry[ 'Process' ][ 'PATH' ] + ';' + $newPaths))
            ($DiffToApply[ 'PSModulePath' ] -eq ($script:FakeRegistry[ 'Process' ][ 'PSModulePath' ] + ';' + $newPsModulePaths))
        }
    }

    It 'should not add duplicate paths (already present in-memory)' {

        $newPsModulePaths = 'newPath3'

        # The thing the install adds will already be present in-memory (so the "new" value
        # would be a duplicate).
        $script:FakeRegistry[ 'Process' ][ 'PSModulePath' ] = $newPsModulePaths
        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'Machine' ][ 'PSModulePath' ] = $newPsModulePaths
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetEnvVar' -Exactly 1 -ParameterFilter {
            ($EnvVarName -eq 'PSModulePath') -and
            ($Target -eq 'Process')
        }
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should add brand-new vars' {

        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'User' ][ 'NewUserVar' ] = 'hi'
            $script:FakeRegistry[ 'Machine' ][ 'NewMachineVar' ] = 'hi'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 2 # once for each new var, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 1 -ParameterFilter {
            ($DiffToApply.Count -eq 2) -and
            $DiffToApply.ContainsKey( 'NewUserVar' ) -and
            $DiffToApply.ContainsKey( 'NewMachineVar' ) -and
            ($DiffToApply[ 'NewUserVar' ] -eq 'hi') -and
            ($DiffToApply[ 'NewMachineVar' ] -eq 'hi')
        }
    }

    It 'should skip new vars that match in-memory values' {

        # The var that winget is going to add to the registry is already in-memory:
        $script:FakeRegistry[ 'Process' ][ 'NewUserVar' ] = 'hi'

        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'User' ][ 'NewUserVar' ] = 'hi'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 1 # once for each new var, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should NOT add new vars that conflict with in-memory values' {

        # The var that winget is going to add to the registry is already in-memory (but
        # with a different value):
        $script:FakeRegistry[ 'Process' ][ 'NewUserVar' ] = 'something else'

        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'User' ][ 'NewUserVar' ] = 'hi'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 1 # once for each new var, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should update vars that were not customized in-memory' {

        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'Machine' ][ 'VIMRUNTIME' ] = 'hi'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 1 # once for each new var, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 1 -ParameterFilter {
            ($DiffToApply.Count -eq 1) -and
            $DiffToApply.ContainsKey( 'VIMRUNTIME' ) -and
            ($DiffToApply[ 'VIMRUNTIME' ] -eq 'hi')
        }
    }

    It 'should NOT update vars that WERE customized in-memory' {

        # The var that winget is going to update in the registry has been modified
        # in-memory:
        $script:FakeRegistry[ 'Process' ][ 'VIMRUNTIME' ] = 'something else'

        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'Machine' ][ 'VIMRUNTIME' ] = 'hi'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetAllEnvVars' -Exactly 4 # 2 for "before", 2 for "after"
        Should -Invoke -CommandName 'GetEnvVar' -Exactly 1 # once for each new var, to check in-memory value
        Should -Invoke -CommandName 'UpdateCurrentProcessEnvironment' -Exactly 0
    }

    It 'should handle dependencies between values' {

        # Need to remove the do-nothing mock:
        Remove-Item Alias:\UpdateCurrentProcessEnvironment -Force

        Mock SetEnvVar {
            $script:FakeRegistry[ 'Process' ][ $name ] = $val
        }

        Mock ExpandEnvironmentVariables {
            # Note that we might not handle pathological cases (like a single '%' in
            # multiple paths in PATH) the same way as the system might... but that's not
            # important for testing.

            $mc = [regex]::Matches( $str, '%(?<varName>[^;%]*)%' )

            if( $mc.Count -eq 0 )
            {
                return $str
            }

            # We'll walk through the matches, copying from the source string and then
            # from the match (if applicable).
            $dest = [System.Text.StringBuilder]::new()

            $lastIdx = 0 # last index that we accounted for from the source string
            for( [int] $i = 0; $i -lt $mc.Count; $i++ )
            {
                $m = $mc[ $i ]

                # Take anything from the source string (that we haven't taken already), up
                # to this match:
                $null = $dest.Append( $str, $lastIdx, ($m.Index - $lastIdx) )

                # Q: Does the environment variable actually have a value?
                $varName = $m.Groups['varName'].Value

                if( $script:FakeRegistry[ 'Process' ].ContainsKey( $varName ) )
                {
                    # A: It does!
                    $val = $script:FakeRegistry[ 'Process' ][ $varName ]
                    $null = $dest.Append( $val )
                }
                else
                {
                    # A: It does not.
                    $null = $dest.Append( $str, $m.Index, $m.Length )
                }

                $lastIdx = $m.Index + $m.Length
            }

            # Remember to get the last bit from the source:
            if( $lastIdx -lt $str.Length )
            {
                $null = $dest.Append( $str, $lastIdx, $str.Length - $lastIdx )
            }

            return $dest.ToString()
        }

        # Self-test our mock:

        ExpandEnvironmentVariables '' | Should -Be ''
        ExpandEnvironmentVariables 'hi' | Should -Be 'hi'
        ExpandEnvironmentVariables '%hi%' | Should -Be '%hi%'
        ExpandEnvironmentVariables '%%' | Should -Be '%%'
        ExpandEnvironmentVariables '%' | Should -Be '%'
        ExpandEnvironmentVariables 'x%hi%x' | Should -Be 'x%hi%x'
        ExpandEnvironmentVariables 'dircmd' | Should -Be 'dircmd'
        ExpandEnvironmentVariables '%dircmd' | Should -Be '%dircmd'
        ExpandEnvironmentVariables 'dircmd%' | Should -Be 'dircmd%'
        ExpandEnvironmentVariables '%dircmd%' | Should -Be '/a'
        ExpandEnvironmentVariables 'x%dircmd%x' | Should -Be 'x/ax'
        ExpandEnvironmentVariables '%FOO%' | Should -Be 'user-override'
        ExpandEnvironmentVariables '%foo%' | Should -Be 'user-override'
        ExpandEnvironmentVariables '%FOO%FOO%' | Should -Be 'user-overrideFOO%'
        ExpandEnvironmentVariables '%FOO%%FOO%' | Should -Be 'user-overrideuser-override'
        ExpandEnvironmentVariables '%FOO%;%dircmd%' | Should -Be 'user-override;/a'
        ExpandEnvironmentVariables '%FOO%;%dircmd%;%notDefinedYet%' | Should -Be 'user-override;/a;%notDefinedYet%'

        # Okay, now we can test our winget wrapper:

        Mock winget.exe {
            # Simulate install updating the registry with values that depend on each
            # other:
            $script:FakeRegistry[ 'Machine' ][ 'BASE_THING' ] = 'hi'
            $script:FakeRegistry[ 'Machine' ][ 'VIMRUNTIME' ] = '%BASE_THING%-there'
            $script:FakeRegistry[ 'Machine' ][ 'Path' ] = $script:FakeRegistry[ 'Machine' ][ 'Path' ] + ';%VIMRUNTIME%'

            # For fun, let's try some crazier scenarios:
            $script:FakeRegistry[ 'Machine' ][ 'A' ] = 'found it'
            $script:FakeRegistry[ 'Machine' ][ 'B' ] = '%A%'
            $script:FakeRegistry[ 'Machine' ][ 'C' ] = '%B%'
            $script:FakeRegistry[ 'Machine' ][ 'D' ] = '%C%'

            # Note that something like this does not work (where "work" would mean "I"
            # eventually gets set to "hi"): we don't handle recursive definitions like
            # this. However, the system doesn't either, so we *shouldn't*.
          # $script:FakeRegistry[ 'Machine' ][ 'E' ] = 'hi'
          # $script:FakeRegistry[ 'Machine' ][ 'F' ] = 'E'
          # $script:FakeRegistry[ 'Machine' ][ 'G' ] = 'F'
          # $script:FakeRegistry[ 'Machine' ][ 'H' ] = 'G'
          # $script:FakeRegistry[ 'Machine' ][ 'I' ] = '%%%%H%%%%'
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        $script:FakeRegistry[ 'Process' ][ 'BASE_THING' ] | Should -Be 'hi'
        $script:FakeRegistry[ 'Process' ][ 'VIMRUNTIME' ] | Should -Be 'hi-there'
        $script:FakeRegistry[ 'Process' ][ 'Path' ] | Should -Be 'testPath1;testPath2;testPath3;runtimePath1;hi-there'

        $script:FakeRegistry[ 'Process' ][ 'A' ] | Should -Be 'found it'
        $script:FakeRegistry[ 'Process' ][ 'B' ] | Should -Be 'found it'
        $script:FakeRegistry[ 'Process' ][ 'C' ] | Should -Be 'found it'
        $script:FakeRegistry[ 'Process' ][ 'D' ] | Should -Be 'found it'
    }
}
