Describe 'WingetPathUpdater version metadata' {
    BeforeAll {
        $installScriptPath = Join-Path $PSScriptRoot 'WingetPathUpdaterInstall.ps1'
        $manifestDir = Join-Path $PSScriptRoot 'manifests/j/jazzdelightsme/WingetPathUpdater/1.3'
        $manifestPath = Join-Path $manifestDir 'jazzdelightsme.WingetPathUpdater.yaml'
        $installerManifestPath = Join-Path $manifestDir 'jazzdelightsme.WingetPathUpdater.installer.yaml'
        $localeManifestPath = Join-Path $manifestDir 'jazzdelightsme.WingetPathUpdater.locale.en-US.yaml'

        $installScriptContent = Get-Content -Path $installScriptPath -Raw
        $installerManifestContent = Get-Content -Path $installerManifestPath -Raw
    }

    It 'writes ARP version values for the 1.3 release' {
        $installScriptContent | Should -Match '\[string\] \$Tag = ''v1\.3'''
        $installScriptContent | Should -Match 'VersionMinor .* /d 3'
        $installScriptContent | Should -Match 'DisplayVersion /d 1\.3'
    }

    It 'publishes winget manifests for version 1.3' {
        (Get-Content -Path $manifestPath -Raw) | Should -Match 'PackageVersion: 1\.3'
        (Get-Content -Path $localeManifestPath -Raw) | Should -Match 'PackageVersion: 1\.3'
        $installerManifestContent | Should -Match 'PackageVersion: 1\.3'
        $installerManifestContent | Should -Match 'https://raw\.githubusercontent\.com/jazzdelightsme/WingetPathUpdater/v1\.3/WingetPathUpdaterInstall\.ps1'
    }
}
