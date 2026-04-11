# hermes-agent-desktop

基于 [ghcr.io/tunmax/openclaw_computer](https://github.com/tunmax/openclaw_computer) (Linux GUI 桌面) + [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) + [Pan UI](https://github.com/Euraika-Labs/pan-ui) (中文 i18n 版) 打包的一体化 Docker 镜像。

## 镜像地址

```
ghcr.io/comedy1024/hermes-agent-desktop:latest
```

## 功能特性

- 🖥️ **Linux GUI 桌面** — 通过 noVNC 在浏览器中访问完整 Linux 桌面环境
- 🤖 **Hermes Agent** — 自演化 AI Agent 框架，支持多种 LLM 提供者
- 🌐 **Pan UI 中文版** — Hermes Agent 专用的全功能 Web 管理界面（i18n 中文化）
- 🔧 **全功能管理** — 聊天、技能管理、MCP 扩展、记忆编辑、配置管理

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 7860 | noVNC | Linux GUI 桌面（浏览器访问） |
| 3199 | Pan UI | Web 管理界面（中文 i18n） |
| 8642 | Hermes Gateway | OpenAI 兼容 API |

## 快速开始（本地运行）

```bash
docker run -d \
  --name hermes-agent \
  -p 7860:7860 \
  -p 3199:3199 \
  -p 8642:8642 \
  -v ./hermes-data:/opt/data \
  ghcr.io/comedy1024/hermes-agent-desktop:latest
```

启动后：
1. 打开 `http://localhost:3199` 访问 Pan UI 管理界面（中文）
2. 打开 `http://localhost:7860` 访问 Linux 桌面
3. `http://localhost:8642` 为 Hermes Gateway API

## 常用环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `OPENAI_API_KEY` | OpenAI API Key | - |
| `ANTHROPIC_API_KEY` | Anthropic API Key | - |
| `OPENROUTER_API_KEY` | OpenRouter API Key | - |
| `HERMES_HOME` | 数据目录 | `/opt/data` |
| `PAN_UI_PORT` | Pan UI 端口 | `3199` |
| `HERMES_GATEWAY_PORT` | Gateway API 端口 | `8642` |

完整配置项请参考容器内的 `/opt/data/.env` 模板文件。

## Pan UI 登录

默认登录凭据：
- 用户名：`admin`
- 密码：`changeme`

**请在首次登录后立即修改密码！**

## 数据持久化

所有配置、记忆、技能、会话日志均保存在 `/opt/data` 目录下：

```bash
-v ./hermes-data:/opt/data
```

目录结构：
```
/opt/data/
├── .env           # 环境配置
├── config.yaml    # 主配置
├── SOUL.md        # Agent 人格
├── memories/      # 长期记忆
├── skills/        # 技能库
├── sessions/      # 会话记录
├── logs/          # 运行日志
└── workspace/     # 工作目录
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

EXPOSE 7860
EXPOSE 3199
EXPOSE 8642

VOLUME ["/opt/data"]
```

## 镜像构建

镜像通过 GitHub Actions 自动构建：
- `push` 到 `main` 分支时触发构建
- 每天 UTC 02:00（北京时间 10:00）定时检查更新
- 支持 `linux/amd64` 和 `linux/arm64` 双架构

### 构建流程

1. 拉取 Pan UI 源码并应用 i18n 补丁
2. 构建 Pan UI 中文版
3. 基于 openclaw_computer 镜像，安装 Hermes Agent + Pan UI
4. 推送多架构镜像到 ghcr.io

## i18n 中文支持

Pan UI 已通过 [next-intl](https://next-intl.dev/) 实现完整的国际化支持：
- 🇨🇳 简体中文（默认）
- 🇺🇸 English

所有界面文字、按钮、提示、错误信息均已翻译，包括：
- 导航栏和侧边栏
- 聊天界面
- 技能管理
- 扩展/MCP 管理
- 记忆编辑
- 配置管理
- 设置面板

## 相关项目

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — Hermes Agent 上游
- [Euraika-Labs/pan-ui](https://github.com/Euraika-Labs/pan-ui) — Pan UI 上游
- [tunmax/openclaw_computer](https://github.com/tunmax/openclaw_computer) — Linux 桌面基础镜像

## License

本仓库遵循 [Apache 2.0](LICENSE) 协议，与上游 hermes-agent 保持一致。
