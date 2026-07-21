#!/usr/bin/env pwsh
# dify-up.ps1 —— Dify 私有化演示环境起服务（Windows 11 + Docker Desktop）
#
# 与 ../macos-zsh/dify-up.sh 逻辑等价。用途：第 2 章（起得来、能演示知识库）、
# 第 4 章（演版本控制/审计日志/RBAC）。
#
# 定位说明：这套环境是**讲师/助教侧演示用**。学员不部署 Dify —— 大纲里 Dify 是
# 「讲授 + 演示」，不是学员动手环节。在一台机器上起一份投屏给学员看。
#
# 依赖：Docker Desktop for Windows（跑起来，且分配 ≥ 8GB 内存）、git
#
# 用法：
#   ./dify-up.ps1                                   # 克隆 + 起服务 + 健康检查
#   ./dify-up.ps1 -Snapshot before-versioning-demo  # 起服务前先打快照
#   ./dify-down.ps1                                 # 停服务

[CmdletBinding()]
param(
    [string]$Snapshot = "",
    [string]$DifyHome = "",
    [string]$Version  = ""
)

$ErrorActionPreference = 'Stop'

if (-not $DifyHome) { $DifyHome = if ($env:DIFY_HOME) { $env:DIFY_HOME } else { Join-Path $env:USERPROFILE "dify-demo" } }
if (-not $Version)  { $Version  = if ($env:DIFY_VERSION) { $env:DIFY_VERSION } else { "1.14.2" } }
$scriptDir = $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Error "没装 Docker。装 Docker Desktop for Windows。"; exit 1 }
try { docker info *> $null } catch { Write-Error "Docker 没跑起来。先打开 Docker Desktop。"; exit 1 }
try { docker compose version *> $null } catch { Write-Error "缺 docker compose v2 插件。"; exit 1 }

# 内存预检：Dify 全家桶（api/worker/web/db/redis/weaviate/nginx/sandbox）8GB 以下必卡
$memBytes = [int64](docker info --format '{{.MemTotal}}' 2>$null)
$memGB = [math]::Floor($memBytes / 1GB)
if ($memGB -lt 7) {
    Write-Warning "!! Docker 只分到 ${memGB}GB 内存。Dify 全套建议 ≥8GB。"
    Write-Warning "   改：Docker Desktop → Settings → Resources → Memory"
    Write-Warning "   现在继续会起得来但演示时卡顿明显。3 秒后继续，Ctrl-C 中止。"
    Start-Sleep -Seconds 3
}

Write-Host "=== 1/5 获取 Dify v$Version ==="
if (Test-Path (Join-Path $DifyHome ".git")) {
    Write-Host "  已存在: $DifyHome"
    git -C $DifyHome fetch --tags --quiet
    git -C $DifyHome checkout $Version --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warning "  !! 切不到 tag $Version，沿用当前分支" }
} else {
    git clone --depth 1 --branch $Version https://github.com/langgenius/dify.git $DifyHome
    if ($LASTEXITCODE -ne 0) { Write-Error "克隆失败。检查网络，或换版本：-Version <tag>"; exit 1 }
    Write-Host "  克隆完成: $DifyHome"
}

$composeDir = Join-Path $DifyHome "docker"
if (-not (Test-Path -PathType Container $composeDir)) { Write-Error "找不到 docker 目录，仓库结构可能变了。【?Dify:compose路径】"; exit 1 }
$composeFile = Join-Path $composeDir "docker-compose.yaml"

Write-Host "=== 2/5 配置 .env ==="
$envFile = Join-Path $composeDir ".env"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $composeDir ".env.example") $envFile
    Write-Host "  从 .env.example 生成"
} else {
    Write-Host "  已存在，不覆盖（要重置就先删 $envFile）"
}

Write-Host "=== 3/5 快照 ==="
if ($Snapshot) {
    $snapDir = Join-Path $scriptDir "..\dify-snapshots\$Snapshot"
    New-Item -ItemType Directory -Force -Path $snapDir | Out-Null
    $dbRunning = docker compose -f $composeFile ps -q db 2>$null
    if ($dbRunning) {
        Write-Host "  导出数据库 → $snapDir\dify.sql"
        docker compose -f $composeFile exec -T db pg_dump -U postgres dify |
            Out-File -Encoding utf8 (Join-Path $snapDir "dify.sql")
        if ($LASTEXITCODE -eq 0) { Write-Host "  ok" } else { Write-Warning "  !! 导出失败（服务没起？）" }
    } else {
        Write-Host "  服务未运行，跳过导出"
    }
    Copy-Item $envFile (Join-Path $snapDir ".env.bak") -ErrorAction SilentlyContinue
    Write-Host "  快照位置: $snapDir"
    Write-Host "  （第 4 章演版本控制/回滚前先打快照，演砸了能回来）"
} else {
    Write-Host "  跳过（要打快照加 -Snapshot <名字>）"
}

Write-Host "=== 4/5 起服务 ==="
Push-Location $composeDir
try {
    docker compose up -d
    Write-Host "  容器已拉起"
} finally {
    Pop-Location
}

Write-Host "=== 5/5 健康检查 ==="
$url = "http://localhost/apps"
for ($i = 1; $i -le 40; $i++) {
    $code = 0
    try {
        $resp = Invoke-WebRequest -Uri $url -TimeoutSec 5 -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
        $code = [int]$resp.StatusCode
    } catch { $code = 0 }
    if ($code -in 200,302,307) {
        Write-Host "  就绪（HTTP $code，等了 $($i*5) 秒）"
        Write-Host ""
        Write-Host "访问: http://localhost"
        Write-Host "首次打开会让你建管理员账号 —— 备课时建两个账号，"
        Write-Host "第 4 章演 RBAC 要用（一个 owner、一个 normal member）。"
        Write-Host ""
        Write-Host "日志: docker compose -f $composeFile logs -f api"
        Write-Host "停服: $scriptDir\dify-down.ps1"
        exit 0
    }
    if ($i % 4 -eq 0) { Write-Host "  等待中… ($($i*5)s, 最近 HTTP $code)" }
    Start-Sleep -Seconds 5
}

Write-Error @"
!! 200 秒没起来。排查：
   docker compose -f $composeFile ps
   docker compose -f $composeFile logs api | Select-Object -Last 50
   常见原因：80 端口被占（改 .env 的 EXPOSE_NGINX_PORT）；镜像拉取超时；内存不足被 OOM kill
"@
exit 1
