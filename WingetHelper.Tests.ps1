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
}
