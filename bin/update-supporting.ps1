<#
.SYNOPSIS
    Update supporting tools to the latest version.
.PARAMETER Supporting
    Specifies the name of supporting tool to be updated.
#>
param([String] $Supporting = '*', [Switch] $Install)

$ErrorActionPreference = 'Stop'
$checkver = Join-Path $PSScriptRoot 'checkver.ps1'
$Sups = Join-Path $PSScriptRoot '..\supporting\*' | Get-ChildItem -Include "$Supporting.*" -File

@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Helpers', 'New-IssuePrompt'),
    @('decompress', 'Expand-7zipArchive'),
    @('install', 'install_app'),
    @('manifest', 'Resolve-ManifestInformation')
) | ForEach-Object {
    if (!(Get-Command $_[1] -ErrorAction 'Ignore')) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "..\lib\$($_[0]).ps1")
    }
}

$exitCode = 0
$problems = 0
foreach ($sup in $Sups) {
    $name = $sup.BaseName
    $folder = $sup.Directory
    $dir = Join-Path $folder "$name\bin"

    Write-UserMessage -Message "Updating $name" -Color 'Magenta'

    & "$checkver" -App "$name" -Dir "$folder" -Update

    if (!$Install) { continue }

    try {
        $manifest = ConvertFrom-Manifest -Path $sup.FullName
    } catch {
        Write-UserMessage -Message "Invalid manifest: $($sup.Name)" -Err
        ++$problems
        continue
    }

    Remove-Module 'powershell-yaml' -ErrorAction 'SilentlyContinue' -Force
    Start-Sleep -Seconds 2

    Rename-Item $dir 'old' -ErrorAction 'SilentlyContinue'
    Confirm-DirectoryExistence -LiteralPath $dir | Out-Null
    Start-Sleep -Seconds 2
    try {
        $fname = dl_urls $name $manifest.version $manifest '' (default_architecture) $dir $true $true
        $fname | Out-Null
        # Pre install is enough now
        Invoke-ManifestScript -Manifest $manifest -ScriptName 'pre_install' -Architecture $architecture
    } catch {
        ++$problems
        debug $_.InvocationInfo
        New-IssuePromptFromException -ExceptionMessage $_.Exception.Message

        continue
    }

    Write-UserMessage -Message "$name done" -Success

    Join-Path $folder "$name\old" | Remove-Item -Force -Recurse
}

if ($problems -gt 0) { $exitCode = 10 + $problems }
exit $exitCode
