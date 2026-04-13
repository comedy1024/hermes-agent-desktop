# hermes-agent-desktop

基于 [ghcr.io/tunmax/openclaw_computer](https://github.com/tunmax/openclaw_computer) (Linux GUI 桌面) + [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) + [Hermes WebUI](https://github.com/nesquena/hermes-webui) 打包的一体化 Docker 镜像。

## 镜像地址

```
ghcr.io/comedy1024/hermes-agent-desktop:latest
```

## 功能特性

- 🖥️ **Linux GUI 桌面** — 通过 noVNC 在浏览器中访问完整 Linux 桌面环境
- 🤖 **Hermes Agent** — 自演化 AI Agent 框架，支持多种 LLM 提供者
- 🌐 **Hermes WebUI** — 社区最活跃的 Hermes Agent Web 管理界面（1.6k+ Stars）
- 🔧 **全功能管理** — 流式聊天、文件浏览器、技能管理、记忆编辑、语音输入、7 种主题
- 🔗 **CLI 会话桥接** — 终端和 WebUI 共享会话，无缝切换

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 7860 | noVNC | Linux GUI 桌面（浏览器访问） |
| 8787 | Hermes WebUI | Web 管理界面 |
| 8642 | Hermes Gateway | OpenAI 兼容 API |

## 快速开始（本地运行）

```bash
docker run -d \
  --name hermes-agent \
  -p 7860:7860 \
  -p 8787:8787 \
  -p 8642:8642 \
  -v ./hermes-data:/opt/data \
  ghcr.io/comedy1024/hermes-agent-desktop:latest
```

启动后：
1. 打开 `http://localhost:8787` 访问 Hermes WebUI 管理界面
2. 打开 `http://localhost:7860` 访问 Linux 桌面
3. `http://localhost:8642` 为 Hermes Gateway API

## 常用环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `OPENAI_API_KEY` | OpenAI API Key | - |
| `ANTHROPIC_API_KEY` | Anthropic API Key | - |
| `OPENROUTER_API_KEY` | OpenRouter API Key | - |
| `HERMES_HOME` | 数据目录 | `/opt/data` |
| `HERMES_WEBUI_PORT` | WebUI 端口 | `8787` |
| `HERMES_WEBUI_PASSWORD` | WebUI 访问密码（可选） | - |

完整配置项请参考容器内的 `/opt/data/.env` 模板文件。

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
├── workspace/     # 工作目录
└── .hermes/
    └── webui-mvp/ # WebUI 状态与配置
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
EXPOSE 8787
EXPOSE 8642

VOLUME ["/opt/data"]
```

## 镜像构建

镜像通过 GitHub Actions 自动构建：
- `push` 到 `main` 分支时触发构建
- 每天 UTC 02:00（北京时间 10:00）定时检查更新
- 支持 `linux/amd64` 和 `linux/arm64` 双架构

### 构建流程

1. 拉取 Hermes WebUI 源码并安装 Python 依赖
2. 基于 openclaw_computer 镜像，安装 Hermes Agent + WebUI
3. 替换 OpenClaw 品牌为 Hermes Agent Desktop
4. 推送多架构镜像到 ghcr.io

## 相关项目

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — Hermes Agent 上游
- [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) — Hermes WebUI 上游
- [tunmax/openclaw_computer](https://github.com/tunmax/openclaw_computer) — Linux 桌面基础镜像

## License

本仓库遵循 [MIT](LICENSE) 协议，与上游 hermes-webui 保持一致。
