<#
.SYNOPSIS
    Check if manifest if valid according to standards.
.DESCRIPTION
    How to fix the known issues:
        File is not UTF8-encoded                    => shovel utils format ./path/to/the/manifest
        File does not end with exactly 1 newline    => shovel utils format ./path/to/the/manifest
        Line endings are not CRLF                   => shovel utils format ./path/to/the/manifest
        File contains trailing spaces               => shovel utils format ./path/to/the/manifest
        File contains tabs                          => shovel utils format ./path/to/the/manifest
        Manifest does not validate against schema   => Open file in editor, which support schema validation and fix the shown issues. You can use '$env:SCOOP_HOME\supporting\validator\bin\validator.exe $env:SCOOP_HOME\schema.json ./path/to/the/manifest' to see the issues
.PARAMETER App
    Specifies the manifest name.
    Wildcards are supported.
.PARAMETER Dir
    Specifies the location of manifests.
.PARAMETER SkipValid
    Specifies to not show valid manifests.
#>
param(
    [SupportsWildcards()]
    [String] $App = '*',
    [Parameter(Mandatory)]
    [ValidateScript( {
            if (!(Test-Path $_ -Type 'Container')) { throw "$_ is not a directory!" }
            $true
        })]
    [String] $Dir,
    [Switch] $SkipValid
)

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Helpers', 'New-IssuePrompt'),
    @('manifest', 'Resolve-ManifestInformation')
) | ForEach-Object {
    if (!(Get-Command $_[1] -ErrorAction 'Ignore')) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

$Dir = Resolve-Path $Dir
$Queue = @()
$ExitCode = 0
$Problems = 0

#region Functions
# Setup validator
$schema = Resolve-Path "$PSScriptRoot/../schema.json"
& (Join-Path $PSScriptRoot '..\supporting\yaml\bin\Load-Assemblies.ps1')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Newtonsoft.Json.dll')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Newtonsoft.Json.Schema.dll')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Scoop.Validator.dll')
$SHOVEL_VALIDATOR = New-Object Scoop.Validator($schema, $true)

# Check spaces/tabs/endlines/UTF8
function Test-FileFormat {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param([Parameter(Mandatory)] $Gci)

    $verdict = $true
    $problems = @()

    $splat = @{
        'LiteralPath' = $Gci.FullName
        'TotalCount'  = 3
    }
    if ((Get-Command Get-Content).Parameters.ContainsKey('AsByteStream')) {
        $splat.Add('AsByteStream', $true)
    } else {
        $splat.Add('Encoding', 'Byte')
    }

    $content = [char[]] (Get-Content @splat) -join ''

    foreach ($prohibited in @('\xEF\xBB\xBF', '\xFF\xFE', '\xFE\xFF\x00', '\xFF\xFE\x00\x00', '\x00\x00\xFE\xFF')) {
        if ([Regex]::Match($content, "(?ms)^$prohibited").Success) {
            $verdict = $false
            $problems += 'File is not UTF8-encoded'
            break
        }
    }

    # Check for the only 1 newline at the end of the file
    $string = [System.IO.File]::ReadAllText($Gci.FullName)
    if (($string.Length -gt 0) -and (($string[-1] -ne "`n") -or ($string[-3] -eq "`n"))) {
        $verdict = $false
        $problems += 'File does not end with exactly 1 newline'
    }

    # CRLF
    $content = Get-Content $gci.FullName -Raw
    $lines = $content -split '\r\n'

    for ($i = 0; $i -lt $lines.Count; ++$i) {
        if ([Regex]::Match($lines[$i], '\r|\n').Success ) {
            $verdict = $false
            $vcr = $true
            break
        }
    }

    $vtrail = $vtab = $false
    $lines = [System.IO.File]::ReadAllLines($Gci.FullName)

    for ($i = 0; $i -lt $lines.Count; ++$i) {
        # No trailing whitespace
        if ($lines[$i] -match '\s+$') {
            $verdict = $false
            $vtrail = $true
        }

        # No tabs
        if (($lines[$i] -notmatch '^[ ]*(\S|$)') -or ($lines[$i] -match '[\t]') ) {
            $verdict = $false
            $vtab = $true
        }

        if ($verdict -eq $false) { break }
    }

    if ($vcr) { $problems += 'Line endings are not CRLF' }
    if ($vtrail) { $problems += 'File contains trailing spaces' }
    if ($vtab) { $problems += 'File contains tabs' }

    return $problems
}

function Test-ManifestSchema {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter(Mandatory)] $Gci)

    $problems = @()
    $verdict = $SHOVEL_VALIDATOR.Validate($Gci.FullName)
    if ($verdict -eq $false) { $problems = @('Manifest does not validate against schema') }

    return $problems
}
#endregion Functions

foreach ($gci in Get-ChildItem $Dir "$App.*" -File) {
    if ($gci.Extension -notmatch "\.($ALLOWED_MANIFEST_EXTENSION_REGEX)") {
        Write-UserMessage -Message "Skipping $($gci.Name)" -Info
        continue
    }

    try {
        $manifest = ConvertFrom-Manifest -Path $gci.FullName
    } catch {
        Write-UserMessage -Message "Invalid manifest: $($gci.Name) $($_.Exception.Message)" -Err
        continue
    }
    $Queue += , @($gci, $manifest)
}

foreach ($q in $Queue[-1..-9]) {
    $gci, $json = $q
    $name = $gci.BaseName

    $tests = @{
        'FileFormat' = Test-FileFormat -Gci $gci
        'Schema'     = Test-ManifestSchema -Gci $gci
    }

    $valid = @(@($tests.Values) -notlike @()).Count -eq 0

    if ($valid) {
        if (!$SkipValid) {
            Write-UserMessage -Message "${name}: Valid" -Success
        }
    } else {
        ++$Problems
        $failed = @()
        $tests.Keys | Where-Object { $tests[$_].Count -gt 0 } | ForEach-Object {
            $failed += $tests[$_]
        }

        Write-UserMessage -Message "${name}: $($failed -join ', ')" -Err -SkipSeverity
    }
}

if ($Problems -gt 0) {
    $ExitCode = 10 + $Problems
}

exit $ExitCode
