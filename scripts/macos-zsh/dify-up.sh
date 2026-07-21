#!/usr/bin/env zsh
# dify-up.sh —— Dify 私有化演示环境起服务（macOS + Docker Desktop）
#
# 用途：第 2 章（起得来、能演示知识库）、第 4 章（演版本控制/审计日志/RBAC）。
#
# 定位说明：这套环境是**讲师侧演示用**。学员在 Windows 11 上不部署 Dify ——
# 大纲里 Dify 是「讲授 + 演示」，不是学员动手环节。你在 macOS 上起一份，
# 投屏给他们看「课堂做的东西，院里怎么正式用起来」。
#
# 依赖：Docker Desktop for Mac（跑起来，且分配 ≥ 8GB 内存）、git
#
# 用法：
#   ./dify-up.sh                    # 克隆 + 起服务 + 健康检查
#   ./dify-up.sh --snapshot before-versioning-demo   # 起服务前先打快照
#   ./dify-down.sh                  # 停服务
#
# 【?Dify:版本】钉 v1.11.2 —— 与学员院内版本对齐（讲师本地降级后一致，避免 UI 对不上）。
#   注意：1.11.2 的 docker/.env.example 是单文件结构（1.14.1+ 才把 env 拆进
#   docker/envs/**）。本脚本用 cp .env.example .env，两版都适用，无需改。
#   若要临时切回 1.14.2 备课，加 --version 1.14.2 即可（但两版数据卷 schema 不通用，
#   切版本前先 dify-down.sh --purge 清卷，别指望原地降级）。

set -euo pipefail

SCRIPT_DIR=${0:A:h}
DIFY_HOME="${DIFY_HOME:-$HOME/dify-demo}"
DIFY_VERSION="${DIFY_VERSION:-1.11.2}"
SNAPSHOT=""
# 固定 project 名，避免跟同名目录（如 README 里另一个 dify/docker）的 stack 撞成一个 project
DIFY_PROJECT="${DIFY_PROJECT:-dify-demo}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    --home)     DIFY_HOME="$2"; shift 2 ;;
    --version)  DIFY_VERSION="$2"; shift 2 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done

command -v docker >/dev/null || { print -u2 "没装 Docker。装 Docker Desktop for Mac。"; exit 1; }
docker info >/dev/null 2>&1 || { print -u2 "Docker 没跑起来。先打开 Docker Desktop。"; exit 1; }
docker compose version >/dev/null 2>&1 || { print -u2 "缺 docker compose v2 插件。"; exit 1; }

# 内存预检：Dify 全家桶（api/worker/web/db/redis/weaviate/nginx/sandbox）8GB 以下必卡
MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
MEM_GB=$(( MEM_BYTES / 1024 / 1024 / 1024 ))
if [[ $MEM_GB -lt 7 ]]; then
  print -u2 "!! Docker 只分到 ${MEM_GB}GB 内存。Dify 全套建议 ≥8GB。"
  print -u2 "   改：Docker Desktop → Settings → Resources → Memory"
  print -u2 "   现在继续会起得来但演示时卡顿明显。3 秒后继续，Ctrl-C 中止。"
  sleep 3
fi

print "=== 1/5 获取 Dify v$DIFY_VERSION ==="
if [[ -d "$DIFY_HOME/.git" ]]; then
  print "  已存在: $DIFY_HOME"
  # 已克隆过就无需强拉。fetch 只为刷新 tag，网络/代理抖动时常 early EOF；
  # 失败不致命——本地已有 tag，加 || true 避免 set -e 把整轮跑挂掉。
  git -C "$DIFY_HOME" fetch --tags --quiet 2>/dev/null \
    || print -u2 "  !! fetch 失败（网络/代理抖动），沿用本地已有的 tag"
  git -C "$DIFY_HOME" checkout "$DIFY_VERSION" --quiet 2>/dev/null \
    || print -u2 "  !! 切不到 tag $DIFY_VERSION，沿用当前分支"
