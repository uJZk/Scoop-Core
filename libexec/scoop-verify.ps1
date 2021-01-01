# Usage: scoop verify <manifestPath>
# Summary: Verify manifest functionality/quality
#
# Options:
#   -h, --help                Show help for this command.
#   -i, --install             Install the app globally.
#   -a, --arch <32bit|64bit>  Use the specified architecture, if the app supports it.
#   -m, --machine-readable    Enable machine readable output (Return exit code and json output)

'Helpers', 'core', 'manifest', 'buckets', 'decompress', 'install', 'shortcuts', 'psmodules', 'Update', 'Versions', 'help', 'getopt', 'depends' | ForEach-Object {
    . (Join-Path $PSScriptRoot "..\lib\$_.ps1")
}

Reset-Alias

$opt, $apps, $err = getopt $args 'ima:' 'install', 'machine-readable', 'arch='
if ($err) { Stop-ScoopExecution -Message "scoop install: $err" -ExitCode 2 }

$exitCode = 0
$independent = $opt.i -or $opt.independent
$architecture = default_architecture

try {
    $architecture = ensure_architecture ($opt.a + $opt.arch)
} catch {
    Stop-ScoopExecution -Message "$_" -ExitCode 2
}
if (!$apps) { Stop-ScoopExecution -Message 'Parameter <apps> missing' -Usage (my_usage) }
if ($global -and !(is_admin)) { Stop-ScoopExecution -Message 'Admin privileges are required to manipulate with globally installed apps' -ExitCode 4 }

# Schema         validor executable or library?
# Properties     Covered by schema partially
#   Homepage trailing /
#   License identifier
# URLS + Hashes Invoke-ScoopCommand 'download' -b $_
# Scripts
#   Replace deprecated functions
#   ??Try with code style??
# Checkver
# Autoupdate
# Installation
# Update
# Uninstallation
# Format

exit $exitCode
