#!/usr/bin/env bash
set -euo pipefail

# Draw.io MCP App Server 自动部署脚本
# 功能：拉取最新代码、识别系统架构、清理旧容器/镜像、构建并启动新容器

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="drawio-mcp"
COMPOSE_FILE=""
IMAGE_TAG=""

# 检测 docker compose 版本（优先使用 v2 插件）
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "错误：未找到 docker compose 或 docker-compose，请先安装 Docker"
    exit 1
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()
{
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok()
{
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. 拉取最新代码
pull_code()
{
    log_info "拉取最新代码..."
    cd "$SCRIPT_DIR"
    if [ -d ".git" ]; then
        git pull --ff-only
        log_ok "代码已更新到最新"
    elif [ -d "../.git" ]; then
        cd ".."
        git pull --ff-only
        log_ok "代码已更新到最新"
    else
        log_warn "当前目录不是 git 仓库，跳过拉取"
    fi
}

# 2. 识别系统架构
detect_arch()
{
    log_info "检测系统架构..."
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            COMPOSE_FILE="docker-compose.amd64.yml"
            IMAGE_TAG="drawio-mcp:amd64-latest"
            log_ok "检测到架构: amd64 ($arch)"
            ;;
        aarch64|arm64|armv8l)
            COMPOSE_FILE="docker-compose.arm64.yml"
            IMAGE_TAG="drawio-mcp:arm64-latest"
            log_ok "检测到架构: arm64 ($arch)"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    if [ ! -f "$SCRIPT_DIR/$COMPOSE_FILE" ]; then
        log_error "Compose 文件不存在: $COMPOSE_FILE"
        exit 1
    fi
}

# 3. 清理旧容器和镜像
cleanup_old()
{
    log_info "清理旧容器和镜像..."
    cd "$SCRIPT_DIR"

    # 获取当前运行的容器名称（根据 compose 文件推断）
    local container_name
    container_name=$(grep -E '^\s+container_name:' "$COMPOSE_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'")

    # 停止并删除由该 compose 文件管理的容器
    if $COMPOSE_CMD -f "$COMPOSE_FILE" ps -q 2>/dev/null | grep -q .; then
        log_info "停止并移除旧容器..."
        $COMPOSE_CMD -f "$COMPOSE_FILE" down --remove-orphans
        log_ok "旧容器已清理"
    else
        log_warn "没有运行中的旧容器"
    fi

    # 删除旧镜像（仅删除当前项目的镜像）
    if docker images "$IMAGE_TAG" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_TAG"; then
        log_info "删除旧镜像: $IMAGE_TAG ..."
        docker rmi -f "$IMAGE_TAG"
        log_ok "旧镜像已删除"
    else
        log_warn "未找到旧镜像: $IMAGE_TAG"
    fi

    # 清理悬空镜像（可选，默认不执行）
    if [ "${PRUNE_DANGLING:-false}" = "true" ]; then
        log_info "清理悬空镜像..."
        docker image prune -f
    fi
}

# 4. 构建并启动新容器
build_and_run()
{
    log_info "构建并启动新容器..."
    cd "$SCRIPT_DIR"

    $COMPOSE_CMD -f "$COMPOSE_FILE" up --build -d

    log_ok "容器已启动"
    log_info "等待服务初始化..."
    sleep 3

    # 健康检查
    local port
    port=$(grep -E '^\s+- "[0-9]+:3000"' "$COMPOSE_FILE" | grep -oP '\d+(?=:3000)')
    if [ -n "$port" ]; then
        if curl -sf "http://127.0.0.1:$port/mcp" -o /dev/null || \
           curl -si "http://127.0.0.1:$port/mcp" 2>/dev/null | grep -q "405"; then
            log_ok "服务健康检查通过 (port: $port)"
        else
            log_warn "服务可能尚未就绪，请稍后检查"
        fi
    fi
}

# 5. 显示状态
show_status()
{
    log_info "部署状态："
    echo ""
    echo "--- 运行中的容器 ---"
    docker ps --filter "ancestor=$IMAGE_TAG" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "--- 镜像信息 ---"
    docker images "$IMAGE_TAG" --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}"
    echo ""

    local port
    port=$(grep -E '^\s+- "[0-9]+:3000"' "$COMPOSE_FILE" | grep -oP '\d+(?=:3000)')
    echo "访问地址: http://<服务器IP>:$port/mcp"
}

# 主流程
main()
{
    echo "=========================================="
    echo " Draw.io MCP App Server 自动部署脚本"
    echo "=========================================="
    echo ""

    pull_code
    echo ""
    detect_arch
    echo ""
    cleanup_old
    echo ""
    build_and_run
    echo ""
    show_status

    echo ""
    echo "=========================================="
    log_ok "部署完成"
    echo "=========================================="
}

# 用法说明
usage()
{
    cat <<EOF
用法: $0 [选项]

选项:
    -p, --prune     同时清理悬空镜像 (docker image prune)
    -h, --help      显示此帮助信息

环境变量:
    PRUNE_DANGLING=true   启用悬空镜像清理

示例:
    $0              # 标准部署
    $0 --prune      # 部署并清理悬空镜像
    PRUNE_DANGLING=true $0

EOF
}

# 解析参数
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--prune)
            export PRUNE_DANGLING=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

main "$@"
