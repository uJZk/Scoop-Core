@(
    @('core', 'Test-ScoopDebugEnabled'),
    @('Helpers', 'New-IssuePrompt'),
    @('manifest', 'Resolve-ManifestInformation')
) | ForEach-Object {
    if (!([bool] (Get-Command $_[1] -ErrorAction 'Ignore'))) {
        Write-Verbose "Import of lib '$($_[0])' initiated from '$PSCommandPath'"
        . (Join-Path $PSScriptRoot "$($_[0]).ps1")
    }
}

# Creates shortcut for the app in the start menu
function create_startmenu_shortcuts($manifest, $dir, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch)
    if ($shortcuts.Count -eq 0) { return }

    if ($SHOVEL_IS_UNIX) {
        Write-UserMessage -Message 'Creation of Start menu shortcuts is not supported on *nix' -Info
        return
    }

    if ($null -eq (shortcut_folder $global)) {
        Write-UserMessage -Message 'System specific folder ''commonstartmenu'' or ''startmenu'' is not defined. Skipping shortcuts creation' -Warning
        return
    }

    $shortcuts | Where-Object { $null -ne $_ } | ForEach-Object {
        $target = [System.IO.Path]::Combine($dir, $_.item(0))
        $target = New-Object System.IO.FileInfo($target)
        $name = $_.item(1)
        $arguments = ''
        $icon = $null
        if ($_.length -ge 3) {
            $arguments = $_.item(2)
        }
        if ($_.length -ge 4) {
            $icon = [System.IO.Path]::Combine($dir, $_.item(3))
            $icon = New-Object System.IO.FileInfo($icon)
        }
        $arguments = (Invoke-VariableSubstitution -Entity $arguments -Substitutes @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir })
        startmenu_shortcut $target $name $arguments $icon $global
    }
}

function shortcut_folder($global) {
    $base = if ($global) { 'commonstartmenu' } else { 'startmenu' }
    $directory = [System.Environment]::GetFolderPath($base)

    if ([String]::IsNullOrEmpty($directory)) { return $null }

    $directory = Join-Path -Path $directory -ChildPath 'Programs\Scoop Apps'

    return Confirm-DirectoryExistence -LiteralPath $directory
}

function startmenu_shortcut([System.IO.FileInfo] $target, $shortcutName, $arguments, [System.IO.FileInfo]$icon, $global) {
    $base = "Creating shortcut for $shortcutName ($(fname $target))"
    $baseError = "$base failed:"

    if (!$target.Exists) {
        Write-UserMessage -Message "$baseError Couldn't find $target" -Color DarkRed
        return
    }
    if ($icon -and !$icon.Exists) {
        Write-UserMessage -Message "$baseError Couldn't find icon $icon" -Color DarkRed
        return
    }

    $scoop_startmenu_folder = shortcut_folder $global
    $subdirectory = [System.IO.Path]::GetDirectoryName($shortcutName)
    if ($subdirectory) {
        $subdirectory = Confirm-DirectoryExistence -LiteralPath ([System.IO.Path]::Combine($scoop_startmenu_folder, $subdirectory))
    }

    $wsShell = New-Object -ComObject WScript.Shell
    $wsShell = $wsShell.CreateShortcut((Join-Path $scoop_startmenu_folder "$shortcutName.lnk"))
    $wsShell.TargetPath = $target.FullName
    $wsShell.WorkingDirectory = $target.DirectoryName
    if ($arguments) { $wsShell.Arguments = $arguments }
    if ($icon -and $icon.Exists) { $wsShell.IconLocation = $icon.FullName }
    $wsShell.Save()

    Write-UserMessage -Message $base
}

# Removes the Startmenu shortcut if it exists
function rm_startmenu_shortcuts($manifest, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch)
    if ($shortcuts.Count -eq 0) { return }

    if ($SHOVEL_IS_UNIX) {
        Write-UserMessage -Message 'Deletion of Start menu shortcuts is not supported on *nix' -Info
        return
    }

    $shortcutFolder = shortcut_folder $global
    if ($null -eq $shortcutFolder) {
        Write-UserMessage -Message 'System specific folder ''commonstartmenu'' or ''startmenu'' is not defined. Skipping shortcuts deletion' -Warning
        return
    }

    $shortcuts | Where-Object { $null -ne $_ } | ForEach-Object {
        $name = $_.item(1)
        $shortcut = Join-Path -Path $shortcutFolder -ChildPath "$name.lnk"

        Write-UserMessage -Message "Removing shortcut $(friendly_path $shortcut)"

        if (Test-Path $shortcut) { Remove-Item $shortcut }
    }
}
