@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Helpers', 'New-IssuePrompt')
) | ForEach-Object {
    if (!(Get-Command $_[1] -ErrorAction 'Ignore')) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "$($_[0]).ps1")
    }
}

$SHOVEL_CONFIG_REMOVED = @(
    'rootPath',
    'globalPath',
    'cachePath'
)

$SHOVEL_CONFIG_DEPRECATED = @(
    @('SCOOP_REPO', 'core.repository.url'),
    @('SCOOP_BRANCH', 'core.repository.branch'),
    @('lastUpdate', 'core.lastUpdate'),
    @('githubToken', 'core.githubToken'),
    @('dbgBypassArmCheck', 'debug.disableArmCheck'),
    @('default-architecture', 'core.defaultArchitecture'),
    @('NO_JUNCTIONS', 'core.disableJunctions'),
    @('MSIEXTRACT_USE_LESSMSI', 'extraction.useLessMSI'),
    @('7ZIPEXTRACT_USE_EXTERNAL', 'extraction.useExternal7z'),
    @('INNOSETUP_USE_INNOEXTRACT', 'extraction.useInnoExtract'),
    @('show_update_log', 'commands.update.showUpdateLog'),
    @('virustotal_api_key', 'commands.virustotal.apiKey'),
    @('aria2-enabled', 'aria2.enabled'),
    @('aria2-retry-wait', 'aria2.retryWait'),
    @('aria2-split', 'aria2.split'),
    @('aria2-max-connection-per-server', 'aria2.maxConnectionPerServer'),
    @('aria2-min-split-size', 'aria2.minSplitSize'),
    @('aria2-options', 'aria2.options')
)

function Convert-ConfigOption {
    <#
    .SYNOPSIS
        Migrate configuration option from the old format to the new.
    .PARAMETER OldConfigOptions
        Specifies the old configuration option.
    .PARAMETER NewConfigOptions
        Specifies the new configuration option.
    #>
    param(
        [Parameter(Mandatory)]
        [String] $OldConfigOptions,
        [Parameter(Mandatory)]
        [String] $NewConfigOptions
    )

    process {
        $OldConfigOptions, $NewConfigOptions | Out-Null
    }
}
