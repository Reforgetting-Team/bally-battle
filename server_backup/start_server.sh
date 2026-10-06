#!/usr/bin/env bash
# ==============================================================================
# Bally Battle Server Startup Script
# Runs the coordinator and cloudflared in the background using nohup
# ==============================================================================

set -e

SERVER_DIR="$HOME/bally_battle_server"
mkdir -p "$SERVER_DIR"

cd "$SERVER_DIR"

# 1. Kill any existing instances cleanly
pkill -f "coordinator.py" 2>/dev/null || true
pkill -f "cloudflared tunnel" 2>/dev/null || true
pkill -f "bally_server.x86_64" 2>/dev/null || true
sleep 1

# 2. Make sure binary is executable
if [ -f "$SERVER_DIR/bally_server.x86_64" ]; then
    chmod +x "$SERVER_DIR/bally_server.x86_64"
fi

# 3. Start Coordinator with nohup
echo "[Server] Launching coordinator..."
nohup python3 "$SERVER_DIR/coordinator.py" > "$SERVER_DIR/coordinator.log" 2>&1 &
COORDINATOR_PID=$!
echo "[Server] Coordinator started (PID: $COORDINATOR_PID)"

# 4. Start Cloudflare Tunnel with nohup
CLOUDFLARED_BIN="$HOME/bin/cloudflared"
if [ ! -f "$CLOUDFLARED_BIN" ]; then
    CLOUDFLARED_BIN="cloudflared"
fi

echo "[Server] Launching cloudflared tunnel..."
nohup "$CLOUDFLARED_BIN" tunnel --url http://127.0.0.1:8910 > "$SERVER_DIR/cloudflared.log" 2>&1 &
CLOUDFLARED_PID=$!
echo "[Server] cloudflared started (PID: $CLOUDFLARED_PID)"

# 5. Wait for tunnel URL
echo "[Server] Waiting for Cloudflare tunnel URL..."
TUNNEL_URL=""
for i in {1..20}; do
    sleep 1
    if grep -q "trycloudflare.com" "$SERVER_DIR/cloudflared.log" 2>/dev/null; then
        TUNNEL_URL=$(grep -o 'https://[-a-zA-Z0-9\.]*\.trycloudflare\.com' "$SERVER_DIR/cloudflared.log" | tail -n 1)
        break
    fi
done

echo "=========================================================="
echo "Bally Battle Global Server is RUNNING!"
echo "Local / ZeroTier IP: 10.24.60.105:8910"
if [ -n "$TUNNEL_URL" ]; then
    echo "Cloudflare Tunnel URL: $TUNNEL_URL"
    echo "$TUNNEL_URL" > "$SERVER_DIR/tunnel_url.txt"
else
    echo "Cloudflare Tunnel URL still initializing (check cloudflared.log)"
fi
echo "=========================================================="