else
  git clone --depth 1 --branch "$DIFY_VERSION" https://github.com/langgenius/dify.git "$DIFY_HOME" \
    || { print -u2 "克隆失败。检查网络，或换版本：--version <tag>"; exit 1; }
  print "  克隆完成: $DIFY_HOME"
fi

COMPOSE_DIR="$DIFY_HOME/docker"
[[ ! -d "$COMPOSE_DIR" ]] && { print -u2 "找不到 docker 目录，仓库结构可能变了。【?Dify:compose路径】"; exit 1; }

print "=== 2/5 配置 .env ==="
if [[ ! -f "$COMPOSE_DIR/.env" ]]; then
  cp "$COMPOSE_DIR/.env.example" "$COMPOSE_DIR/.env"
  print "  从 .env.example 生成"
else
  print "  已存在，不覆盖（要重置就先删 $COMPOSE_DIR/.env）"
fi

print "=== 3/5 快照 ==="
if [[ -n "$SNAPSHOT" ]]; then
  SNAP_DIR="$SCRIPT_DIR/../dify-snapshots/$SNAPSHOT"
  mkdir -p "$SNAP_DIR"
  if docker compose -p "$DIFY_PROJECT" -f "$COMPOSE_DIR/docker-compose.yaml" ps -q db 2>/dev/null | grep -q .; then
    print "  导出数据库 → $SNAP_DIR/dify.sql"
    docker compose -p "$DIFY_PROJECT" -f "$COMPOSE_DIR/docker-compose.yaml" exec -T db \
      pg_dump -U postgres dify > "$SNAP_DIR/dify.sql" 2>/dev/null \
      && print "  ok" || print -u2 "  !! 导出失败（服务没起？）"
  else
    print "  服务未运行，跳过导出"
  fi
  cp "$COMPOSE_DIR/.env" "$SNAP_DIR/.env.bak" 2>/dev/null || true
  print "  快照位置: $SNAP_DIR"
  print "  （第 4 章演版本控制/回滚前先打快照，演砸了能回来）"
else
  print "  跳过（要打快照加 --snapshot <名字>）"
fi

print "=== 4/5 起服务 ==="
cd "$COMPOSE_DIR"
docker compose -p "$DIFY_PROJECT" up -d
print "  容器已拉起"

print "=== 5/5 健康检查 ==="
URL="http://localhost/apps"
# --noproxy '*'：本机装了 ClashX/V2Ray 等代理时，ALL_PROXY/HTTP_PROXY 会把 localhost
# 也走 SOCKS 代理，代理一挂 curl 就 000（Dify 其实好好的）。强制直连绕开代理。
for i in {1..40}; do
  code=$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 5 "$URL" 2>/dev/null || echo 000)
  if [[ "$code" =~ ^(200|302|307)$ ]]; then
    print "  就绪（HTTP $code，等了 $((i*5)) 秒）"
    print ""
    print "访问: http://localhost"
    print "首次打开会让你建管理员账号 —— 备课时建两个账号，"
    print "第 4 章演 RBAC 要用（一个 owner、一个 normal member）。"
    print ""
    print "日志: docker compose -p $DIFY_PROJECT -f $COMPOSE_DIR/docker-compose.yaml logs -f api"
    print "停服: $SCRIPT_DIR/dify-down.sh"
    exit 0
  fi
  [[ $((i % 4)) -eq 0 ]] && print "  等待中… ($((i*5))s, 最近 HTTP $code)"
  sleep 5
done

print -u2 ""
print -u2 "!! 200 秒没起来。排查："
print -u2 "   docker compose -p $DIFY_PROJECT -f $COMPOSE_DIR/docker-compose.yaml ps"
print -u2 "   docker compose -p $DIFY_PROJECT -f $COMPOSE_DIR/docker-compose.yaml logs api | tail -50"
print -u2 "   常见原因：80 端口被占（改 .env 的 EXPOSE_NGINX_PORT）；镜像拉取超时；内存不足被 OOM kill"
print -u2 "   project 名撞车（两个 docker 目录缝成一个 project）：docker compose ls 若见一个 project 关联多份 compose 文件，就是它"
exit 1