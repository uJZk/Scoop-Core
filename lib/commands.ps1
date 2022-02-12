if ($__importedCommands__ -eq $true) {
    return
} else {
    Write-Verbose 'Importing commands'
}
$__importedCommands__ = $false

'core', 'Helpers' | ForEach-Object {
    . (Join-Path $PSScriptRoot "${_}.ps1")
}

function command_files {
    $libExec = Join-Path $PSScriptRoot '..\libexec'
    $shims = Join-Path $SCOOP_ROOT_DIRECTORY 'shims'

    Confirm-DirectoryExistence -LiteralPath $shims | Out-Null

    return @(Get-ChildItem -LiteralPath $libExec, $shims -ErrorAction 'SilentlyContinue' | Where-Object -Property 'Name' -Match -Value 'scoop-.*?\.ps1$')
}

function command_name($filename) {
    $filename.name | Select-String 'scoop-(.*?)\.ps1$' | ForEach-Object { $_.Matches[0].Groups[1].Value }
}

function commands {
    command_files | ForEach-Object { command_name $_ }
}

function command_path($cmd) {
    $cmd_path = Join-Path $PSScriptRoot "..\libexec\scoop-$cmd.ps1"

    # Built in commands
    if (!(Test-Path -LiteralPath $cmd_path -PathType 'Leaf')) {
        # Get path from shim
        $shim_path = Join-Path $SCOOP_ROOT_DIRECTORY "shims\scoop-$cmd.ps1"
        if (!(Test-Path -LiteralPath $shim_path -PathType 'Leaf')) {
            throw [ScoopException]::new("Shim for alias '$cmd' does not exist") # TerminatingError thrown
        }

        $cmd_path = $shim_path
        $line = @((Get-Content -LiteralPath $shim_path -Encoding 'UTF8') | Where-Object { $_.StartsWith('$path') })
        if ($line) {
            # TODO: Drop Invoke-Expression
            Invoke-Expression -Command "$line"
            $cmd_path = $path
        }
    }

    return $cmd_path
}

function Invoke-ScoopCommand {
    param($cmd, $arguments)

    & (command_path $cmd) @arguments
}

$__importedCommands__ = $true
