# hermes-agent-desktop

基于 [LinuxServer.io Baseimage KasmVNC (Debian Bookworm)](https://github.com/linuxserver/docker-baseimage-kasmvnc) + [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) + [Hermes WebUI](https://github.com/EKKOLearnAI/hermes-web-ui) 打包的一体化 Docker 镜像。

## 镜像地址

```
ghcr.io/comedy1024/hermes-agent-desktop:latest
```

## 功能特性

- 🖥️ **Linux GUI 桌面** — 通过 KasmVNC 在浏览器中访问完整 Debian KDE 桌面环境
- 🤖 **Hermes Agent** — 自演化 AI Agent 框架，支持 OpenAI / Anthropic / DeepSeek / Ollama 等
- 🌐 **Hermes WebUI** — 社区最活跃的 Hermes Agent Web 管理界面（769+ Stars）
- 🔧 **全功能管理** — Web 终端、平台频道配置（8平台）、使用分析、定时任务、模型管理
- 🔗 **Gateway API** — OpenAI 兼容 API，供 WebUI 和外部调用
- 🔒 **官方镜像基础** — 基于 LinuxServer.io 官方维护的 KasmVNC 基础镜像，多架构支持
- ☁️ **云平台友好** — KasmVNC 使用 WebSocket VNC，完美兼容 ModelScope/HuggingFace 等单端口 HTTP 反代平台

## 远程桌面方案：KasmVNC

> **为什么用 KasmVNC 而不是 Selkies？**
>
> 云平台（ModelScope 创空间、HuggingFace Spaces）只暴露单个 HTTP 端口。
> - **KasmVNC** (WebSocket VNC)：HTTP 页面 + 同端口 WebSocket 升级 → ✅ 完美兼容
> - **Selkies** (WebRTC)：需要独立 UDP/TCP 媒体流 → ❌ 无法穿透 HTTP 反向代理

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| `3000` | KasmVNC | Debian KDE 桌面（浏览器访问，HTTP） |
| `3001` | KasmVNC | Debian KDE 桌面（浏览器访问，HTTPS） |
| `8648` | Hermes WebUI | Web 管理界面（聊天/配置/运维）|
| `8642` | Hermes Gateway | OpenAI 兼容 API（WebUI 自动管理）|

> 💡 ModelScope/HuggingFace 部署时，设置 `CUSTOM_PORT=7860` 将桌面映射到云平台默认端口。

## 快速开始（本地运行）

```bash
docker run -d \
  --name hermes-agent \
  -p 3000:3000 \
  -p 3001:3001 \
  -p 8648:8648 \
  -p 8642:8642 \
  -v hermes-data:/config \
  ghcr.io/comedy1024/hermes-agent-desktop:latest
```

启动后：
1. 打开 `http://localhost:3000` — Linux KDE 桌面（KasmVNC）
2. 打开 `http://localhost:8648` — Hermes WebUI 管理界面（首次配置 LLM API Key）
3. `http://localhost:8642` — Hermes Gateway OpenAI 兼容 API

## 常用环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `CUSTOM_PORT` | KasmVNC HTTP 端口（云平台设为 7860） | `3000` |
| `CUSTOM_HTTPS_PORT` | KasmVNC HTTPS 端口 | `3001` |
| `RESOLUTION` | 桌面分辨率（云平台推荐 1024x768） | `1024x768` |
| `PASSWORD` | 桌面访问密码 | （空，无密码）|
| `OPENAI_API_KEY` | OpenAI API Key | — |
| `ANTHROPIC_API_KEY` | Anthropic API Key | — |
| `OPENROUTER_API_KEY` | OpenRouter API Key | — |
| `HERMES_HOME` | Hermes 数据目录 | `/config/hermes-data` |

> 完整配置项请参考容器内的 `/config/hermes-data/.env` 模板文件。

## 数据持久化

所有配置、记忆、技能、会话日志均保存在 `/config` 目录下：

```bash
-v hermes-data:/config
```

目录结构：
```
/config/
├── hermes-data/
│   ├── .env           # 环境配置（API Keys、模型配置）
│   ├── config.yaml    # Hermes Agent 主配置
│   ├── SOUL.md        # Agent 人格定义
│   ├── memories/      # 长期记忆
│   ├── skills/        # 技能库
│   ├── sessions/      # 会话记录
│   ├── logs/          # 运行日志
│   ├── workspace/     # 工作目录
│   └── .hermes/
│       └── webui-mvp/ # WebUI 状态与配置
└── logs/
    └── hermes-webui.log  # WebUI 服务日志
```

## 常见问题

### 如何设置桌面访问密码？

在 `docker run` 时传入 `PASSWORD` 环境变量：

```bash
docker run -d -e PASSWORD=your_password ...
```

### 配置 LLM 后报错 `Hermes runtime returned an unexpected response`

这是由于 Gateway 的用户白名单未配置导致的。编辑容器内的 `.env` 文件：

```bash
docker exec -it hermes-agent bash
nano /config/hermes-data/.env
```

添加：

```env
# 允许所有用户访问（本地/私有部署）
GATEWAY_ALLOW_ALL_USERS=true

# 建议同时设置 API Key 以启用 session 保持
API_SERVER_KEY=your_random_secret_key
```

保存后在 WebUI 中重启 Gateway 即可。

## 部署到 ModelScope Spaces

> **注意**：本镜像基于 linuxserver/baseimage-kasmvnc，使用 KasmVNC（WebSocket VNC）
> 和 s6-overlay 管理进程。从 v2026-04-18 起已切换到 KasmVNC 方案，
> 完美兼容云平台单端口 HTTP 反向代理。内置 PID 1 兼容层。

1. 在 ModelScope 创建一个新的创空间（SDK 选择 Docker）
2. 在创空间仓库中添加 `Dockerfile` 文件：
```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest

# ModelScope 创空间要求应用监听 7860 端口
# KasmVNC 通过 CUSTOM_PORT 环境变量切换端口
ENV CUSTOM_PORT=7860

EXPOSE 7860
```
3. 在创空间「设置」中添加所需环境变量（如 `OPENAI_API_KEY`）
4. 点击重启即可自动拉取镜像并部署

### 端口映射

创空间默认只暴露 `7860` 端口。你可以根据需要选择映射哪个服务：

| 映射端口 | 访问内容 | 说明 |
|----------|----------|------|
| `7860→3000` | KDE 桌面 | 浏览器访问完整 Linux 桌面（默认） |
| `7860→8648` | Hermes WebUI | 仅使用聊天/管理界面 |

如需同时访问桌面和 WebUI，建议使用 Docker 自行部署（见上方快速开始）。

### 常见问题

**Q: 创空间启动报错 `s6-overlay-suexec: fatal: can only run as pid 1`**

从 v2026-04-16 起已修复。请拉取最新镜像。如果仍遇到此问题，
请确保使用最新版镜像，其中包含 `s6-init.sh` PID 1 兼容层。

## 部署到 HuggingFace Spaces

在 Spaces 仓库中添加 `Dockerfile` 文件：

```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest

ENV HERMES_HOME=/data/hermes-data
ENV CUSTOM_PORT=7860

EXPOSE 7860
EXPOSE 8648
EXPOSE 8642
```

## 镜像构建

镜像通过 GitHub Actions 自动构建：
- `push` 到 `main` 分支时触发构建
- 每天 UTC 02:00（北京时间 10:00）定时检查上游更新（hermes-agent / hermes-webui / 基础镜像）
- 仅上游有变化时才构建，避免无意义重建
- 支持 `linux/amd64` 和 `linux/arm64` 双架构

### 构建流程

1. 基于 `ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm`（Debian 12 + KasmVNC）
2. 安装 KDE Plasma 桌面环境（kde-plasma-desktop + konsole + dolphin）
3. 使用 uv 安装 hermes-agent[all] 到 /opt/hermes-venv
4. NodeSource 安装 Node.js 22 + npm（Playwright + WhatsApp bridge）
5. 构建 EKKOLearnAI/hermes-web-ui（Vue 3 + Koa 2 BFF）
6. 设置桌面快捷方式、壁纸、开机自启
7. 推送多架构镜像到 ghcr.io

## 相关项目

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — Hermes Agent 上游
- [EKKOLearnAI/hermes-web-ui](https://github.com/EKKOLearnAI/hermes-web-ui) — Hermes WebUI 上游
- [linuxserver/docker-baseimage-kasmvnc](https://github.com/linuxserver/docker-baseimage-kasmvnc) — KasmVNC 基础镜像
- [kasmtech/KasmVNC](https://github.com/kasmtech/KasmVNC) — KasmVNC 远程桌面

## License

本仓库遵循 [MIT](LICENSE) 协议。
