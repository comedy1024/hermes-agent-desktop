# ModelScope 创空间配置指南

## 步骤 1：进入创空间设置

1. 打开你的 ModelScope 创空间页面
2. 点击「设置」或「配置」选项卡
3. 找到「Dockerfile 配置」或「启动配置」区域

## 步骤 2：修改 Dockerfile

**删除原有的 Dockerfile 内容**，替换为以下内容：

```dockerfile
FROM ghcr.io/comedy1024/hermes-agent-desktop:latest

# 设置 KasmVNC 使用 7860 端口（ModelScope 要求）
ENV CUSTOM_PORT=7860
```

## 步骤 3：删除不需要的文件

如果创空间里有以下文件，请删除：
- `app.py`
- 其他不必要的配置文件

## 步骤 4：保存并部署

1. 点击「保存」或「提交」
2. 等待创空间重新部署（可能需要 5-10 分钟拉取镜像）

## 步骤 5：验证部署

部署完成后，访问创空间 URL，你应该能看到：
- KasmVNC 登录页面（输入密码后进入 KDE 桌面）
- 桌面上的 Hermes 终端自动启动

---

## 故障排查

### 如果仍然报错 `/init: not found`

1. 确认镜像标签是否正确：`ghcr.io/comedy1024/hermes-agent-desktop:latest`
2. 尝试使用具体 digest 而不是 `latest`：
   ```dockerfile
   FROM ghcr.io/comedy1024/hermes-agent-desktop@sha256:xxx
   ```
   （将 xxx 替换为实际 digest，可在 GitHub Packages 页面查看）

### 如果页面无法访问

1. 检查 ModelScope 创空间日志
2. 确认端口配置是否为 7860
3. 等待更长时间（首次拉取镜像可能较慢）

---

## 镜像信息

- **镜像地址**: `ghcr.io/comedy1024/hermes-agent-desktop:latest`
- **最新构建**: #52 (commit b02ef3e)
- **构建时间**: 2026-04-18
- **包含功能**:
  - KasmVNC 远程桌面 (KDE Plasma)
  - Hermes Agent 框架
  - Hermes WebUI (端口 8648)
  - 内置 Nginx 反向代理
