# Adds the personal add-ons to an existing OpenJarvis install on Windows.
#   .\install.ps1                          # finds the install automatically
#   .\install.ps1 -Source C:\path\to\OpenJarvis
#   .\install.ps1 -NoSchedule              # skip the Task Scheduler jobs
param(
    [string]$Source = "",
    [switch]$NoSchedule
)
$ErrorActionPreference = "Stop"

# Runs a native command and fails on its exit code. Warnings that tools such
# as npm print to stderr must not stop the install, so they are not errors here.
function Invoke-Native([scriptblock]$Command, [string]$What) {
    $ErrorActionPreference = "Continue"
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Source) {
    $candidates = @($env:OPENJARVIS_SRC, "$env:LOCALAPPDATA\OpenJarvis\src", "$HOME\.openjarvis\src") | Where-Object { $_ }
    $Source = $candidates | Where-Object { Test-Path (Join-Path $_ ".git") } | Select-Object -First 1
}
if (-not $Source -or -not (Test-Path (Join-Path $Source ".git"))) {
    throw "Could not find the OpenJarvis source folder. Pass it with -Source <path>."
}
Write-Host "OpenJarvis source: $Source"

Push-Location $Source
try {
    if (git status --porcelain --untracked-files=no) {
        throw "The OpenJarvis folder has uncommitted changes. Commit or stash them first."
    }
    $patches = Get-ChildItem (Join-Path $here "patches") -Filter *.patch | Sort-Object Name
    try {
        Invoke-Native { git -c user.name="OpenJarvis add-ons" -c user.email="addons@localhost" am --3way --keep-cr $patches.FullName } "Applying the patches"
    } catch {
        & git am --abort 2>$null
        throw "The patches did not apply to this version of OpenJarvis. See README > Compatibility."
    }

    $venv = @((Join-Path $Source ".venv"), (Join-Path (Split-Path $Source) ".venv")) |
        Where-Object { Test-Path (Join-Path $_ "Scripts\python.exe") } | Select-Object -First 1
    if ($venv) {
        Write-Host "Installing python-docx and Playwright into $venv"
        Invoke-Native { uv pip install --python (Join-Path $venv "Scripts\python.exe") python-docx "playwright>=1.40" } "Installing Python packages"
    } else {
        Write-Warning "No .venv found; install python-docx and playwright into OpenJarvis's Python yourself."
    }

    Write-Host "Building the web UI"
    Push-Location frontend
    Invoke-Native { npm ci --no-audit --no-fund } "npm ci"
    Invoke-Native { npm run build } "Building the web UI"
    Pop-Location

    if (-not $NoSchedule -and $venv) {
        $pythonw = Join-Path $venv "Scripts\pythonw.exe"
        $every15 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
        $daily = New-ScheduledTaskTrigger -Daily -At "08:00"
        foreach ($job in @(@{Name = "Event Mate"; Agent = "eventmate"; Trigger = $every15},
                           @{Name = "Job Search"; Agent = "jobs"; Trigger = $daily})) {
            $action = New-ScheduledTaskAction -Execute $pythonw -Argument "-m openjarvis.personal.runner $($job.Agent)" -WorkingDirectory $Source
            Register-ScheduledTask -TaskPath "\OpenJarvis\" -TaskName $job.Name -Action $action -Trigger $job.Trigger -Force | Out-Null
            Write-Host "Scheduled: $($job.Name)"
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Done. Restart 'jarvis serve', open the web UI, then go to Settings:"
Write-Host "  Email accounts   - connect Gmail with an app password"
Write-Host "  Personal agents  - fill in your profile and resume, then press Run now"
