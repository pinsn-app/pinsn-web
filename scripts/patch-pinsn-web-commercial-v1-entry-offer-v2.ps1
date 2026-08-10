param(
    [Parameter(Mandatory = $false)]
    [string]$WebRoot = "C:\pinsn\pinsn-web"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

if (-not (Test-Path -LiteralPath $WebRoot)) {
    throw ("pinsn-web directory does not exist: {0}" -f $WebRoot)
}

$resolvedRoot = (Resolve-Path -LiteralPath $WebRoot).Path
$indexPath = Join-Path $resolvedRoot "index.html"

if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "pinsn-web index.html is missing."
}

$before = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8

$expected = "<h2>Recevez votre Diagnostic PINSN, court et factuel.</h2>"
$replacement = "<h2>Recevez votre Diagnostic PINSN gratuit, court et factuel.</h2>"

$expectedCount = ([regex]::Matches(
    $before,
    [regex]::Escape($expected)
)).Count

$canonicalCountBefore = ([regex]::Matches(
    $before,
    [regex]::Escape("Diagnostic PINSN gratuit")
)).Count

if ($canonicalCountBefore -gt 0) {
    Write-Host ""
    Write-Host "Canonical entry offer already present."
    Write-Host "NO CHANGE."
    exit 0
}

if ($expectedCount -ne 1) {
    throw (
        "Expected exactly one current landing heading before patch; found {0}. Refusing broad replacement." -f
        $expectedCount
    )
}

$protected = @(
    "Votre activité mérite d’inspirer autant confiance en ligne que dans la réalité.",
    "Le fait est fondamental.",
    "PINSN conseille. Vous décidez.",
    "contact@pinsn.fr",
    "https://pinsn.fr"
)

foreach ($text in $protected) {
    if (-not $before.Contains($text)) {
        throw ("Protected Commercial V1 landing text is missing before patch: {0}" -f $text)
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $resolvedRoot (".pinsn\backups\commercial-v1-entry-offer-" + $timestamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backupPath = Join-Path $backupRoot "index.html"

Copy-Item -LiteralPath $indexPath -Destination $backupPath -Force

try {
    $after = $before.Replace($expected, $replacement)

    Write-Utf8NoBom `
        -Path $indexPath `
        -Content $after

    $check = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8

    $canonicalCountAfter = ([regex]::Matches(
        $check,
        [regex]::Escape("Diagnostic PINSN gratuit")
    )).Count

    if ($canonicalCountAfter -ne 1) {
        throw (
            "Expected exactly one canonical 'Diagnostic PINSN gratuit' after patch; found {0}." -f
            $canonicalCountAfter
        )
    }

    if ($check.Contains("pinsn.fr@gmail.com")) {
        throw "Private Gmail address became visible in landing index.html."
    }

    foreach ($text in $protected) {
        if (-not $check.Contains($text)) {
            throw ("Protected Commercial V1 landing text changed unexpectedly: {0}" -f $text)
        }
    }

    # PowerShell 5.1 can surface native stderr as ErrorRecord when
    # ErrorActionPreference=Stop. Git line-ending warnings are non-fatal,
    # so only the native exit code is authoritative here.
    $previousEap = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"
        $diff = & git -C $resolvedRoot diff --no-ext-diff -- index.html 2>&1
        $gitExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousEap
    }

    if ($gitExitCode -ne 0) {
        throw ("git diff failed with exit code {0}." -f $gitExitCode)
    }

    Write-Host ""
    Write-Host "Commercial V1 entry offer patch validated."
    Write-Host ("Backup: {0}" -f $backupPath)
    Write-Host ""
    Write-Host "Changed only:"
    Write-Host "  Recevez votre Diagnostic PINSN, court et factuel."
    Write-Host "  -> Recevez votre Diagnostic PINSN gratuit, court et factuel."
    Write-Host ""
    Write-Host "=== GIT DIFF index.html ==="
    $diff | Out-Host
    Write-Host ""
    Write-Host "NO EMAIL CHANGE."
    Write-Host "NO PDF CHANGE."
    Write-Host "NO DEPLOY."
    Write-Host "NO COMMIT."
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $indexPath -Force

    throw (
        "Commercial V1 entry offer patch failed and index.html was restored. Cause: {0}" -f
        $_.Exception.Message
    )
}
