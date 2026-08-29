param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

# Source: AI-generated QA asset, reviewed through execution evidence.
# Goal: verify the platform deployment entrypoints without contacting a K8s cluster.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:AssertionCount = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:AssertionCount++
}

function Assert-Contains([string]$Text, [string]$Expected, [string]$Message) {
    Assert-True ($Text.Contains($Expected)) $Message
}

function Assert-NotContains([string]$Text, [string]$Unexpected, [string]$Message) {
    Assert-True (-not $Text.Contains($Unexpected)) $Message
}

function Get-ReleaseMarker([string]$Release) {
    return "[DRY-RUN] helm upgrade --install $Release "
}

function Assert-HasRelease([string]$Output, [string]$Release) {
    Assert-Contains $Output (Get-ReleaseMarker $Release) "missing Helm release '$Release'"
}

function Assert-LacksRelease([string]$Output, [string]$Release) {
    Assert-NotContains $Output (Get-ReleaseMarker $Release) "unexpected Helm release '$Release'"
}

function Get-ReleaseCount([string]$Output) {
    return [regex]::Matches($Output, '\[DRY-RUN\] helm upgrade --install ').Count
}

function Invoke-BashRoutingTests {
    $gitExe = (Get-Command git -ErrorAction Stop).Source
    $gitRoot = Split-Path (Split-Path $gitExe -Parent) -Parent
    $bashExe = Join-Path $gitRoot "bin\bash.exe"
    Assert-True (Test-Path -LiteralPath $bashExe) "Git for Windows Bash is unavailable"

    $test = @'
set -euo pipefail
helm() { :; }
kubectl() { echo "kubectl was called during dry-run: $*" >&2; return 97; }
export -f helm kubectl

has_release() { grep -q "helm upgrade --install $2 " <<<"$1"; }
lacks_release() { ! grep -q "helm upgrade --install $2 " <<<"$1"; }
release_count() { grep -c "\[DRY-RUN\] helm upgrade --install " <<<"$1"; }

platform=$(DRY_RUN=1 ./deploy-registry-stack.sh --platform-all)
for release in minio etcd openbao loki alloy velero renovate; do has_release "$platform" "$release"; done
for release in mysql apisix shenyu; do lacks_release "$platform" "$release"; done
[ "$(release_count "$platform")" -eq 7 ]

etcd=$(DRY_RUN=1 ./deploy-registry-stack.sh --etcd)
has_release "$etcd" etcd
[ "$(release_count "$etcd")" -eq 1 ]

openbao=$(DRY_RUN=1 ./deploy-registry-stack.sh --openbao)
has_release "$openbao" openbao
[ "$(release_count "$openbao")" -eq 1 ]

loki=$(DRY_RUN=1 ./deploy-registry-stack.sh --loki)
for release in minio loki alloy; do has_release "$loki" "$release"; done
[ "$(release_count "$loki")" -eq 3 ]

velero=$(DRY_RUN=1 ./deploy-registry-stack.sh --velero)
for release in minio velero; do has_release "$velero" "$release"; done
[ "$(release_count "$velero")" -eq 2 ]

renovate=$(DRY_RUN=1 ./deploy-registry-stack.sh --renovate)
has_release "$renovate" renovate
[ "$(release_count "$renovate")" -eq 1 ]

all=$(DRY_RUN=1 ./deploy-registry-stack.sh --all)
has_release "$all" apisix
for release in etcd openbao loki alloy velero renovate; do lacks_release "$all" "$release"; done

help=$(./deploy-registry-stack.sh --help)
for flag in --etcd --openbao --loki --velero --renovate --platform-all; do grep -q -- "$flag" <<<"$help"; done
'@

    & $bashExe -n "deploy-registry-stack.sh"
    Assert-True ($LASTEXITCODE -eq 0) "Bash syntax check failed"
    & $bashExe -lc $test
    Assert-True ($LASTEXITCODE -eq 0) "Bash dry-run routing failed"
}

