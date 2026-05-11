#Requires -Version 5.1
<#
.SYNOPSIS
    configure-api-scenario.ps1 — Configures a LoadRunner API protocol scenario
    with run-time parameters and individual user credentials.

.DESCRIPTION
    - Patches the .lrs scenario XML to set VUser count, duration, and ramp-up.
    - Injects per-user credentials from the GitHub Actions environment (populated
      from GitHub Secrets / repository variables).
    - Sets the license server and validates the scenario before handing off to
      run-lr-scenario.ps1.
#>

param(
    [Parameter(Mandatory)] [string] $ScenarioFile,
    [Parameter(Mandatory)] [int]    $VUsers,
    [Parameter(Mandatory)] [int]    $Duration,
    [Parameter(Mandatory)] [int]    $RampUp,
    [Parameter(Mandatory)] [string] $TargetEnv,
    [Parameter(Mandatory)] [string] $LicenseServer,
    [string] $ParameterFile = "configs\params-api.dat"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg) Write-Host "  ➤ $Msg" -ForegroundColor Cyan }

# ── 1. Load scenario XML ─────────────────────────────────────────────────────
Write-Step "Loading scenario: $ScenarioFile"
if (-not (Test-Path $ScenarioFile)) {
    throw "Scenario file not found: $ScenarioFile"
}
[xml]$lrs = Get-Content $ScenarioFile -Encoding UTF8

# ── 2. Patch VUser count ─────────────────────────────────────────────────────
Write-Step "Setting VUser count → $VUsers"
$lrs.Scenario.Groups.Group | ForEach-Object {
    $_.VUser = $VUsers.ToString()
}

# ── 3. Patch schedule duration & ramp-up ────────────────────────────────────
Write-Step "Setting Duration → ${Duration}m, Ramp-Up → ${RampUp}m"
$schedule = $lrs.Scenario.Scheduler
if ($schedule) {
    $schedule.Duration  = ($Duration  * 60).ToString()  # LR uses seconds
    $schedule.RampUpTime = ($RampUp   * 60).ToString()
}

# ── 4. Inject individual credentials via parameter file ─────────────────────
Write-Step "Injecting per-user credentials for $TargetEnv"

# Credentials are stored as GitHub secrets in the pattern:
#   LR_USER_<N>_USERNAME  /  LR_USER_<N>_PASSWORD  (N = 1..VUsers)
# For large VUser pools, a pool approach is used where credentials cycle.

$credRows = @()
for ($i = 1; $i -le [Math]::Min($VUsers, 50); $i++) {
    $userVar = "LR_USER_${i}_USERNAME"
    $passVar = "LR_USER_${i}_PASSWORD"
    $u = [System.Environment]::GetEnvironmentVariable($userVar)
    $p = [System.Environment]::GetEnvironmentVariable($passVar)
    if ($u -and $p) {
        $credRows += "$u,$p"
    }
}

# Fall back to shared service account if individual creds are absent
if ($credRows.Count -eq 0) {
    $sharedUser = $env:LR_SCRIPT_USERNAME
    $sharedPass = $env:LR_SCRIPT_PASSWORD
    if (-not $sharedUser) { throw "No user credentials available — set LR_SCRIPT_USERNAME secret" }
    Write-Warning "No per-user creds found; using shared account (pool of 1)"
    $credRows = @("$sharedUser,$sharedPass")
}

Write-Step "Credential pool: $($credRows.Count) entries"
$paramContent  = "username,password`n"
$paramContent += $credRows -join "`n"
$paramDir = Split-Path $ParameterFile -Parent
if (-not (Test-Path $paramDir)) { New-Item -ItemType Directory -Path $paramDir -Force | Out-Null }
$paramContent | Set-Content $ParameterFile -Encoding UTF8

# Update scenario to reference the param file
$paramNode = $lrs.SelectSingleNode("//ParameterFile")
if ($paramNode) {
    $paramNode.InnerText = (Resolve-Path $ParameterFile).Path
}

# ── 5. Set environment-specific base URL ────────────────────────────────────
Write-Step "Configuring target environment: $TargetEnv"
$urlMap = @{
    dev        = $env:TARGET_URL_DEV
    staging    = $env:TARGET_URL_STAGING
    production = $env:TARGET_URL_PROD
}
$baseUrl = $urlMap[$TargetEnv]
if (-not $baseUrl) { throw "No TARGET_URL_$($TargetEnv.ToUpper()) secret configured" }

$runtimeNode = $lrs.SelectSingleNode("//RuntimeSettings/WebUrl")
if ($runtimeNode) { $runtimeNode.InnerText = $baseUrl }

# ── 6. Set license server ─────────────────────────────────────────────────────
Write-Step "Setting license server: $LicenseServer"
$licNode = $lrs.SelectSingleNode("//LicenseServer")
if ($licNode) { $licNode.InnerText = $LicenseServer }

# ── 7. Save patched scenario ─────────────────────────────────────────────────
$patchedFile = $ScenarioFile -replace '\.lrs$', '_patched.lrs'
$lrs.Save($patchedFile)
Write-Step "Saved patched scenario → $patchedFile"

# ── 8. Validate with lr_batch (smoke check) ──────────────────────────────────
Write-Step "Validating scenario (dry-run)..."
$lrBatch = "$env:LR_INSTALL_DIR\bin\lr_batch.exe"
if (Test-Path $lrBatch) {
    $result = & $lrBatch -Validate -Scenario $patchedFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Scenario validation failed:`n$result"
    }
    Write-Step "Validation passed ✅"
} else {
    Write-Warning "lr_batch.exe not found at $lrBatch — skipping validation"
}

Write-Host "`n✅ API scenario configured successfully" -ForegroundColor Green
