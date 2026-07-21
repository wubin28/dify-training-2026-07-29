#!/usr/bin/env pwsh
# dify-down.ps1 —— 停 Dify 演示环境（Windows 11 + Docker Desktop）
#
# 与 ../macos-zsh/dify-down.sh 逻辑等价。
#
# 用法：
#   ./dify-down.ps1                      # 停容器，数据保留
#   ./dify-down.ps1 -Purge               # 停容器 + 删数据卷（下次是全新实例）
#   ./dify-down.ps1 -Restore <快照名>    # 停服务 → 恢复快照 → 重起

[CmdletBinding()]
param(
    [switch]$Purge,
    [string]$Restore = "",
    [string]$DifyHome = ""
)

$ErrorActionPreference = 'Stop'

if (-not $DifyHome) { $DifyHome = if ($env:DIFY_HOME) { $env:DIFY_HOME } else { Join-Path $env:USERPROFILE "dify-demo" } }
$scriptDir   = $PSScriptRoot
$composeFile = Join-Path $DifyHome "docker\docker-compose.yaml"

if (-not (Test-Path -PathType Leaf $composeFile)) { Write-Error "找不到 compose 文件: $composeFile"; exit 1 }

if ($Restore) {
    $snapDir = Join-Path $scriptDir "..\dify-snapshots\$Restore"
    $sql = Join-Path $snapDir "dify.sql"
    if (-not (Test-Path -PathType Leaf $sql)) { Write-Error "快照不存在: $sql"; exit 1 }
    Write-Host "=== 恢复快照: $Restore ==="
    docker compose -f $composeFile up -d db
    Start-Sleep -Seconds 8
    docker compose -f $composeFile exec -T db psql -U postgres -c 'DROP DATABASE IF EXISTS dify;' | Out-Null
    docker compose -f $composeFile exec -T db psql -U postgres -c 'CREATE DATABASE dify;' | Out-Null
    Get-Content $sql | docker compose -f $composeFile exec -T db psql -U postgres dify | Out-Null
    Write-Host "  数据库已恢复"
    docker compose -f $composeFile up -d
    Write-Host "  服务已重起 → http://localhost"
    exit 0
}

if ($Purge) {
    Write-Host "!! -Purge 会删掉 Dify 的所有数据卷：应用、知识库、审计日志全没。"
    Write-Host "   你在第 2 章建的演示知识库也会没。确定？输 yes 继续："
    $confirm = Read-Host
    if ($confirm -ne "yes") { Write-Host "已取消"; exit 0 }
    docker compose -f $composeFile down -v
    Write-Host "已停止并清空数据卷"
} else {
    docker compose -f $composeFile down
    Write-Host "已停止（数据保留，下次 ./dify-up.ps1 直接回来）"
}
