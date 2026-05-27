# Draw.io MCP App Server Docker 部署指南

本文档提供在阿里云公网服务器上通过 Docker 容器部署 MCP App Server 的完整方案，支持 amd64 和 arm64 两种架构。

---

## 架构说明

本项目为**纯 Node.js 服务**，无 Python、apt 等额外依赖：

- 运行时仅依赖 Node.js 和 npm 包
- Alpine Linux 的 `apk` 已配置华为云国内镜像源
- npm 已配置淘宝镜像源 (`registry.npmmirror.com`)
- 如需后续扩展 Python 辅助脚本，建议使用 `uv` 进行环境管理

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `Dockerfile.amd64` | amd64 架构构建文件 |
| `Dockerfile.arm64` | arm64 架构构建文件 |
| `docker-compose.amd64.yml` | amd64 编排文件（宿主机端口 18080） |
| `docker-compose.arm64.yml` | arm64 编排文件（宿主机端口 20000） |
| `deploy.sh` | 自动部署脚本（拉代码 + 识别架构 + 清理 + 构建启动） |

---

## 快速开始

### 1. 克隆代码到阿里云服务器

```bash
git clone https://github.com/jgraph/drawio-mcp.git
cd drawio-mcp/mcp-app-server
```

### 2. 根据服务器架构选择部署方式

#### amd64 架构

```bash
docker-compose -f docker-compose.amd64.yml up --build -d
```

服务将监听：
- 容器内端口：`3000`
- 宿主机端口：`18080`
- 访问地址：`http://<服务器IP>:18080/mcp`

#### arm64 架构（阿里云 ARM 实例）

```bash
docker-compose -f docker-compose.arm64.yml up --build -d
```

服务将监听：
- 容器内端口：`3000`
- 宿主机端口：`20000`
- 访问地址：`http://<服务器IP>:20000/mcp`

### 3. 验证服务状态

```bash
# 查看容器运行状态
docker ps

# 查看服务日志
docker logs drawio-mcp-amd64   # amd64
docker logs drawio-mcp-arm64   # arm64

# 健康检查
curl -i http://localhost:18080/mcp   # amd64
curl -i http://localhost:20000/mcp  # arm64
```

预期返回 HTTP 405（MCP 协议端点，GET 请求返回 405 是正常的）。

### 4. 停止服务

```bash
docker-compose -f docker-compose.amd64.yml down
docker-compose -f docker-compose.arm64.yml down
```

---

## 公网访问配置

阿里云服务器需要在安全组中开放对应端口：

| 架构 | 安全组入方向规则 |
|------|----------------|
| amd64 | 允许 TCP 18080 |
| arm64 | 允许 TCP 20000 |

### 配置 Claude.ai 远程 MCP

如果需要通过公网让 Claude.ai 访问，建议配置 Nginx 反向代理 + HTTPS：

```nginx
server {
    listen 443 ssl http2;
    server_name drawio-mcp.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /mcp {
        proxy_pass http://localhost:18080;  # amd64 用 18080，arm64 用 20000
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

然后在 Claude.ai 设置中添加远程 MCP server URL：
```
https://drawio-mcp.yourdomain.com/mcp
```

---

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `NODE_ENV` | `production` | 运行环境 |
| `PORT` | `3000` | 容器内部监听端口 |
| `LISTEN` | `0.0.0.0` | 绑定地址（容器内必须 0.0.0.0） |
| `DRAWIO_BASE_URL` | - | 自建 draw.io 实例地址 |
| `ALLOWED_HOSTS` | - | 允许的 Host 头，逗号分隔 |

---

## 镜像源说明

### 基础镜像

| 架构 | 镜像地址 |
|------|----------|
| amd64 | `swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/node:22-alpine` |
| arm64 | `swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/node:22-alpine-linuxarm64` |

### 国内镜像源配置

**Alpine apk 源**：已配置华为云镜像 `https://repo.huaweicloud.com/alpine`

**npm 源**：已配置淘宝镜像 `https://registry.npmmirror.com`

---

## 关于 Python / uv 的说明

当前 MCP App Server 为纯 Node.js 项目，无 Python 依赖，因此 Dockerfile 中未包含 Python 和 uv 的安装。

如需后续扩展 Python 辅助功能，可在 Dockerfile 的 `RUN apk add` 步骤中加入：

```dockerfile
# 安装 Python + uv（如需）
RUN apk add --no-cache python3 py3-pip \
    && pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    && pip install uv
```

---

## 常见问题

### Q: 构建时下载依赖很慢？
A: Dockerfile 已配置国内镜像源。如仍慢，可检查服务器 DNS 是否能正常解析 `repo.huaweicloud.com` 和 `registry.npmmirror.com`。

### Q: 容器启动后无法从外部访问？
A: 确保 `LISTEN=0.0.0.0`（容器内不能监听 127.0.0.1），且阿里云安全组已放行对应端口。

### Q: arm64 构建失败？
A: 确认基础镜像标签正确。部分旧版 Docker 可能不支持 `linuxarm64` 标签，可尝试使用 `docker buildx`：

```bash
docker buildx build --platform linux/arm64 -f Dockerfile.arm64 .
```
