#!/bin/bash
set -e

# ================================================================
# herme-agent-docker Entrypoint
# Starts: Linux Desktop (noVNC) + Hermes Agent Gateway + Pan UI
# ================================================================

HERMES_HOME="${HERMES_HOME:-/opt/data}"
PAN_UI_PORT="${PAN_UI_PORT:-3199}"
HERMES_GATEWAY_PORT="${HERMES_GATEWAY_PORT:-8642}"

echo "============================================================"
echo "  herme-agent-docker"
echo "  Hermes Agent + Pan UI (i18n) in Linux GUI Desktop"
echo "============================================================"
echo ""
echo "  noVNC Desktop:  http://0.0.0.0:7860"
echo "  Pan UI:         http://0.0.0.0:${PAN_UI_PORT}"
echo "  Hermes Gateway: http://0.0.0.0:${HERMES_GATEWAY_PORT}"
echo "  Data directory: ${HERMES_HOME}"
echo ""

# Ensure data directory exists
mkdir -p "${HERMES_HOME}"
mkdir -p /var/log/supervisor

# Initialize Hermes config if not present
if [ ! -f "${HERMES_HOME}/.env" ]; then
    echo "[init] Creating default .env template..."
    cat > "${HERMES_HOME}/.env" << 'ENVEOF'
# Hermes Agent Configuration
# Fill in your API keys below

# LLM Provider Keys (uncomment and fill as needed)
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# OPENROUTER_API_KEY=sk-or-...

# Hermes settings
HERMES_HOME=/opt/data
HERMES_LOG_LEVEL=info
ENVEOF
fi

if [ ! -f "${HERMES_HOME}/config.yaml" ]; then
    echo "[init] Creating default config.yaml..."
    cat > "${HERMES_HOME}/config.yaml" << 'YAMLEOF'
# Hermes Agent Configuration
# See: https://github.com/NousResearch/hermes-agent

agent:
  name: Pan
  model_default: gpt-4o

gateway:
  host: 0.0.0.0
  port: 8642

memory:
  mode: hybrid

policy:
  preset: safe-chat
YAMLEOF
fi

# Create Pan UI .env if not present
if [ ! -f "/opt/pan-ui/.env" ]; then
    echo "[init] Creating Pan UI environment..."
    cat > "/opt/pan-ui/.env" << 'PANEOF'
HERMES_RUNTIME_URL=http://localhost:8642
PAN_UI_HOST=0.0.0.0
PAN_UI_PORT=3199
NEXT_LOCALE=zh-CN
PANEOF
fi

echo "[init] Starting all services via supervisord..."
echo ""

# Start supervisord (manages all services)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/hermes.conf
