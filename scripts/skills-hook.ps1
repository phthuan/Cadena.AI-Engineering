
# Hook cua Claude Code (PostToolUse Write|Edit va UserPromptSubmit).
# So sanh skill trong repo voi Junction trong ~/.claude/skills; chi chay sync-skills.ps1 khi lech.
# Luu y: giu file nay chi gom ky tu ASCII (tieng Viet khong dau) vi PowerShell 5.1 doc .ps1 khong BOM theo ANSI.

param(
    [ValidateSet("Tool", "Prompt")]
    [string]$Mode = "Prompt"
)

$ErrorActionPreference = "Stop"

function Get-NormalizedPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

try {
    $repo = Split-Path -Parent $PSScriptRoot
    $sourceSkills = Get-NormalizedPath (Join-Path $repo "skills")
    $targetSkills = Join-Path $env:USERPROFILE ".claude\skills"

    $payload = [Console]::In.ReadToEnd()

    # Voi Write/Edit: bo qua ngay neu file vua ghi khong nam trong skills/ cua repo nay.
    if ($Mode -eq "Tool") {
        $filePath = $null
        if ($payload) {
            $data = $payload | ConvertFrom-Json
            if ($data.tool_input) { $filePath = $data.tool_input.file_path }
        }
        if (!$filePath) { exit 0 }

        $full = Get-NormalizedPath $filePath
        if (!$full.StartsWith($sourceSkills + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            exit 0
        }
    }

    $expected = @(Get-ChildItem $sourceSkills -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") -PathType Leaf } |
        ForEach-Object { $_.Name } | Sort-Object)

    # Chi tinh cac Junction tro vao skills/ cua repo nay.
    $linked = @()
    if (Test-Path $targetSkills) {
        $linked = @(Get-ChildItem $targetSkills -Force |
            Where-Object { $_.LinkType -eq "Junction" } |
            Where-Object {
                $link = $_
                @($link.Target) | Where-Object {
                    $_ -and [string]::Equals(
                        [System.IO.Path]::GetDirectoryName((Get-NormalizedPath $_)),
                        $sourceSkills,
                        [System.StringComparison]::OrdinalIgnoreCase)
                }
            } |
            ForEach-Object { $_.Name } | Sort-Object)
    }

    $added = @($expected | Where-Object { $linked -notcontains $_ })
    $removed = @($linked | Where-Object { $expected -notcontains $_ })

    if ($added.Count -eq 0 -and $removed.Count -eq 0) { exit 0 }

    & (Join-Path $PSScriptRoot "sync-skills.ps1") *> $null

    $parts = @()
    if ($added.Count -gt 0) { $parts += "added: " + ($added -join ", ") }
    if ($removed.Count -gt 0) { $parts += "removed: " + ($removed -join ", ") }
    $message = "Cadena skills synced (" + ($parts -join "; ") + "). Open a new session if the skill list does not update."

    @{ systemMessage = $message } | ConvertTo-Json -Compress
    exit 0
}
catch {
    @{ systemMessage = "Cadena skills hook failed: $($_.Exception.Message)" } | ConvertTo-Json -Compress
    exit 0
}
