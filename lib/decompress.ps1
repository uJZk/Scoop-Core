if ($__importedDecompress__ -eq $true) {
    return
} else {
    Write-Verbose 'Importing decompress'
}
$__importedDecompress__ = $false

'core', 'Helpers' | ForEach-Object {
    . (Join-Path $PSScriptRoot "${_}.ps1")
}

#region helpers
function Test-7zipRequirement {
    <#
    .SYNOPSIS
        Test if file or url requires 7zip to be installed.
    .PARAMETER URL
        Specifies the string representing URL.
    .PARAMETER File
        Specifies the filename.
    #>
    [CmdletBinding(DefaultParameterSetName = 'URL')]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'URL')]
        [AllowNull()]
        [String[]] $URL,
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [String] $File
    )

    if (!$File -and ($null -eq $URL)) { return $false }

    if ($URL) {
        # For dependencies resolving
        if (get_config '7ZIPEXTRACT_USE_EXTERNAL' $false) {
            return $false
        } else {
            return @($URL | Where-Object { Test-7zipRequirement -File $_ }).Count -gt 0
        }
    } else {
        return $File -match '\.((gz)|(tar)|(tgz)|(lzma)|(bz)|(bz2)|(7z)|(rar)|(iso)|(xz)|(lzh)|(nupkg))$'
    }
}

function Test-LessmsiRequirement {
    <#
    .SYNOPSIS
        Test if url requires lessmsi to be installed.
    .PARAMETER URL
        Specifies the string representing URL.
    #>
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [String[]] $URL
    )

    if ($null -eq $URL) { return $false }

    if (get_config 'MSIEXTRACT_USE_LESSMSI' $true) {
        return @($URL | Where-Object { $_ -match '\.msi$' }).Count -gt 0
    } else {
        return $false
    }
}

function Test-ZstdRequirement {
    [CmdletBinding(DefaultParameterSetName = 'URL')]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'URL')]
        [AllowNull()]
        [String[]] $URL,
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [String] $File
    )

    if (!$File -and ($null -eq $URL)) { return $false }

    if ($URL) {
        return @($URL | Where-Object { Test-ZstdRequirement -File $_ }).Count -gt 0
    } else {
        return $File -match '\.zst$'
    }
}

function _decompressErrorPrompt($path, $log) {
    return @("Decompress error|-Failed to extract files from $path.", 'Log file:', "  $(friendly_path $log)") -join "`n"
}

function Test-TarAchive {
    param([String] $Path)

    process {
        return ((strip_ext $Path) -match '\.tar$') -or ($Path -match '\.t[abgpx]z2?$')
    }
}
#endregion helpers

