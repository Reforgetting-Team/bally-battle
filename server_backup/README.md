# Bally Battle Dedicated Server Backup

This folder contains a complete, self-contained backup of the Bally Battle dedicated server system.
When you move to a new VPS (e.g. located in South America / US for low ping), you can migrate and launch everything with just a few steps.

## What's Included
- `bally_server.x86_64`: Headless Godot 4.7.2 Linux binary for Bally Battle with room netcode, anti-wall clip physics, and throttled transform sync.
- `coordinator.py`: Lightweight coordinator server that manages room lifecycles, creates/joins rooms by 4-letter code, and multiplexes WebSockets.
- `start_server.sh`: One-click startup script that starts the coordinator and Cloudflare Tunnel in the background with `nohup`.
- `stop_server.sh`: One-click shutdown script for clean teardown.

## How to Deploy to a New VPS

1. **Copy this folder to your new VPS:**
   ```bash
   scp -r server_backup user@new_vps_ip:~/bally_battle_server
   ```
   Or unpack the tarball:
   ```bash
   scp server_backup/bally_battle_server_backup.tar.gz user@new_vps_ip:~/
   ssh user@new_vps_ip "tar -xzvf bally_battle_server_backup.tar.gz"
   ```

2. **Make sure Python 3 and cloudflared are installed on the new VPS:**
   ```bash
   # Debian / Ubuntu:
   sudo apt update && sudo apt install -y python3 curl
   
   # Install cloudflared (if not already present):
   curl -L --output ~/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
   chmod +x ~/bin/cloudflared
   ```

3. **Start the server:**
   ```bash
   cd ~/bally_battle_server
   ./start_server.sh
   ```

4. **Connect to your server in Bally Battle:**
   - The startup script will output the new Cloudflare Tunnel URL (e.g. `https://xxxx.trycloudflare.com`) or you can use your new VPS direct IP and port `8910`.
   - In Bally Battle, click **CUSTOM IP** in the multiplayer menu, type the address and port (or paste the tunnel URL), and click **SAVE SERVER**.
