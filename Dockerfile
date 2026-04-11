# ================================================================
# hermes-agent-desktop: Linux GUI Desktop + Hermes Agent + Pan UI (i18n)
# Based on: ghcr.io/tunmax/openclaw_computer (noVNC Linux Desktop)
# ================================================================
#
# Build stages:
#   1. Build Pan UI (Next.js) with Chinese i18n support
#   2. Combine everything into the openclaw desktop image
#
# Ports:
#   7860 - noVNC web desktop
#   3199 - Pan UI web management interface
#   8642 - Hermes Agent Gateway API

# ---- Stage 1: Build Pan UI with i18n ----
FROM node:20-slim AS pan-ui-builder

WORKDIR /build

# Clone Pan UI source
RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/Euraika-Labs/pan-ui.git . && \
    rm -rf .git

# Install dependencies
RUN npm ci

# Install i18n dependency (added by our patches)
RUN npm install next-intl@^4.9.1

# Apply i18n patches - copy over modified files
COPY patches/messages/ ./messages/
COPY patches/i18n/ ./src/i18n/
COPY patches/next.config.ts ./next.config.ts
COPY patches/app/layout.tsx ./src/app/layout.tsx
COPY patches/app/login/ ./src/app/login/
COPY patches/components/ ./src/components/
COPY patches/features/ ./src/features/
COPY patches/lib/ ./src/lib/

# Build Pan UI for production with standalone output
RUN npm run build

# ---- Stage 2: Final image ----
FROM ghcr.io/tunmax/openclaw_computer:latest

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Pan UI (i18n) in Linux GUI Desktop"
LABEL org.opencontainers.image.licenses=Apache-2.0

# Install all system dependencies (matching official hermes-agent Dockerfile)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc \
    python3 python3-pip python3-venv python3-dev \
    libffi-dev ripgrep ffmpeg procps \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN pip install --no-cache-dir uv --break-system-packages

# Clone and install Hermes Agent (following official Dockerfile approach)
# This is the slowest layer - split from Pan UI for better caching
RUN git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    cd /opt/hermes && \
    uv pip install --system --break-system-packages --no-cache -e ".[all]" && \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    cd scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm

# Copy Hermes Agent docker config templates
# (hermes entrypoint.sh will bootstrap config from these)
RUN chmod +x /opt/hermes/docker/entrypoint.sh

# Set up Hermes environment
ENV HERMES_HOME=/opt/data
ENV PYTHONUNBUFFERED=1
RUN mkdir -p /opt/data

# Copy built Pan UI from builder stage
# Note: Pan UI has no public/ directory - static assets are in .next/static
COPY --from=pan-ui-builder /build/.next/standalone /opt/pan-ui
COPY --from=pan-ui-builder /build/.next/static /opt/pan-ui/.next/static
# messages/ contains i18n translation files needed at runtime by next-intl
COPY --from=pan-ui-builder /build/messages /opt/pan-ui/messages

# Copy our configuration files
COPY supervisord.conf /etc/supervisor/conf.d/hermes.conf
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Expose ports
# 7860 - noVNC (from openclaw base)
# 3199 - Pan UI
# 8642 - Hermes Gateway API
EXPOSE 7860 3199 8642

# Data volume
VOLUME ["/opt/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:3199/ || exit 1

ENTRYPOINT ["/opt/entrypoint.sh"]