function Expand-7zipArchive {
    <#
    .SYNOPSIS
        Extract files from 7zip archive.
    .PARAMETER Path
        Specifies the path to the archive.
    .PARAMETER DestinationPath
        Specifies the location, where archive should be extracted.
    .PARAMETER ExtractDir
        Specifies to extract only nested directory inside archive.
    .PARAMETER Switches
        Specifies additional parameters passed to the extraction.
    .PARAMETER Overwrite
        Specifies how files with same names inside archive are handled.
    .PARAMETER Removal
        Specifies to remove the archive after extraction is done.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        # TODO: Check wildcard support
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [String] $ExtractDir,
        [Parameter(ValueFromRemainingArguments)]
        [String] $Switches,
        [ValidateSet('All', 'Skip', 'Rename')]
        [String] $Overwrite,
        [Switch] $Removal
    )

    begin {
        if (!$DestinationPath) { $DestinationPath = Split-Path $Path -Parent }

        if (get_config '7ZIPEXTRACT_USE_EXTERNAL' $false) {
            try {
                $7zPath = (Get-Command -Name '7z' -CommandType 'Application' -ErrorAction 'Stop' | Select-Object -First 1).Source
            } catch [System.Management.Automation.CommandNotFoundException] {
                throw [ScoopException]::new((
                        "Cannot find external 7-Zip (7z.exe) while '7ZIPEXTRACT_USE_EXTERNAL' is 'true'!",
                        "Run 'scoop config 7ZIPEXTRACT_USE_EXTERNAL false' or install 7zip manually and try again." -join "`n"
                    )
                ) # TerminatingError thrown
            }
        } else {
            $7zPath = Get-HelperPath -Helper '7zip'
        }
    }

    process {
        $logPath = Split-Path $Path -Parent | Join-Path -ChildPath '7zip.log'
        $argList = @('x', "`"$Path`"", "-o`"$DestinationPath`"", '-y')
        $isTar = Test-TarAchive -Name $Path

        if (!$isTar -and $ExtractDir) { $argList += "-ir!`"$ExtractDir\*`"" }
        if ($Switches) { $argList += (-split $Switches) }

        switch ($Overwrite) {
            'All' { $argList += '-aoa' }
            'Skip' { $argList += '-aos' }
            'Rename' { $argList += '-aou' }
        }

        try {
            $status = Invoke-ExternalCommand $7zPath $argList -LogPath $logPath
        } catch [System.Management.Automation.ParameterBindingException] {
            throw [ScoopException]::new('''7zip'' is not installed or cannot be used') # TerminatingError thrown
        }

        if (!$status) {
            throw [ScoopException]::new((_decompressErrorPrompt $Path $logPath)) # TerminatingError thrown
        }
        if (!$isTar -and $ExtractDir) {
            movedir (Join-Path $DestinationPath $ExtractDir) $DestinationPath | Out-Null
        }
        if (Test-Path $logPath) { Remove-Item $logPath -Force }

        if ($isTar) {
            # Check for tar
            $tarStatus = Invoke-ExternalCommand $7zPath @('l', "`"$Path`"") -LogPath $logPath
            if ($tarStatus) {
                # Get inner tar file name
                $tarFile = (Get-Content -Path $logPath)[-4] -replace '.{53}(.*)', '$1'
                Expand-7zipArchive -Path (Join-Path $DestinationPath $tarFile) -DestinationPath $DestinationPath -ExtractDir $ExtractDir -Removal
            } else {
                throw [ScoopException]::new("Decompress error|-Failed to list files in $Path.`nNot a 7zip supported archive file.") # TerminatingError thrown
            }
        }

        # Remove original archive file
        if ($Removal) { Remove-Item $Path -Force }
    }
}

