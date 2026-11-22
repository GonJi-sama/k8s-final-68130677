#Requires -Version 5.1
<#
.SYNOPSIS
    One-command 3-Node Kind Kubernetes setup, deployment, and full verification (ID: 68130677).
    Target: Windows + Docker Desktop (creates a 3-node Kind cluster: 1 control-plane + 2 workers).
#>

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ProjectRoot

$ClusterName = "k8s-68130677"
$KubeContext = "kind-$ClusterName"
$Namespace = "iam-68130677"
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$Domains = @("www.iam-68130677.com", "www.id-68130677.com", "admin.iam-68130677.com")
$KindVersion = "v0.24.0"
$KindDownloadUrl = "https://kind.sigs.k8s.io/dl/$KindVersion/kind-windows-amd64"
$IngressKindUrl = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml"
$LogFile = Join-Path $ProjectRoot "verification-log.txt"

function Write-Step {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Resolve-KindBinary {
    $cmd = Get-Command kind -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $localBinDir = Join-Path $ProjectRoot "bin"
    $localKind = Join-Path $localBinDir "kind.exe"
    if (Test-Path -LiteralPath $localKind) { return $localKind }

    Write-Host "kind CLI not found in PATH. Downloading official kind $KindVersion to .\bin\kind.exe ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $localBinDir -Force | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $KindDownloadUrl -OutFile $localKind -UseBasicParsing -ErrorAction Stop
    } catch {
        Fail "Failed to download kind CLI from $KindDownloadUrl. Install manually via: winget install Kubernetes.kind"
    }
    if (-not (Test-Path -LiteralPath $localKind)) {
        Fail "kind.exe was not saved properly."
    }
    Write-Host "[OK] Downloaded kind CLI to $localKind" -ForegroundColor Green
    return $localKind
}

function Test-HostsConfigured {
    if (-not (Test-Path -LiteralPath $HostsPath)) { return $false }
    $content = Get-Content -LiteralPath $HostsPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return $false }
    foreach ($d in $Domains) {
        $escaped = [Regex]::Escape($d)
        if ($content -notmatch "(?m)^\s*127\.0\.0\.1\s+[^#\r\n]*\b$escaped\b") {
            return $false
        }
    }
    return $true
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-HostsEntries {
    if (Test-HostsConfigured) {
        Write-Host "[OK] Windows hosts file already maps 127.0.0.1 for all 3 required domains." -ForegroundColor Green
        return
    }

    $hostsUpdater = @'
$ErrorActionPreference = "Stop"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
if (Test-Path -LiteralPath $hostsPath) {
    $item = Get-Item -LiteralPath $hostsPath -Force
    if ($item.IsReadOnly) { $item.IsReadOnly = $false }
    $content = Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue
} else {
    $content = ""
}
if ($null -eq $content) { $content = "" }

$domains = @("www.iam-68130677.com", "www.id-68130677.com", "admin.iam-68130677.com")
$toAdd = @()
foreach ($d in $domains) {
    $escaped = [Regex]::Escape($d)
    if ($content -notmatch "(?m)^\s*127\.0\.0\.1\s+[^#\r\n]*\b$escaped\b") {
        $toAdd += "127.0.0.1 $d"
    }
}

if ($toAdd.Count -gt 0) {
    $prefix = ""
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $prefix = "`r`n"
    }
    $block = $prefix + ($toAdd -join "`r`n") + "`r`n"
    [System.IO.File]::AppendAllText($hostsPath, $block, [System.Text.Encoding]::ASCII)
}
ipconfig /flushdns | Out-Null
'@

    if (Test-IsAdmin) {
        Write-Host "Updating Windows hosts file directly (running as Administrator)..."
        try {
            Invoke-Expression $hostsUpdater
        } catch {
            Fail "Failed to update $HostsPath : $($_.Exception.Message)"
        }
    } else {
        Write-Host "Requesting Administrator permission (UAC) to update Windows hosts file..." -ForegroundColor Yellow
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($hostsUpdater)
        $encoded = [Convert]::ToBase64String($bytes)
        try {
            $proc = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ErrorAction Stop -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded
            )
            if ($proc.ExitCode -ne 0) {
                Fail "Elevated hosts update exited with code $($proc.ExitCode)."
            }
        } catch {
            Fail "UAC prompt was cancelled or failed. Please approve UAC or run as Administrator to update $HostsPath."
        }
    }

    if (-not (Test-HostsConfigured)) {
        Fail "Failed to verify required domain entries in $HostsPath."
    }
    Write-Host "[OK] Updated $HostsPath and flushed DNS cache." -ForegroundColor Green
}

