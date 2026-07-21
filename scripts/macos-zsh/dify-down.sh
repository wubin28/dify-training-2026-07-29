#!/usr/bin/env zsh
# dify-down.sh —— 停 Dify 演示环境
#
# 用法：
#   ./dify-down.sh            # 停容器，数据保留
#   ./dify-down.sh --purge    # 停容器 + 删数据卷（下次是全新实例）
#   ./dify-down.sh --restore <快照名>   # 停服务 → 恢复快照 → 重起
#
# ⚠️ 版本一致性：--restore 用 pg_dump 逻辑还原，只在**同版本**内安全。
#   1.14.2 时期打的快照别往 1.11.2 上还原（schema 不通用，会脏库或起不来）。
#   降级到 1.11.2 后，请重新用 dify-up.sh --snapshot 打新的 1.11.2 快照。

set -euo pipefail

SCRIPT_DIR=${0:A:h}
DIFY_HOME="${DIFY_HOME:-$HOME/dify-demo}"
COMPOSE="$DIFY_HOME/docker/docker-compose.yaml"
# 跟 dify-up.sh 用同一 project 名，否则 down 找不到 up 起的容器
DIFY_PROJECT="${DIFY_PROJECT:-dify-demo}"
PURGE=0
RESTORE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)   PURGE=1; shift ;;
    --restore) RESTORE="$2"; shift 2 ;;
    --home)    DIFY_HOME="$2"; COMPOSE="$2/docker/docker-compose.yaml"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done

[[ ! -f "$COMPOSE" ]] && { print -u2 "找不到 compose 文件: $COMPOSE"; exit 1; }

if [[ -n "$RESTORE" ]]; then
  SNAP_DIR="$SCRIPT_DIR/../dify-snapshots/$RESTORE"
  [[ ! -f "$SNAP_DIR/dify.sql" ]] && { print -u2 "快照不存在: $SNAP_DIR/dify.sql"; exit 1; }
  print "=== 恢复快照: $RESTORE ==="
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" up -d db
  sleep 8
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" exec -T db psql -U postgres -c 'DROP DATABASE IF EXISTS dify;' >/dev/null
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" exec -T db psql -U postgres -c 'CREATE DATABASE dify;' >/dev/null
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" exec -T db psql -U postgres dify < "$SNAP_DIR/dify.sql" >/dev/null
  print "  数据库已恢复"
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" up -d
  print "  服务已重起 → http://localhost"
  exit 0
fi

if [[ $PURGE -eq 1 ]]; then
  print "!! --purge 会删掉 Dify 的所有数据卷：应用、知识库、审计日志全没。"
  print "   你在第 2 章建的演示知识库也会没。确定？输 yes 继续："
  read -r confirm
  [[ "$confirm" != "yes" ]] && { print "已取消"; exit 0; }
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" down -v --remove-orphans
  print "已停止并清空数据卷"
else
  docker compose -p "$DIFY_PROJECT" -f "$COMPOSE" down --remove-orphans
  print "已停止（数据保留，下次 ./dify-up.sh 直接回来）"
fi