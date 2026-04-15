# hermes-agent-desktop

基于 [LinuxServer.io Webtop (Ubuntu KDE)](https://github.com/linuxserver/docker-webtop) + [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) + [Hermes WebUI](https://github.com/nesquena/hermes-webui) 打包的一体化 Docker 镜像。

## 镜像地址

```
ghcr.io/comedy1024/hermes-agent-desktop:latest
```

## 功能特性

- 🖥️ **Linux GUI 桌面** — 通过 noVNC 在浏览器中访问完整 Ubuntu KDE 桌面环境
- 🤖 **Hermes Agent** — 自演化 AI Agent 框架，支持 OpenAI / Anthropic / DeepSeek / Ollama 等
- 🌐 **Hermes WebUI** — 社区最活跃的 Hermes Agent Web 管理界面（1.6k+ Stars）
- 🔧 **全功能管理** — 流式聊天、文件浏览器、技能管理、记忆编辑、语音输入、7 种主题
- 🔗 **CLI 会话桥接** — 终端和 WebUI 共享会话，无缝切换
- 🔒 **官方镜像基础** — 基于 LinuxServer.io 官方维护镜像，安全可靠，多架构支持

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| `3000` | noVNC | Linux KDE 桌面（浏览器访问，HTTP） |
| `3001` | noVNC | Linux KDE 桌面（浏览器访问，HTTPS） |
| `8787` | Hermes WebUI | Web 管理界面（聊天/配置/运维）|
| `8642` | Hermes Gateway | OpenAI 兼容 API（WebUI 自动管理）|

## 快速开始（本地运行）

```bash
docker run -d \
  --name hermes-agent \
  -p 3000:3000 \
  -p 3001:3001 \
  -p 8787:8787 \
  -p 8642:8642 \
  -v hermes-data:/config \
  ghcr.io/comedy1024/hermes-agent-desktop:latest
```

启动后：
1. 打开 `http://localhost:8787` — Hermes WebUI 管理界面（首次配置 LLM API Key）
2. 打开 `http://localhost:3000` — Linux KDE 桌面（noVNC）
3. `http://localhost:8642` — Hermes Gateway OpenAI 兼容 API

## 常用环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `OPENAI_API_KEY` | OpenAI API Key | — |
| `ANTHROPIC_API_KEY` | Anthropic API Key | — |
| `OPENROUTER_API_KEY` | OpenRouter API Key | — |
| `PASSWORD` | KDE 桌面访问密码 | （空，无密码）|
| `HERMES_HOME` | Hermes 数据目录 | `/config/hermes-data` |
| `HERMES_WEBUI_PORT` | WebUI 端口 | `8787` |
| `HERMES_WEBUI_PASSWORD` | WebUI 访问密码（可选）| — |
| `GATEWAY_ALLOW_ALL_USERS` | 允许所有用户访问 Gateway | `false` |
| `API_SERVER_KEY` | Gateway API 鉴权 Key（启用 session 保持）| — |

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
│   ├── skills/        # 技能库（78 个预装）
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

### HuggingFace Spaces 数据持久化

在 HF Spaces 设置中开启 **Persistent Storage**，然后在 `Dockerfile` 中重定向数据目录：

```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest

ENV HERMES_HOME=/data/hermes-data
ENV HERMES_WEBUI_STATE_DIR=/data/hermes-data/.hermes/webui-mvp
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/data/hermes-data

EXPOSE 7860
```

## 部署到 ModelScope Spaces

1. 在 ModelScope 创建一个新的创空间
2. 在创空间仓库中添加 `Dockerfile` 文件：
```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest
```
3. 在创空间「设置」中添加所需环境变量
4. 点击重启即可自动拉取镜像并部署

## 部署到 HuggingFace Spaces

在 Spaces 仓库中添加 `Dockerfile` 文件：

```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest

ENV HERMES_HOME=/data/hermes-data
ENV HERMES_WEBUI_STATE_DIR=/data/hermes-data/.hermes/webui-mvp
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/data/hermes-data

EXPOSE 7860
EXPOSE 8787
EXPOSE 8642
```

## 镜像构建

镜像通过 GitHub Actions 自动构建：
- `push` 到 `main` 分支时触发构建
- 每天 UTC 02:00（北京时间 10:00）定时检查上游更新（hermes-agent / hermes-webui / 基础镜像）
- 仅上游有变化时才构建，避免无意义重建
- 支持 `linux/amd64` 和 `linux/arm64` 双架构

### 构建流程

1. Stage 1：clone hermes-webui 源码
2. Stage 2：基于官方 `lscr.io/linuxserver/webtop:ubuntu-kde`
3. 安装 hermes-agent（系统 Python + WebUI venv 双份，深度集成）
4. 安装 Playwright + WhatsApp bridge
5. 设置桌面快捷方式、壁纸、开机自启
6. 推送多架构镜像到 ghcr.io

## 相关项目

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — Hermes Agent 上游
- [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) — Hermes WebUI 上游
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — Linux GUI 桌面基础镜像

## License

本仓库遵循 [MIT](LICENSE) 协议，与上游 hermes-webui 保持一致。
