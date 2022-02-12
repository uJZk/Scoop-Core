# Usage: scoop info [<OPTIONS>] <APP>
# Summary: Display information about an application.
#
# Options:
#   -h, --help                      Show help for this command.
#   -a, --arch <32bit|64bit|arm64>  Use the specified architecture, if the application's manifest supports it.

'core', 'getopt', 'help', 'Helpers', 'Applications', 'buckets', 'Dependencies', 'install', 'manifest', 'Versions' | ForEach-Object {
    . (Join-Path $PSScriptRoot "..\lib\${_}.ps1")
}

$ExitCode = 0
# TODO: Add some --remote parameter to not use installed manifest
#   -g, --global                    Gather information from globally installed application if application is installed both locally and globally.
#                                       Useful for pre-check of installed specific application in automatic deployments.
#   -r, --remote >    Remote manifest will be used to get all required information. Ignoring locally installed manifest (scoop-manifest.json).
# $Options, $Application, $_err = Resolve-GetOpt $args 'a:g' 'arch=', 'global'
$Options, $Application, $_err = Resolve-GetOpt $args 'a:' 'arch='

if ($_err) { Stop-ScoopExecution -Message "scoop info: $_err" -ExitCode 2 }
if (!$Application) { Stop-ScoopExecution -Message 'Parameter <APP> missing' -Usage (my_usage) }
if ($Application.Count -gt 1) { Write-UserMessage -Message 'Multiple <APP> parameters is not allowed. Ignoring all except the first.' -Warning }

$Application = $Application[0]
$Architecture = Resolve-ArchitectureParameter -Architecture $Options.a, $Options.arch
# $Global = $Options.'g' -or $Options.'global'

$Resolved = $null
try {
    $Resolved = Resolve-ManifestInformation -ApplicationQuery $Application
} catch {
    Stop-ScoopExecution -Message $_.Exception.Message
}

# Variables
$Name = $Resolved.ApplicationName
$Message = @()
$Global = installed $Name $true
$Status = app_status $Name $Global
$Manifest = $Resolved.ManifestObject
$ManifestPath = @($Resolved.LocalPath)

$ManifestPath = $ManifestPath, $Resolved.Url, (installed_manifest $Name $Manifest.version $Global -PathOnly), $Resolved.LocalPath |
    Where-Object { ![String]::IsNullOrEmpty($_) } | Select-Object -Unique

