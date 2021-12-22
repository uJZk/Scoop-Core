<#
.SYNOPSIS
    Check if manifest if valid according to standards.
.DESCRIPTION
    How to fix the known issues:
        File is not UTF8-encoded                    => `shovel utils format ./path/to/the/manifest`
        File does not end with exactly 1 newline    => `shovel utils format ./path/to/the/manifest`
        Line endings are not CRLF                   => `shovel utils format ./path/to/the/manifest`
        File contains trailing spaces               => `shovel utils format ./path/to/the/manifest`
        File contains tabs                          => `shovel utils format ./path/to/the/manifest`
        Manifest does not validate against schema   => Open file in editor, which support schema validation and fix the shown issues. You can use `$env:SCOOP_HOME\supporting\validator\bin\validator.exe $env:SCOOP_HOME\schema.json ./path/to/the/manifest` to see the issues

        Hash check utility issue                    => Run `shovel utils checkhashes ./path/to/the/manifest` and fix the issue being shown.
        Hash check failed                           => `shovel utils checkhashes ./path/to/the/manifest --additional-options -update`

        Checkver issue                              => Run `shovel utils checkver ./path/to/the/manifest --additional-options -force` and fix the issue being shown.
        Newer version available                     => shovel utils checkver ./path/to/the/manifest --additional-options -update
.PARAMETER App
    Specifies the manifest name.
    Wildcards are supported.
.PARAMETER Dir
    Specifies the location of manifests.
.PARAMETER Schame
    Specifies the path to the alternative schema.json file.
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
    [String] $Schema,
    [Switch] $SkipValid
)

'core', 'Helpers', 'manifest', 'commands' | ForEach-Object {
    . (Join-Path $PSScriptRoot "..\lib\$_.ps1")
}

$Dir = Resolve-Path $Dir
$Queue = @()
$ExitCode = 0
$Problems = 0

# Setup validator
if (!$Schema) {
    $Schema = "$PSScriptRoot/../schema.json"
}

$Schema = Resolve-Path -Path $Schema
& (Join-Path $PSScriptRoot '..\supporting\yaml\bin\Load-Assemblies.ps1')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Newtonsoft.Json.dll')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Newtonsoft.Json.Schema.dll')
Add-Type -Path (Join-Path $PSScriptRoot '..\supporting\validator\bin\Scoop.Validator.dll')
$SHOVEL_VALIDATOR = New-Object Scoop.Validator($Schema, $true)

#region Functions
function Test-Hash {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter(Mandatory)] $Gci)

    $verdict = $true, $Gci
    $problems = @()



    # $outputH = @(& shovel utils checkhashes $manifest.FullName *>&1)
    # $ec = $LASTEXITCODE
    # Write-Log 'Output' $outputH

    # # Everything should be all right when latest string in array will be OK
    # $statuses.Add('Hashes', (($ec -eq 0) -and ($outputH[-1] -like 'OK')))







    return $problems
}

function _inlineHelper($checkver = @(), $autoupdate = @()) {
    return [PSObject] @{
        'Checkver'   = $checkver
        'Autoupdate' = $autoupdate
    }
}

function Test-Checkver {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter(Mandatory)] $Gci)

    $verdict = $true
    $checkverProblems = @()
    $autoupdateProblems = @()

    # TODO: Do not call external
    $res = shovel utils checkver $Gci.FullName --additional-options -ForceUpdate *>&1
    if ($LASTEXITCODE -ne 0) {
        $verdict = $false
        return _inlineHelper @("Checkver issue: '$res'") @('Checkver cannot run')
    }




    <#
                $outputV = @(& shovel utils checkver $manifest.FullName --additional-options -Force *>&1)
            $ec = $LASTEXITCODE
            Write-log 'Output' $outputV

            # If there are more than 2 lines and second line is not version, there is problem
            $checkver = (($ec -eq 0) -and (($outputV.Count -ge 2) -and ($outputV[1] -like "$($object.version)")))
            $statuses.Add('Checkver', $checkver)
            Write-Log 'Checkver done'

            #region Autoupdate
            if ($object.autoupdate) {
                Write-Log 'Autoupdate'
                $autoupdate = $false
                switch -Wildcard ($outputV[-1]) {
                    'ERROR*' {
                        Write-Log 'Error in checkver'
                    }
                    'could*t match*' {
                        Write-Log 'Version match fail'
                    }
                    'Writing updated*' {
                        Write-Log 'Autoupdate finished successfully'
                        $autoupdate = $true
                    }
                    default { $autoupdate = $checkver }
                }
                $statuses.Add('Autoupdate', $autoupdate)

                # There is some hash property defined in autoupdate
                if ((($outputV -like 'Searching hash for*')) -or (hash $object.autoupdate '32bit') -or (hash $object.autoupdate '64bit') -or (hash $object.autoupdate 'arm64')) {
                    $result = $autoupdate
                    if ($result) {
                        # If any result contains any item with 'Could not find hash*' there is hash extraction error.
                        $result = (($outputV -like 'Could not find hash*').Count -eq 0)
                    }
                    $statuses.Add('Autoupdate Hash Extraction', $result)
                }
                Write-Log 'Autoupdate done'
            }
            #endregion Autoupdate
        }
    #>







    $joined = $res -join ''

    Write-Host $joined -f magenta
    Write-Host $res -f red
    $new = $res[1].ToString().Trim()
    $old = $res[1].ToString().Trim()
    Write-Host $new, $old -f Yellow
    if ($joined -match '\((scoop|shovel) version is (.*?)\)') {
        $checkverProblems += 'Newer version available'
    }

    return _inlineHelper $checkverProblems $autoupdateProblems
}

# Check spaces/tabs/endlines/UTF8
function Test-FileFormat {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
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

    $lines = $string -split '\r\n'
    $vcr = $vtrail = $vtab = $false

    for ($i = 0; $i -lt $lines.Count; ++$i) {
        # CRLF
        if ($lines[$i] -match '\r|\n') {
            $verdict = $false
            $vcr = $true
        }
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

        # TODO: Consider just break here if the first line is broken
    }

    if ($vcr) { $problems += 'Line endings are not CRLF' }
    if ($vtrail) { $problems += 'File contains trailing spaces' }
    if ($vtab) { $problems += 'File contains tabs' }

    return $problems
}

function Test-ManifestSchema {
    <#
    .SYNOPSIS
        Check if manifest validates according to the schema.
    #>
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
        ++$Problems
        Write-UserMessage -Message "Invalid manifest: $($gci.Name) $($_.Exception.Message)" -Err
        continue
    }
    $Queue += , @($gci, $manifest)
}

foreach ($q in $Queue) {
    $gci, $json = $q
    $name = $gci.BaseName

    $tests = [PSObject] @{
        'FileFormat' = Test-FileFormat -Gci $gci
        'Schema'     = Test-ManifestSchema -Gci $gci
        'Hashes'     = Test-Hash -Gci $gci
    }
    $chAut = Test-Checkver -Gci $gci
    $tests.Add('Checkver', $chAut.'Checkver')
    $tests.Add('Autoupdate', $chAut.'Autoupdate')

    $failed = @()
    foreach ($f in $tests.Keys) {
        if ($tests[$f]) { $failed += $tests[$f] }
    }

    if ($failed.Count -eq 0) {
        if ($SkipValid) { continue }

        Write-UserMessage -Message "${name}: Valid" -Success
    } else {
        ++$Problems

        Write-UserMessage -Message "${name}: $($failed -join ', ')" -Err -SkipSeverity
    }
}

if ($Problems -gt 0) {
    $ExitCode = 10 + $Problems
}

exit $ExitCode