function Invoke-PowerShellRoutingTests {
    $deploy = Join-Path $RepoRoot "deploy-registry-stack.ps1"
    $pwsh = (Get-Process -Id $PID).Path
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "PowerShell syntax check failed"

    & {
        function Invoke-DryRun([string]$SwitchName) {
            $command = @"
function helm { `$global:LASTEXITCODE = 0 }
function kubectl { throw 'kubectl was called during dry-run' }
& '$deploy' -DryRun -$SwitchName
"@
            $output = & $pwsh -NoProfile -NonInteractive -Command $command 2>&1
            if ($LASTEXITCODE -ne 0) { throw "PowerShell dry-run failed for -${SwitchName}: $($output -join [Environment]::NewLine)" }
            return ($output -join [Environment]::NewLine)
        }

        $platform = Invoke-DryRun "PlatformAll"
        @("minio", "etcd", "openbao", "loki", "alloy", "velero", "renovate") |
            ForEach-Object { Assert-HasRelease $platform $_ }
        @("mysql", "apisix", "shenyu") | ForEach-Object { Assert-LacksRelease $platform $_ }
        Assert-True ((Get-ReleaseCount $platform) -eq 7) "-PlatformAll expanded to an unexpected release set"

        $etcd = Invoke-DryRun "Etcd"
        Assert-HasRelease $etcd "etcd"
        Assert-True ((Get-ReleaseCount $etcd) -eq 1) "-Etcd should deploy exactly one release"

        $openbao = Invoke-DryRun "OpenBao"
        Assert-HasRelease $openbao "openbao"
        Assert-True ((Get-ReleaseCount $openbao) -eq 1) "-OpenBao should deploy exactly one release"

        $loki = Invoke-DryRun "Loki"
        @("minio", "loki", "alloy") | ForEach-Object { Assert-HasRelease $loki $_ }
        Assert-True ((Get-ReleaseCount $loki) -eq 3) "-Loki dependency expansion is incorrect"

        $velero = Invoke-DryRun "Velero"
        @("minio", "velero") | ForEach-Object { Assert-HasRelease $velero $_ }
        Assert-True ((Get-ReleaseCount $velero) -eq 2) "-Velero dependency expansion is incorrect"

        $renovate = Invoke-DryRun "Renovate"
        Assert-HasRelease $renovate "renovate"
        Assert-True ((Get-ReleaseCount $renovate) -eq 1) "-Renovate should deploy exactly one release"

        $all = Invoke-DryRun "WithAll"
        Assert-HasRelease $all "apisix"
        @("etcd", "openbao", "loki", "alloy", "velero", "renovate") |
            ForEach-Object { Assert-LacksRelease $all $_ }
    }
}

function Add-IsolatedHelmRepository([string]$Name, [string]$Url) {
    & helm repo add $Name $Url --force-update 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to add Helm repository '$Name'" }
}

function Invoke-HelmTemplate([string]$Release, [string]$Chart, [string]$ValuesFile) {
    $output = & helm template $Release $Chart --namespace registry-stack --values $ValuesFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "helm template failed for ${Release}: $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine)
}

function Get-ManifestDocuments([string]$Yaml) {
    return @($Yaml -split '(?m)^---\s*$')
}

function Get-ManifestDocument([string]$Yaml, [string]$Kind, [string]$Name) {
    foreach ($document in (Get-ManifestDocuments $Yaml)) {
        $kindMatch = [regex]::Match($document, '(?m)^kind:\s*([^\s]+)')
        $nameMatch = [regex]::Match($document, '(?ms)^metadata:\s*\r?\n.*?^\s{2}name:\s*([^\r\n]+)')
        if (-not $kindMatch.Success -or -not $nameMatch.Success) { continue }
        $documentKind = $kindMatch.Groups[1].Value.Trim('"', "'")
        $documentName = $nameMatch.Groups[1].Value.Trim().Trim('"', "'")
        if ($documentKind -eq $Kind -and $documentName -eq $Name) { return $document }
    }
    throw "Manifest not found: $Kind/$Name"
}

function Assert-Workload([string]$Yaml, [string]$Kind, [string]$Name, [int]$Replicas, [bool]$HardAntiAffinity) {
    $document = Get-ManifestDocument $Yaml $Kind $Name
    Assert-True ([regex]::IsMatch($document, "(?m)^  replicas:\s*$Replicas\s*$")) "$Kind/$Name replicas != $Replicas"
    if ($HardAntiAffinity) {
        Assert-Contains $document "requiredDuringSchedulingIgnoredDuringExecution:" "$Kind/$Name lacks hard anti-affinity"
    }
}

function Invoke-HelmRenderingTests {
    $helm = Get-Command helm -ErrorAction Stop
    Assert-True ([bool]$helm) "Helm is unavailable"

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $qaCache = Join-Path $tempRoot ("beggar-qa-helm-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $qaCache)
    $env:HELM_REPOSITORY_CONFIG = Join-Path $qaCache "repositories.yaml"
    $env:HELM_REPOSITORY_CACHE = Join-Path $qaCache "repository"

    Add-IsolatedHelmRepository "openbao" "https://openbao.github.io/openbao-helm"
    Add-IsolatedHelmRepository "grafana-community" "https://grafana-community.github.io/helm-charts"
    Add-IsolatedHelmRepository "grafana" "https://grafana.github.io/helm-charts"
    Add-IsolatedHelmRepository "vmware-tanzu" "https://vmware-tanzu.github.io/helm-charts"

    $config = Join-Path $RepoRoot "config"
    $etcd = Invoke-HelmTemplate "etcd" "oci://registry-1.docker.io/bitnamicharts/etcd" (Join-Path $config "etcd-values.yaml")
    $minio = Invoke-HelmTemplate "minio" "oci://registry-1.docker.io/bitnamicharts/minio" (Join-Path $config "minio-values.yaml")
    $openbao = Invoke-HelmTemplate "openbao" "openbao/openbao" (Join-Path $config "openbao-values.yaml")
    $loki = Invoke-HelmTemplate "loki" "grafana-community/loki" (Join-Path $config "loki-values.yaml")
    $alloy = Invoke-HelmTemplate "alloy" "grafana/alloy" (Join-Path $config "alloy-values.yaml")
    $velero = Invoke-HelmTemplate "velero" "vmware-tanzu/velero" (Join-Path $config "velero-values.yaml")
    $renovate = Invoke-HelmTemplate "renovate" "oci://ghcr.io/renovatebot/charts/renovate" (Join-Path $config "renovate-values.yaml")

    Assert-Workload $etcd "StatefulSet" "etcd" 3 $true
    Assert-Contains (Get-ManifestDocument $etcd "PodDisruptionBudget" "etcd") "minAvailable: 2" "etcd PDB does not preserve quorum"

    Assert-Contains $minio "loki-chunks" "MinIO does not provision the Loki chunks bucket"
    Assert-Contains $minio "loki-ruler" "MinIO does not provision the Loki ruler bucket"
    Assert-Contains $minio "loki-admin" "MinIO does not provision the Loki admin bucket"
    Assert-Contains $minio "velero" "MinIO does not provision the Velero bucket"

    Assert-Workload $openbao "StatefulSet" "openbao" 3 $true
    Assert-Contains (Get-ManifestDocument $openbao "PodDisruptionBudget" "openbao") "maxUnavailable: 1" "OpenBao PDB is incorrect"
    Assert-Contains $openbao 'storage "raft"' "OpenBao does not use Raft storage"
    Assert-Contains $openbao "sealedcode=204&uninitcode=204" "OpenBao readiness blocks safe manual initialization"

    Assert-Workload $loki "Deployment" "loki-gateway" 2 $true
    Assert-Workload $loki "Deployment" "loki-read" 3 $true
    Assert-Workload $loki "StatefulSet" "loki-write" 3 $true
    Assert-Workload $loki "StatefulSet" "loki-backend" 3 $true
    foreach ($pdb in @("loki-gateway", "loki-read", "loki-write", "loki-backend")) {
        [void](Get-ManifestDocument $loki "PodDisruptionBudget" $pdb)
        $script:AssertionCount++
    }
    Assert-Contains $loki "endpoint: http://minio:9000" "Loki does not target MinIO/S3"

    Assert-Workload $alloy "Deployment" "alloy" 2 $true
    Assert-Contains (Get-ManifestDocument $alloy "PodDisruptionBudget" "alloy") "minAvailable: 1" "Alloy PDB is incorrect"
    Assert-Contains $alloy "clustering {" "Alloy target sharding is missing"
    Assert-Contains $alloy "http://loki-gateway/loki/api/v1/push" "Alloy does not forward to Loki"

    Assert-Workload $velero "Deployment" "velero" 1 $false
    [void](Get-ManifestDocument $velero "DaemonSet" "node-agent")
    $script:AssertionCount++
    Assert-Contains $velero "--default-volumes-to-fs-backup" "Velero filesystem backup is not enabled"
    Assert-Contains $velero 's3Url: "http://minio:9000"' "Velero does not target MinIO/S3"
    $scheduleCount = @((Get-ManifestDocuments $velero) | Where-Object { $_ -match '(?m)^kind:\s*Schedule\s*$' }).Count
    Assert-True ($scheduleCount -eq 0) "Velero installation unexpectedly creates a backup schedule"

    $renovateCron = Get-ManifestDocument $renovate "CronJob" "renovate"
    Assert-Contains $renovateCron "suspend: true" "Renovate CronJob must be suspended by default"
    Assert-Contains $renovateCron "name: renovate-credentials" "Renovate credential Secret reference is missing"
    Assert-Contains $renovateCron "optional: true" "Renovate installation should tolerate an absent credential Secret while suspended"
}

Push-Location $RepoRoot
try {
    Invoke-BashRoutingTests
    Invoke-PowerShellRoutingTests
    Invoke-HelmRenderingTests
    & git diff --check
    Assert-True ($LASTEXITCODE -eq 0) "git diff --check failed"
    Write-Output "QA PASS assertions=$script:AssertionCount"
} finally {
    Pop-Location
}
