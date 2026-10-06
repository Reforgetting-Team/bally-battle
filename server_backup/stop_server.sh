#!/usr/bin/env bash
# Stop script for Bally Battle server processes
echo "[Server] Stopping Bally Battle server components..."
pkill -f "coordinator.py" 2>/dev/null || true
pkill -f "cloudflared tunnel" 2>/dev/null || true
pkill -f "bally_server.x86_64" 2>/dev/null || true
echo "[Server] All components stopped."