# ============================================================
# STEP 1: Check Prerequisites (Docker, kubectl, curl.exe, kind)
# ============================================================
Write-Step "[1/8] Checking Prerequisites (Docker Desktop, kubectl, kind)"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "docker command not found. Please install and start Docker Desktop."
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Fail "kubectl command not found. Please install kubectl or enable Kubernetes CLI in Docker Desktop."
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Fail "curl.exe not found in PATH."
}

& docker version 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Fail "Docker Engine is not running. Please start Docker Desktop first."
}

$KindExe = Resolve-KindBinary
Write-Host "[OK] Docker, kubectl, and kind ($KindExe) are ready." -ForegroundColor Green

# ============================================================
# STEP 2: Configure Windows hosts File
# ============================================================
Write-Step "[2/8] Configuring Windows hosts File"
Ensure-HostsEntries

# ============================================================
# STEP 3: Create / Reuse 3-Node Kind Cluster
# ============================================================
Write-Step "[3/8] Creating 3-Node Kind Kubernetes Cluster ($ClusterName)"

$clusters = & $KindExe get clusters 2>$null
if ($clusters -contains $ClusterName) {
    Write-Host "[OK] Kind cluster '$ClusterName' already exists. Reusing existing 3-node cluster." -ForegroundColor Green
} else {
    $port80 = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
    if ($port80) {
        $pids = ($port80 | Select-Object -ExpandProperty OwningProcess -Unique) -join ", "
        Write-Host "[WARNING] Port 80 is currently in use by PID(s): $pids." -ForegroundColor Yellow
        Write-Host "          If cluster creation fails binding port 80, stop IIS/Apache/XAMPP or disable ingress-nginx in Docker Desktop K8s." -ForegroundColor Yellow
    }
    Write-Host "Creating 3-node cluster from kind-config.yaml (1 control-plane + 2 workers)..."
    & $KindExe create cluster --config kind-config.yaml
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to create Kind cluster '$ClusterName'. Check if port 80/443 is already in use."
    }
}

& kubectl config use-context $KubeContext 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to switch kubectl context to $KubeContext."
}

Write-Host "Waiting for all 3 nodes to become Ready..."
& kubectl wait --for=condition=Ready nodes --all --timeout=180s
if ($LASTEXITCODE -ne 0) {
    Fail "Not all Kind nodes became Ready within 180 seconds."
}
$nodeList = (& kubectl get nodes --no-headers 2>$null)
$nodeCount = @($nodeList | Where-Object { $_ -match "\S" }).Count
Write-Host "[OK] Cluster active with $nodeCount nodes:" -ForegroundColor Green
& kubectl get nodes -o wide
if ($nodeCount -ne 3) {
    Fail "Expected 3 Kubernetes nodes, but found $nodeCount."
}

# ============================================================
# STEP 4: Build Local Docker Images & Load into 3-Node Kind Cluster
# ============================================================
Write-Step "[4/8] Building Local Images and Loading into Kind 3-Node Cluster"

$apps = @(
    @{ Name = "portal-68130677"; Tag = "portal-68130677:1.0"; Path = "apps/portal-68130677" },
    @{ Name = "app-research";    Tag = "app-research:1.0";    Path = "apps/app-research" },
    @{ Name = "api-68130677";    Tag = "api-68130677:1.0";    Path = "apps/api-68130677" },
    @{ Name = "admin-68130677";  Tag = "admin-68130677:1.0";  Path = "apps/admin-68130677" }
)

foreach ($app in $apps) {
    Write-Host "Building $($app.Tag) from $($app.Path)..."
    & docker build -t $app.Tag $app.Path
    if ($LASTEXITCODE -ne 0) {
        Fail "Docker build failed for $($app.Name)."
    }
}

Write-Host "Ensuring postgres:16-alpine image is available locally..."
& docker image inspect postgres:16-alpine 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    & docker pull postgres:16-alpine
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to pull postgres:16-alpine."
    }
}

