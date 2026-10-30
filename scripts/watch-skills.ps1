
# Theo doi thu muc skills/ va chay sync-skills.ps1 moi khi co thay doi.
# Luu y: chi theo doi skills/; thay doi o scripts/claude-global.template.md chi duoc ap dung
# khi sync-skills.ps1 chay (git hook post-merge/post-rewrite, watcher nay, hoac chay tay).
# Giu file nay chi gom ky tu ASCII (tieng Viet khong dau) vi PowerShell 5.1 doc .ps1 khong BOM theo ANSI.

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$skillsDir = Join-Path $repo "skills"
$syncScript = Join-Path $PSScriptRoot "sync-skills.ps1"

if (!(Test-Path $skillsDir)) {
    throw "Khong tim thay thu muc skills: $skillsDir"
}

if (!(Test-Path $syncScript)) {
    throw "Khong tim thay script: $syncScript"
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $skillsDir
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName `
    -bor [System.IO.NotifyFilters]::FileName `
    -bor [System.IO.NotifyFilters]::LastWrite
$watcher.EnableRaisingEvents = $true

Write-Host "Dang theo doi Skills: $skillsDir" -ForegroundColor Cyan
Write-Host "Nhan Ctrl+C de dung." -ForegroundColor Yellow

$action = {
    $scriptPath = $Event.MessageData
    Start-Sleep -Milliseconds 800

    try {
        & $scriptPath
        Write-Host "Da kiem tra dong bo Skill luc $(Get-Date -Format 'HH:mm:ss')" `
            -ForegroundColor Green
    }
    catch {
        Write-Host "Loi dong bo: $_" -ForegroundColor Red
    }
}

$subscriptions = @(
    Register-ObjectEvent $watcher Created -Action $action -MessageData $syncScript
    Register-ObjectEvent $watcher Changed -Action $action -MessageData $syncScript
    Register-ObjectEvent $watcher Renamed -Action $action -MessageData $syncScript
)

# Dong bo cac Skill hien co truoc khi theo doi
& $syncScript

try {
    while ($true) {
        Wait-Event -Timeout 1 | Out-Null
    }
}
finally {
    $watcher.EnableRaisingEvents = $false

    foreach ($subscription in $subscriptions) {
        Unregister-Event -SubscriptionId $subscription.Id `
            -ErrorAction SilentlyContinue
        Remove-Job -Id $subscription.Id -Force `
            -ErrorAction SilentlyContinue
    }

    $watcher.Dispose()
}
