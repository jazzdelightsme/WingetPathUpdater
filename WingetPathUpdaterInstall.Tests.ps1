# The following line is important for the installer:
# This file is part of the WingetPathUpdater package.

Describe 'WingetPathUpdaterInstall.ps1' {
    BeforeAll {
        $script:InstallerScript = Get-Content (Join-Path $PSScriptRoot 'WingetPathUpdaterInstall.ps1') -Raw
    }

    It 'should write ARP version 1.3' {
        $script:InstallerScript | Should -Match '\$null = reg\.exe add \$keyPath /f /v VersionMajor /t REG_DWORD /d 1 ; checkRegResult'
        $script:InstallerScript | Should -Match '\$null = reg\.exe add \$keyPath /f /v VersionMinor /t REG_DWORD /d 3 ; checkRegResult'
        $script:InstallerScript | Should -Match '\$null = reg\.exe add \$keyPath /f /v DisplayVersion /d 1\.3 ; checkRegResult'
    }
}
