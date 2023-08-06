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
            }
            Machine = @{
                Path = 'testPath1;testPath2;testPath3'
                PSModulePath = 'testPsModulePath1'
            }
            Process = @{
                Path = 'testPath1;testPath2;testPath3;runtimePath1'
                PSModulePath = 'testPsModulePath1;runtimePsModulePath1'
            }
        }
    }

    Mock GetEnvVar {
        return ($script:FakeRegistry)[ $Target ][ $EnvVarName ]
    }

    Mock UpdateCurrentProcessPath {
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

        Should -Invoke -CommandName 'GetEnvVar' -Exactly 0
        Should -Invoke -CommandName 'UpdateCurrentProcessPath' -Exactly 0
    }

    It 'should do nothing if no change in path' {

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetEnvVar' -Exactly 10
        Should -Invoke -CommandName 'UpdateCurrentProcessPath' -Exactly 0
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

        Should -Invoke -CommandName 'GetEnvVar' -Exactly 10
        Should -Invoke -CommandName 'UpdateCurrentProcessPath' -Exactly 1 -ParameterFilter {
            ($EnvVarName -eq 'PATH') -and ($Additions -eq $newPaths)
        }
        Should -Invoke -CommandName 'UpdateCurrentProcessPath' -Exactly 1 -ParameterFilter {
            ($EnvVarName -eq 'PSModulePath') -and ($Additions -eq $newPsModulePaths)
        }
    }

    It 'should not add duplicate paths' {

        $newPsModulePaths = 'newPath3'
        $script:FakeRegistry[ 'Process' ][ 'PSModulePath' ] = $newPsModulePaths
        Mock winget.exe {
            # Simulate install updating the registry:
            $script:FakeRegistry[ 'Machine' ][ 'PSModulePath' ] = $newPsModulePaths
        }

        # N.B. Dot sourcing here is important, so that it executes in the current scope.
        . $PSScriptRoot\winget.ps1 install something

        Should -Invoke -CommandName 'GetEnvVar' -Exactly 10
        Should -Invoke -CommandName 'UpdateCurrentProcessPath' -Exactly 0
    }
}
