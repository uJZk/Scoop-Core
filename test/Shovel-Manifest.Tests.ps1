
. "$PSScriptRoot\Scoop-TestLib.ps1"
. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"

Describe 'Manifests operations' -Tag 'Scoop' {
    BeforeAll {
        $working_dir = (setup_working 'manifest' | Resolve-Path).Path
        Move-Item "$working_dir\*.*" "$working_dir\bucket"
        $SCOOP_BUCKETS_DIRECTORY = $working_dir | Split-Path

        Copy-Item $working_dir "$SCOOP_BUCKETS_DIRECTORY\ash258.ash258" -Force -Recurse
        Copy-Item $working_dir "$SCOOP_BUCKETS_DIRECTORY\main" -Force -Recurse
    }

    It 'manifest_path' {
        $path = manifest_path 'cosi' 'manifest'
        $path | Should -Be "$working_dir\bucket\cosi.yaml"
        $path = $null

        $path = manifest_path 'wget' 'manifest'
        $path | Should -Be "$working_dir\bucket\wget.json"
        $path = $null

        $path = manifest_path 'pwsh' 'ash258.ash258'
        $path | Should -Be "$SCOOP_BUCKETS_DIRECTORY\ash258.ash258\bucket\pwsh.json"
        $path = $null

        $path = manifest_path 'cosi' 'main'
        $path | Should -Be "$SCOOP_BUCKETS_DIRECTORY\main\bucket\cosi.yaml"
        $path = $null

        $path = manifest_path 'pwsh' 'alfa'
        $path | Should -Be $null
        $path = $null

        $path = manifest_path 'ahoj' 'main'
        $path | Should -Be $null
        $path = $null
    }

    It 'manifest_path with version' {
        $path = manifest_path 'cosi' 'main' '7.1.0'
        $path | Should -Be "$SCOOP_BUCKETS_DIRECTORY\main\bucket\old\cosi\7.1.0.yaml"
        $path = $null

        $path = manifest_path 'pwsh' 'ash258.ash258' '6.2.3'
        $path | Should -Be "$SCOOP_BUCKETS_DIRECTORY\ash258.ash258\bucket\old\pwsh\6.2.3.yml"
        $path = $null

        $path = manifest_path 'pwsh' 'ash258.ash258' '2222'
        $path | Should -Be $null
        $path = $null

        { manifest_path 'wget' 'ash258.ash258' '2222' } | Should -Throw 'Bucket ''ash258.ash258'' does not contain archived version ''2222'' for ''wget'''
        $path = $null
    }

    It 'New-VersionedManifest' {
        $path = manifest_path 'pwsh' 'ash258.ash258'
        $new = New-VersionedManifest -LiteralPath $path -Version '7.1.0' 6>$null
        $new | Should -BeLike "$env:SCOOP\manifests\pwsh-*.json"
        (ConvertFrom-Manifest -LiteralPath $new).version | Should -Be '7.1.0'
        $path = $null

        $path = manifest_path 'cosi' 'main'
        $new = New-VersionedManifest -LiteralPath $path -Version '6.2.3' 6>$null
        $new | Should -BeLike "$env:SCOOP\manifests\cosi-*.yaml"
        (ConvertFrom-Manifest -LiteralPath $new).version | Should -Be '6.2.3'
        $path = $null

        { manifest_path 'cosi' 'main' | New-VersionedManifest -Version '22222' 6>$null } | Should -Throw 'Cannot generate manifest with version ''22222'''

        $path = manifest_path 'broken_wget' 'main'
        { New-VersionedManifest -LiteralPat $path -Version '22222' 6>$null } | Should -Throw "Invalid manifest '$path'"
        $path = $null
    }

    Describe 'Resolve-ManifestInformation' {
        Describe 'Get-LocalManifest' {
            It 'Full path' {
                $result = Resolve-ManifestInformation "$working_dir\bucket\pwsh.json"
                $result.ApplicationName | Should -Be 'pwsh'
                $result.Version | Should -Be '7.1.3'
                $result.ManifestObject.checkver | Should -Be 'github'
                $result.LocalPath | Should -Be "$working_dir\bucket\pwsh.json"
                $result = $null

                # Mix of dividers
                $result = Resolve-ManifestInformation "$working_dir\bucket/cosi.yaml"
                $result.ApplicationName | Should -Be 'cosi'
                $result.Version | Should -Be '7.1.3'
                $result.ManifestObject.checkver | Should -Be 'github'
                $result.LocalPath | Should -Be "$working_dir\bucket\cosi.yaml"
                $result = $null
            }

            It 'Full versioned path' {
                $result = Resolve-ManifestInformation "$working_dir\bucket\old\pwsh\6.2.3.yml"
                $result.ApplicationName | Should -Be 'pwsh'
                $result.Version | Should -Be '6.2.3'
                $result.ManifestObject.bin | Should -Be 'pwsh.exe'
                $result.LocalPath | Should -Be "$working_dir\bucket\old\pwsh\6.2.3.yml"
                $result = $null

                $result = Resolve-ManifestInformation "$working_dir\bucket\old\cosi\7.1.0.yaml"
                $result.ApplicationName | Should -Be 'cosi'
                $result.Version | Should -Be '7.1.0'
                $result.ManifestObject.bin | Should -Be 'pwsh.exe'
                $result.LocalPath | Should -Be "$working_dir\bucket\old\cosi\7.1.0.yaml"
                $result = $null

                $result = Resolve-ManifestInformation "$working_dir\bucket/old\cosi/7.1.0.yaml"
                $result.ApplicationName | Should -Be 'cosi'
                $result.Version | Should -Be '7.1.0'
                $result.ManifestObject.bin | Should -Be 'pwsh.exe'
                $result.LocalPath | Should -Be "$working_dir\bucket\old\cosi\7.1.0.yaml"
                $result = $null

                $result = Resolve-ManifestInformation "$($working_dir -replace '\\', '/')/bucket/old/cosi/7.1.0.yaml"
                $result.ApplicationName | Should -Be 'cosi'
                $result.Version | Should -Be '7.1.0'
                $result.ManifestObject.bin | Should -Be 'pwsh.exe'
                $result = $null
            }

            It 'Error handling' {
                { manifest_path 'invalid_wget' 'main' | Resolve-ManifestInformation } | Should -Throw 'Not a valid manifest'
                ( { manifest_path 'broken_wget' 'main' | Resolve-ManifestInformation } | Should -Throw -Passthru).Exception.Message | Should -BeLike 'File is not a valid manifest*'
            }
        }

        It 'Not supported query' {
            { Resolve-ManifestInformation '@@cosi@@' } | Should -Throw 'Not supported way how to provide manifest'
            { Resolve-ManifestInformation '@1.2.5.8' } | Should -Throw 'Not supported way how to provide manifest'
            { Resolve-ManifestInformation 'ftp://test.json' } | Should -Throw 'Not supported way how to provide manifest'
        }
    }
}