$dir = (versiondir $Name $Manifest.version $Global).TrimEnd('\')
$original_dir = (versiondir $Name $Resolved.Version $Global).TrimEnd('\')
$persist_dir = (persistdir $Name $Global).TrimEnd('\')
$up = if ($Status.outdated) { 'Yes' } else { 'No' }

$Message = @("Name: $Name")
$Message += "Version: $($Manifest.Version)"
if ($Manifest.description) { $Message += "Description: $($Manifest.description)" }
if ($Manifest.homepage) { $Message += "Homepage: $($Manifest.homepage)" }

# Show license
# TODO: Rework
if ($Manifest.license) {
    $license = $Manifest.license
    if ($Manifest.license.identifier -and $Manifest.license.url) {
        $license = "$($Manifest.license.identifier) ($($Manifest.license.url))"
    } elseif ($Manifest.license -match '^((ht)|f)tps?://') {
        $license = "$($Manifest.license)"
    } elseif ($Manifest.license -match '[|,]') {
        $licurl = $Manifest.license.Split('|,') | ForEach-Object { "https://spdx.org/licenses/$_.html" }
        $license = "$($Manifest.license) ($($licurl -join ', '))"
    } else {
        $license = "$($Manifest.license) (https://spdx.org/licenses/$($Manifest.license).html)"
    }
    $Message += "License: $license"
}

if ($Manifest.changelog) {
    $ch = $Manifest.changelog
    if (!$ch.StartsWith('http')) {
        if ($Status.installed) {
            $ch = Join-Path $dir $ch
        } else {
            $ch = "Could be found in file '$ch' inside application directory. Install application to see a recent changes"
        }
    }
    $Message += "Changelog: $ch"
}

# Manifest file
$Message += 'Manifest:'
foreach ($m in $ManifestPath) { $Message += "  $m" }

# Bucket info
if ($Resolved.Bucket) {
    $_m = "Bucket: $($Resolved.Bucket)"
    $path = Find-BucketDirectory -Bucket $Resolved.Bucket

    if ($path) {
        try {
            # TODO: Quote
            $_u = Invoke-GitCmd -Repository $path -Command 'config' -Argument @('--get', 'remote.origin.url')
            if ($LASTEXITCODE -ne 0) { throw 'Ignore' }
            if ($_u) { $_m = "$_m ($_u)" }
        } catch {
            $_u = $null
        }
    }

    $Message += $_m
}

# Show installed versions
if ($Status.installed) {
    $_m = 'Installed: Yes'
    if ($Global) { $_m = "$_m *global*" }
    $Message += $_m

    $Message += "Installation path: $dir"

    $v = Get-InstalledVersion -AppName $Name -Global:$Global
    if ($v.Count -gt 0) {
        $Message += "Installed versions: $($v -join ', ')"
    }
    $Message += "Update available: $up"

    $InstallInfo = install_info $Name $Manifest.version $Global
    $Architecture = $InstallInfo.architecture
} else {
    $inst = 'Installed: No'
    # if ($reason) { $inst = "$inst ($reason)" }
    $Message += $inst
}

$arm64Support = 'No'
if ($Manifest.architecture.arm64) { $arm64Support = 'Yes' }
$Message += "arm64 Support: $arm64Support"

$binaries = @(arch_specific 'bin' $Manifest $Architecture)
if ($binaries) {
    $Message += 'Binaries:'
    $add = ' '
    foreach ($b in $binaries) {
        $addition = "$b"
        if ($b -is [System.Array]) {
            $addition = $b[0]
            if ($b[1]) {
                $addition = "$($b[1]).exe"
            }
        }
        $add = "$add $addition"
    }
    $Message += $add
}

#region Environment
$env_set = arch_specific 'env_set' $Manifest $Architecture
$env_add_path = @(arch_specific 'env_add_path' $Manifest $Architecture)

if ($env_set -or $env_add_path) {
    $m = 'Environment:'
    if (!$Status.installed) { $m += ' (simulated)' }
    $Message += $m
}

if ($env_set) {
    foreach ($es in $env_set | Get-Member -MemberType 'NoteProperty') {
        $value = env $es.Name $Global
        if (!$value) {
            $value = format $env_set.$($es.Name) @{ 'dir' = $dir }
        }
        $Message += "  $($es.Name)=$value"
    }
}
if ($env_add_path) {
    # TODO: Should be path rather joined on one line or with multiple PATH=??
    # Original:
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\global\node_modules\.bin
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\Yarn\bin
    # vs:
    # PATH=%PATH%;C:\SCOOP\apps\yarn\current\global\node_modules\.bin;C:\SCOOP\apps\yarn\current\Yarn\bin
    foreach ($ea in $env_add_path | Where-Object { $_ }) {
        $to = "$dir"
        if ($ea -ne '.') {
            $to = "$to\$ea"
        }
        $Message += "  PATH=%PATH%;$to"
    }
}
#endregion Environment

# Available versions:
$vers = Find-BucketDirectory -Name $Resolved.Bucket | Join-Path -ChildPath "old\$Name" | Get-ChildItem -ErrorAction 'SilentlyContinue' -File |
    Where-Object -Property 'Name' -Match -Value "\.($ALLOWED_MANIFEST_EXTENSION_REGEX)$"
if ($vers.Count -gt 0) { $Message += "Available archived versions: $($vers.BaseName -join ', ')" }

Write-UserMessage -Message $Message -Output

# Show notes
show_notes $Manifest $dir $original_dir $persist_dir

exit $ExitCode