function Expand-MsiArchive {
    <#
    .SYNOPSIS
        Extract files from msi files.
    .PARAMETER Path
        Specifies the path to the file.
    .PARAMETER DestinationPath
        Specifies the location, where file should be extracted.
    .PARAMETER ExtractDir
        Specifies to extract only nested directory inside file.
    .PARAMETER Switches
        Specifies additional parameters passed to the extraction.
    .PARAMETER Removal
        Specifies to remove the file after extraction is done.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        # TODO: Check wildcard support
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [String] $ExtractDir,
        [Parameter(ValueFromRemainingArguments)]
        [String] $Switches,
        [Switch] $Removal
    )

    process {
        if (!$DestinationPath) { $DestinationPath = Split-Path $Path -Parent }
        $DestinationPath = $DestinationPath.TrimEnd('\')

        if ($ExtractDir) {
            $originalDestination = $DestinationPath
            $DestinationPath = Join-Path $DestinationPath '_tmp'
        }

        if ((get_config 'MSIEXTRACT_USE_LESSMSI' $true)) {
            $msiPath = Get-HelperPath -Helper 'Lessmsi'
            $argList = @('x', "`"$Path`"", "`"$DestinationPath\\`"")
        } else {
            $msiPath = 'msiexec.exe'
            $argList = @('/a', "`"$Path`"", '/qn', "TARGETDIR=`"$DestinationPath\\SourceDir`"")
        }

        $logPath = Split-Path $Path -Parent | Join-Path -ChildPath 'msi.log'
        if ($Switches) { $argList += (-split $Switches) }

        $status = Invoke-ExternalCommand $msiPath $argList -LogPath $logPath

        if (!$status) {
            throw [ScoopException]::new((_decompressErrorPrompt $Path $logPath)) # TerminatingError thrown
        }

        $sourceDir = Join-Path $DestinationPath 'SourceDir'
        if ($ExtractDir -and (Test-Path $sourceDir)) {
            movedir (Join-Path $sourceDir $ExtractDir) $originalDestination | Out-Null
            Remove-Item $DestinationPath -Recurse -Force
        } elseif ($ExtractDir) {
            movedir (Join-Path $DestinationPath $ExtractDir) $originalDestination | Out-Null
            Remove-Item $DestinationPath -Recurse -Force
        } elseif (Test-Path $sourceDir) {
            movedir $sourceDir $DestinationPath | Out-Null
        }

        # ??
        $fnamePath = Join-Path $DestinationPath (fname $Path)
        if (($DestinationPath -ne (Split-Path $Path)) -and (Test-Path $fnamePath)) { Remove-Item $fnamePath -Force }

        if (Test-Path $logPath) { Remove-Item $logPath -Force }

        # Remove original archive file
        if ($Removal) { Remove-Item $Path -Force }
    }
}

function Expand-InnoArchive {
    <#
    .SYNOPSIS
        Extract files from innosetup file.
    .PARAMETER Path
        Specifies the path to the file.
    .PARAMETER DestinationPath
        Specifies the location, where file should be extracted.
    .PARAMETER ExtractDir
        Specifies to extract only nested directory inside file.
    .PARAMETER Switches
        Specifies additional parameters passed to the extraction.
    .PARAMETER Removal
        Specifies to remove the file after extraction is done.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        # TODO: Check wildcard support
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [String] $ExtractDir,
        [Parameter(ValueFromRemainingArguments)]
        [String] $Switches,
        [Switch] $Removal,
        [Switch] $UseInnoextract
    )

    process {
        if (!$DestinationPath) { $DestinationPath = Split-Path $Path -Parent }
        $DestinationPath = $DestinationPath.TrimEnd('\').TrimEnd('/')

        $isInnoextract = (get_config 'INNOSETUP_USE_INNOEXTRACT' $false) -or $UseInnoextract
        if ($isInnoextract) {
            Write-UserMessage -Message 'Using innoextract is experimental' -Warning

            $logPath = Split-Path $Path -Parent | Join-Path -ChildPath 'innoextract.log'
            $argList = @('--extract', '--output-dir', """$DestinationPath""", '--default-language', '"enu"')
            $innoPath = Get-HelperPath -Helper 'Innoextract'
            $inno = 'innoextract'

            switch -Regex ($ExtractDir) {
                '^[^{].*' {
                    $toMove = "app\$ExtractDir"
                    $argList += '--include', """$toMove"""
                }
                '^{.*' {
                    $toMove = (($ExtractDir -replace '{') -replace '}') -replace '_', '$' # TODO: ?? _ => $
                    $argList += '--include', """$toMove"""
                }
                default {
                    $toMove = 'app'
                    $argList += '--include', """$toMove"""
                }
            }
        } else {
            $logPath = Split-Path $Path -Parent | Join-Path -ChildPath 'innounp.log'
            $argList = @('-x', "-d`"$DestinationPath`"", '-y')
            $innoPath = Get-HelperPath -Helper 'Innounp'
            $inno = 'innounp'

            switch -Regex ($ExtractDir) {
                '^[^{].*' { $argList += "-c""{app}\$ExtractDir""" }
                '^{.*' { $argList += "-c""$ExtractDir""" }
                default { $argList += '-c"{app}"' }
            }
        }

        if ($Switches) { $argList += (-split $Switches) }
        $argList += """$Path"""

        try {
            $status = Invoke-ExternalCommand $innoPath $argList -LogPath $logPath
        } catch [System.Management.Automation.ParameterBindingException] {
            throw [ScoopException]::new("'$inno' is not installed or cannot be used") # TerminatingError thrown
        }

        if (!$status) {
            throw [ScoopException]::new((_decompressErrorPrompt $Path $logPath)) # TerminatingError thrown
        }

        # Innoextract --include do not extract the directory, it only filter the content
        # Need to manually move the nested directories
        if ($isInnoextract) { movedir "$DestinationPath\$toMove" $DestinationPath | Out-Null }

        if (Test-Path $logPath) { Remove-Item $logPath -Force }

        # Remove original archive file
        if ($Removal) { Remove-Item $Path -Force }
    }
}

function Expand-ZipArchive {
    <#
    .SYNOPSIS
        Extract files from zip archive.
    .PARAMETER Path
        Specifies the path to the archive.
    .PARAMETER DestinationPath
        Specifies the location, where archive should be extracted.
    .PARAMETER ExtractDir
        Specifies to extract only nested directory inside archive.
    .PARAMETER Removal
        Specifies to remove the archive after extraction is done.
    #>
    [CmdletBinding()]
    param (
        # TODO: Check wildcard support
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [String] $ExtractDir,
        [Switch] $Removal
    )

    process {
        if (!$DestinationPath) { $DestinationPath = Split-Path $Path -Parent }

        if ($ExtractDir) {
            $originalDestination = $DestinationPath
            $DestinationPath = Join-Path $DestinationPath '_tmp'
        }

        # Compatible with Pscx (https://github.com/Pscx/Pscx)
        Microsoft.PowerShell.Archive\Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force

        if ($ExtractDir) {
            movedir (Join-Path $DestinationPath $ExtractDir) $originalDestination | Out-Null
            Remove-Item $DestinationPath -Recurse -Force
        }

        # Remove original archive file
        if ($Removal) { Remove-Item $Path -Force }
    }
}

function Expand-DarkArchive {
    <#
    .SYNOPSIS
        Extract files from dark installers.
    .PARAMETER Path
        Specifies the path to the dark installer.
    .PARAMETER DestinationPath
        Specifies the location, where installer should be extracted.
    .PARAMETER Switches
        Specifies additional parameters passed to the extraction.
    .PARAMETER Removal
        Specifies to remove the installer after extraction is done.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        # TODO: Check wildcard support
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [Parameter(ValueFromRemainingArguments)]
        [String] $Switches,
        [Switch] $Removal
    )

    process {
        if (!$DestinationPath) { $DestinationPath = Split-Path $Path -Parent }

        $logPath = Split-Path $Path -Parent | Join-Path -ChildPath 'dark.log'
        $argList = @('-nologo', "-x `"$DestinationPath`"", "`"$Path`"")
        if ($Switches) { $argList += (-split $Switches) }

        try {
            $status = Invoke-ExternalCommand (Get-HelperPath -Helper 'Dark') $argList -LogPath $logPath
        } catch [System.Management.Automation.ParameterBindingException] {
            throw [ScoopException]::new('''dark'' is not installed or cannot be used') # TerminatingError thrown
        }

        if (!$status) {
            throw [ScoopException]::new((_decompressErrorPrompt $Path $logPath)) # TerminatingError thrown
        }
        if (Test-Path $logPath) { Remove-Item $logPath -Force }

        # Remove original archive file
        if ($Removal) { Remove-Item $Path -Force }
    }
}

function Expand-ZstdArchive {
    <#
    .SYNOPSIS
        Extract files from zstd archive.
        The final extracted from zstd archive will be named same as original file, but without .zst extension.
    .PARAMETER Path
        Specifies the path to the zstd archive.
    .PARAMETER DestinationPath
        Specifies the location, where archive should be extracted to.
    .PARAMETER ExtractDir
        Specifies to extract only nested directory inside archive.
    .PARAMETER Switches
        Specifies additional parameters passed to the extraction.
    .PARAMETER Overwrite
        Specifies to override files with same name.
    .PARAMETER Removal
        Specifies to remove the archive after extraction is done.
    .PARAMETER Skip7zip
        Specifies to not extract resulted file of zstd extraction.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        # TODO: Check wildcard support
        [String] $Path,
        [Parameter(Position = 1)]
        [Alias('ExtractTo', 'Target')]
        [String] $DestinationPath,
        [String] $ExtractDir,
        [Parameter(ValueFromRemainingArguments)]
        [String] $Switches,
        [Switch] $Overwrite,
        [Switch] $Removal,
        [Switch] $Skip7zip
    )

    begin {
        $zstdPath = Get-HelperPath -Helper 'Zstd'
        if ($null -eq $zstdPath) { throw 'Ignore|-''zstd'' is not installed or cannot be used' } # TerminatingError thrown

        $argList = @('-d', '-v')
        if ($Switches) { $argList += (-split $Switches) }
        if ($Overwrite) { $argList += '-f' }
    }

    process {
        $_path = $Path
        $_item = Get-Item $_path
        $_log = Join-Path $_item.Directory.FullName 'zstd.log'
        $_extractDir = $ExtractDir
        $_dest = $DestinationPath
        $_output = Join-Path $_dest $_item.BaseName

        $_arg = $argList
        if ($Removal) { $_arg += '--rm' }
        $_arg += "`"$_path`"", '-o', "`"$_output`""

        Confirm-DirectoryExistence -LiteralPath $_dest | Out-Null
        $status = Invoke-ExternalCommand -Path $zstdPath -ArgumentList $_arg -LogPath $_log
        if (!$status) {
            throw [ScoopException]::new((_decompressErrorPrompt $_path $_log)) # TerminatingError thrown
        }

        Remove-Item -Path $_log -ErrorAction 'SilentlyContinue' -Force

        $isTar = Test-TarAchive -Path $_path
        if ($Skip7zip -or !$isTar) { return }

        try {
            Expand-7zipArchive -Path $_output -DestinationPath $_dest -ExtractDir $_extractDir -Removal
        } catch {
            throw $_
        }
    }
}

$__importedDecompress__ = $true
