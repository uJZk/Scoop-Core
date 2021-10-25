<#
@{
    Option = @{
        Name = Same as $_
        Default = 'def'
        EnvironmentVariable = 'SCOOP_CONFIG_$_'
        Value = 'current' # Will be filled with Default if not specified
        'Old' = odl config in scoop
        'Validation = {
            return $false
        }
    }
}
#>
$SCOOP_CONFIGURATION_DEFAULTS = @{
    # proxy: $null [username:password@]host:port
    # default-architecture: 64bit|32bit|arm64
    # 7ZIPEXTRACT_USE_EXTERNAL: $true|$false
    # MSIEXTRACT_USE_LESSMSI: $true|$false
    # INNOSETUP_USE_INNOEXTRACT: $true|$false
    # NO_JUNCTIONS: $true|$false
    # debug: $true|$false
    # SCOOP_REPO: http://github.com/lukesampson/scoop
    # SCOOP_BRANCH: main|NEW
    # show_update_log: $true|$false
    # virustotal_api_key: $null
    # githubToken: $null
    # dbgBypassArmCheck: $true|$false
    # aria2-enabled: $true|$false
    # aria2-retry-wait: 2
    # aria2-split: 5
    # aria2-max-connection-per-server: 5
    # aria2-min-split-size: 5M
    # aria2-options: @()
}

function ConvertFrom-ConfigurationFile {
    [CmdletBinding()]
    param()

    process {
        return $SCOOP_CONFIGURATION
    }
}

function Get-ConfigOption {
    [CmdletBinding()]
    [OutputType(object)]
    param(
        [Alias('Name')]
        [String] $OptionName,
        $OverrideDefault
    )

    process {
        $value = $OptionName, $OverrideDefault
        return $value
    }
}

function Set-ConfigOption {
    [CmdletBinding()]
    param(
        [Alias('Name')]
        [String] $OptionName,
        [Object] $Value
    )

    process {
        return $SCOOP_CONFIGURATION, $OptionName, $Value
    }
}

#region Deprecated
function get_config($name, $default) {
    return Get-ConfigOption -OptionName $name -OverrideDefault $default
}

function set_config($name, $value) {
    return Set-ConfigOption -OptionName $name -Value $value
}
#endregion Deprecated
