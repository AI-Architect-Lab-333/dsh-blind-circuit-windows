# Probe Tailscale llama.cpp /v1/models (ids only). Do not print document
# contents. Do not call /v1/chat/completions.
param(
    [string]$DshRepo = ""
)

$ErrorActionPreference = "Stop"

function Get-SparkUrls {
    $settings = Join-Path $env:USERPROFILE ".dsh\settings.yaml"
    $text = $null
    $vl = $null
    if (Test-Path $settings) {
        $raw = Get-Content -Raw -Path $settings
        if ($raw -match 'spark:\s*\r?\n(?:[^\n]*\r?\n)*?\s*baseURL:\s*(\S+)') {
            $text = $Matches[1].Trim('"').Trim("'")
        }
        if ($raw -match 'spark-vl:\s*\r?\n(?:[^\n]*\r?\n)*?\s*baseURL:\s*(\S+)') {
            $vl = $Matches[1].Trim('"').Trim("'")
        }
    }
    if (-not $text) { $text = $env:SPARK_TEXT_URL }
    if (-not $vl) { $vl = $env:SPARK_VL_URL }
    return @{ Text = $text; Vl = $vl }
}

function Probe-Models([string]$Url) {
    if (-not $Url) {
        Write-Output "SKIP (no URL)"
        return
    }
    $modelsUrl = $Url.TrimEnd('/')
    if ($modelsUrl -notmatch '/v1/models$') {
        $modelsUrl = $modelsUrl + '/models'
        if ($modelsUrl -notmatch '/v1/models$') {
            $modelsUrl = ($Url.TrimEnd('/') -replace '/v1$', '') + '/v1/models'
        }
    }
    try {
        $r = Invoke-RestMethod -Uri $modelsUrl -TimeoutSec 10
        $ids = @($r.data | ForEach-Object { $_.id })
        Write-Output ("OK ids=" + ($ids -join ','))
    } catch {
        Write-Output "FAIL"
    }
}

$urls = Get-SparkUrls
Write-Output "spark-text $(Probe-Models $urls.Text)"
Write-Output "spark-vl $(Probe-Models $urls.Vl)"

$listening = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Output "dsh-web ALREADY http://127.0.0.1:3080"
    exit 0
}

Write-Output "dsh-web not listening on 3080"
Write-Output "Start it in a process that outlives this script:"
Write-Output "  cd <deepseek-harness-checkout>"
Write-Output "  pnpm dsh web --no-open"
Write-Output "Do not Start-Process -WindowStyle Hidden from a short agent job: the Windows Job Object kills it."
if ($DshRepo -and -not (Test-Path (Join-Path $DshRepo "package.json"))) {
    Write-Output "FAIL dsh repo missing"
    exit 1
}
exit 2