Write-Host "Loading all 5 images into Kind cluster '$ClusterName'..."
foreach ($img in @("portal-68130677:1.0", "app-research:1.0", "api-68130677:1.0", "admin-68130677:1.0")) {
    & $KindExe load docker-image $img --name $ClusterName
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to load image $img into Kind cluster."
    }
}
Write-Host "[OK] All 5 images loaded into Kind cluster nodes." -ForegroundColor Green

# ============================================================
# STEP 5: Install NGINX Ingress Controller (Kind Provider)
# ============================================================
Write-Step "[5/8] Ensuring NGINX Ingress Controller (Kind Provider) is Ready"

& kubectl get namespace ingress-nginx 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing ingress-nginx controller for Kind..."
    & kubectl apply -f $IngressKindUrl
    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to install ingress-nginx for Kind."
    }
} else {
    Write-Host "[OK] ingress-nginx namespace already exists." -ForegroundColor Green
}

Write-Host "Waiting for ingress-nginx controller pod to become Ready..."
& kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
if ($LASTEXITCODE -ne 0) {
    Fail "ingress-nginx controller did not become Ready within 180 seconds."
}
Write-Host "[OK] NGINX Ingress Controller is Ready on control-plane node." -ForegroundColor Green

# ============================================================
# STEP 6: Apply Manifests (PostgreSQL First, then 4 Apps & Ingress)
# ============================================================
Write-Step "[6/8] Applying Kubernetes Manifests (Namespace, DB, 4 Apps, Ingress)"

$appDeployments = @("portal-68130677", "app-research", "api-68130677", "admin-68130677")
$existingDeps = @{}
foreach ($dep in $appDeployments) {
    & kubectl get deployment $dep -n $Namespace 1>$null 2>$null
    $existingDeps[$dep] = ($LASTEXITCODE -eq 0)
}

foreach ($mf in @("k8s/00-namespace.yaml", "k8s/01-config-secret.yaml", "k8s/02-postgres.yaml")) {
    & kubectl apply -f $mf
    if ($LASTEXITCODE -ne 0) { Fail "Failed to apply $mf." }
}

Write-Host "Waiting for PostgreSQL (postgres-68130677) to become Ready..."
& kubectl rollout status deployment/postgres-68130677 -n $Namespace --timeout=180s
if ($LASTEXITCODE -ne 0) {
    Fail "PostgreSQL deployment did not become Ready."
}

foreach ($mf in @("k8s/03-portal.yaml", "k8s/04-research.yaml", "k8s/05-api.yaml", "k8s/06-admin.yaml")) {
    & kubectl apply -f $mf
    if ($LASTEXITCODE -ne 0) { Fail "Failed to apply $mf." }
}

