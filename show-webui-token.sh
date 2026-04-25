#!/bin/bash
# ================================================================
# show-webui-token.sh — Display Hermes WebUI login token
# ================================================================
# This script reads the current WebUI authentication token from
# ~/.hermes-web-ui/.token and displays it in a dialog window.
#
# Usage: Click the desktop shortcut or run: /opt/show-webui-token.sh
# ================================================================

TOKEN_FILE="/root/.hermes-web-ui/.token"

if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n')
    echo "WebUI 登录 Token:"
    echo "=================="
    echo "$TOKEN"
    echo ""
    echo "在 WebUI 登录页面输入此 Token，或添加到 API 请求的 Authorization 头中。"
    echo "Token 文件位置: $TOKEN_FILE"
else
    echo "错误：Token 文件不存在"
    echo "文件路径: $TOKEN_FILE"
    echo ""
    echo "可能原因："
    echo "  1. WebUI 尚未启动"
    echo "  2. AUTH_DISABLED=true（认证已禁用）"
    echo "  3. token 文件被删除"
    echo ""
    echo "请先启动 Hermes WebUI，然后重试。"
fi
