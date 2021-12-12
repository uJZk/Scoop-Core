<#
.SYNOPSIS
    Check if manifest if valid according to standards.
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
# Check spaces/tabs/endlines/UTF8
function Test-FileFormat {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        $Gci,
        $Manifest
    )

    $verdict = $true

    $splat = @{
        'LiteralPath' = $Gci.FullName
        'TotalCount'  = 3
    }
    if ((Get-Command Get-Content).Parameters.ContainsKey('AsByteStream')) {
        $splat.Add('AsByteStream', $true)
    } else {
        $splat.Add('Encoding', 'Byte')
    }

    $content = [char[]] (Get-Content -LiteralPath @splat) -join ''

    # TODO: UTF32
    foreach ($prohibited in @('\xEF\xBB\xBF', '\xFF\xFE', '\xFE\xFF')) {
        if ([Regex]::Match($content, "(?ms)^$prohibited").Success) {
            $verdict = $false
            break
        }
    }

    # Check for the only 1 newline at the end of the file
    $string = [System.IO.File]::ReadAllText($Gci.FullName)
    if (($string.Length -gt 0) -and (($string[-1] -ne "`n") -or ($string[-3] -eq "`n"))) {
        $verdict = $false
    }

    # CRLF
    # TODO: Join with below?
    $content = Get-Content -LiteralPath $Gci.FullName -Raw
    $lines = [Regex]::Split($content, '\r\n')

    for ($i = 0; $i -lt $lines.Count; ++$i) {
        if ([Regex]::Match($lines[$i], '\r|\n').Success ) {
            $verdict = $false
            break
        }
    }

    $lines = [System.IO.File]::ReadAllLines($Gci.FullName)
    for ($i = 0; $i -lt $lines.Count; ++$i) {
        # No trailing whitespace
        if ($lines[$i] -match '\s+$') {
            $verdict = $false
            break
        }

        # No tabs
        if ($lines[$i] -notmatch '^[ ]*(\S|$)') {
            $verdict = $false
            break
        }
    }

    return $verdict
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

foreach ($q in $Queue) {
    $gci, $json = $q
    $name = $gci.Name

    $tests = @{
        'UTF8' = Test-FileFormat -Gci $gci -Manifest $json
        # 'Schema' = $false
    }

    # Print
    $valid = @(@($tests.Values) -like $false).Count -eq 0

    if ($valid) {
        if (!$SkipValid) {
            Write-UserMessage -Message "${name}: Valid" -Success
        }
    } else {
        ++$Problems
        $failed = $tests.Keys | Where-Object { $false -eq $tests[$_] }

        Write-UserMessage -Message "${name}: Invalid ($($failed -join ', '))" -Err
    }
}

if ($Problems -gt 0) {
    $ExitCode = 10 + $Problems
}

exit $ExitCode