# Retry Ingress apply while ingress-nginx admission webhook initializes
$ingressApplied = $false
$lastIngressOut = ""
for ($attempt = 1; $attempt -le 12; $attempt++) {
    $lastIngressOut = & kubectl apply -f k8s/07-ingress.yaml 2>&1
    if ($LASTEXITCODE -eq 0) {
        $lastIngressOut | ForEach-Object { Write-Host $_ }
        $ingressApplied = $true
        break
    }
    Write-Host "Waiting for ingress-nginx admission webhook (attempt $attempt/12)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}
if (-not $ingressApplied) {
    Write-Host ($lastIngressOut | Out-String) -ForegroundColor Red
    Fail "Failed to apply k8s/07-ingress.yaml after 12 attempts."
}

foreach ($dep in $appDeployments) {
    if ($existingDeps[$dep]) {
        Write-Host "Restarting existing deployment/$dep to load freshly built image..."
        & kubectl rollout restart "deployment/$dep" -n $Namespace 1>$null
    }
}

# ============================================================
# STEP 7: Wait for All Deployments & Warmup All Endpoints
# ============================================================
Write-Step "[7/8] Waiting for All 4 Application Deployments & Ingress Sync"

foreach ($dep in $appDeployments) {
    & kubectl rollout status "deployment/$dep" -n $Namespace --timeout=150s
    if ($LASTEXITCODE -ne 0) {
        Fail "Rollout failed for deployment/$dep."
    }
}

$warmupUrls = @(
    "http://www.iam-68130677.com/",
    "http://www.id-68130677.com/",
    "http://www.iam-68130677.com/research",
    "http://www.iam-68130677.com/api-68130677/Hello",
    "http://admin.iam-68130677.com/"
)
Write-Host "Waiting for NGINX Ingress to sync all endpoints..."
$httpReady = $false
for ($i = 1; $i -le 20; $i++) {
    $allOk = $true
    foreach ($u in $warmupUrls) {
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 3 $u 2>$null
        if ($code -ne "200") {
            $allOk = $false
            break
        }
    }
    if ($allOk) {
        $httpReady = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $httpReady) {
    Write-Host "[WARNING] Not all endpoints returned HTTP 200 within 40s; proceeding to diagnostics." -ForegroundColor Yellow
}

# ============================================================
# STEP 8: Automated Verification & Evidence Log
# ============================================================
Write-Step "[8/8] 3-Node Cluster & HTTP Endpoint Verification"

$nodesOut = (& kubectl get nodes -o wide 2>&1) | Out-String
$getOut = (& kubectl get all,pvc,ingress -n $Namespace -o wide 2>&1) | Out-String
$descOut = (& kubectl describe ingress ingress-public ingress-admin -n $Namespace 2>&1) | Out-String

Write-Host $nodesOut
Write-Host $getOut

$checks = @(
    @{ Url = "http://www.iam-68130677.com/";                 Expected = "200"; Label = "portal-68130677 (www.iam)" },
    @{ Url = "http://www.id-68130677.com/";                  Expected = "200"; Label = "portal-68130677 (www.id alias)" },
    @{ Url = "http://www.iam-68130677.com/photo";            Expected = "200"; Label = "portal-68130677 (/photo from PostgreSQL)" },
    @{ Url = "http://www.iam-68130677.com/research";         Expected = "200"; Label = "app-research (/research)" },
    @{ Url = "http://www.id-68130677.com/research";          Expected = "200"; Label = "app-research (www.id /research)" },
    @{ Url = "http://www.iam-68130677.com/api-68130677/Hello"; Expected = "200"; Label = "api-68130677 (/api-68130677/Hello)" },
    @{ Url = "http://admin.iam-68130677.com/";               Expected = "200"; Label = "admin-68130677 (dashboard)" },
    @{ Url = "http://admin.iam-68130677.com/edit/portal";    Expected = "200"; Label = "admin-68130677 (edit portal)" },
    @{ Url = "http://admin.iam-68130677.com/edit/research";  Expected = "200"; Label = "admin-68130677 (edit research)" },
    @{ Url = "http://www.iam-68130677.com/edit/portal";      Expected = "404"; Label = "security isolation (www /edit blocked)" }
)

$allPassed = $true
$httpLines = @()
Write-Host "--- HTTP Endpoint Verification ---"
foreach ($c in $checks) {
    $actual = & curl.exe -s -o NUL -w "%{http_code}" --max-time 5 $c.Url 2>$null
    if (-not $actual) { $actual = "ERR" }
    $ok = ($actual -eq $c.Expected)
    if (-not $ok) { $allPassed = $false }
    $tag = if ($ok) { "PASS" } else { "FAIL" }
    $line = "[$tag] HTTP $actual (expected $($c.Expected))  $($c.Url)  -- $($c.Label)"
    $httpLines += $line
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host $line -ForegroundColor $color
}

$logContent = @"
=== Verification Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ===

--- kubectl get nodes -o wide ---
$nodesOut
--- kubectl get all,pvc,ingress -n $Namespace -o wide ---
$getOut
--- HTTP Endpoint Verification ---
$($httpLines -join "`r`n")

--- kubectl describe ingress -n $Namespace ---
$descOut
"@
Set-Content -LiteralPath $LogFile -Value $logContent -Encoding UTF8 -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Saved full verification output to: $LogFile" -ForegroundColor DarkGray

if (-not $allPassed) {
    Fail "One or more HTTP checks failed. Inspect $LogFile."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " 3-NODE K8S CLUSTER DEPLOYED AND VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host " Test URLs:" -ForegroundColor Green
Write-Host "   http://www.iam-68130677.com"
Write-Host "   http://www.id-68130677.com"
Write-Host "   http://www.iam-68130677.com/research"
Write-Host "   http://www.iam-68130677.com/api-68130677/Hello"
Write-Host "   http://admin.iam-68130677.com"
Write-Host "============================================================" -ForegroundColor Green
exit 0

