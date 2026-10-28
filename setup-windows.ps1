$ErrorActionPreference = 'Stop'
$forward = @($args)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    Write-Host 'Install Git for Windows, reopen the terminal, and rerun:'
    Write-Host '  winget install --id Git.Git -e'
    exit 2
}
$execPath = (& $gitCommand.Source --exec-path).Trim()
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$search = $execPath
$gitBash = $null
while ($search) {
    foreach ($relative in @('bin\bash.exe', 'usr\bin\bash.exe')) {
        $candidate = Join-Path $search $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $gitBash = $candidate; break }
    }
    if ($gitBash) { break }
    $parent = Split-Path $search -Parent
    if ($parent -eq $search) { break }
    $search = $parent
}
if (-not $gitBash) { Write-Host 'Repair Git for Windows: its Bash executable is missing.'; exit 2 }
$script = (Join-Path $PSScriptRoot 'setup-common.sh').Replace('\','/')
& $gitBash $script windows @forward
exit $LASTEXITCODE
