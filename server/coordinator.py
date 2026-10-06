#!/usr/bin/env python3
"""
Bally Battle Global Server Coordinator & WebSocket Multiplexer
Indie dev server manager for headless Bally Battle rooms.
Spawns dedicated headless room servers on demand and routes players by room code.
"""

import os
import sys
import time
import socket
import select
import threading
import json
import subprocess
import random
import urllib.parse

# make logs flush immediately to disk
try:
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
except Exception:
    pass

COORDINATOR_PORT = int(os.environ.get("PORT", 8910))
ROOM_PORT_START = 8920
ROOM_PORT_END = 8999

# find bally server binary path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BINARY_CANDIDATES = [
    os.path.join(os.path.expanduser("~"), "bally_battle_server", "bally_server.x86_64"),
    os.path.join(SCRIPT_DIR, "bally_server.x86_64"),
    os.path.join(SCRIPT_DIR, "..", "Exports", "Bally Battle.x86_64"),
    "/usr/bin/godot"
]

SERVER_BINARY = None
for candidate in BINARY_CANDIDATES:
    if os.path.exists(candidate) and os.access(candidate, os.X_OK):
        SERVER_BINARY = candidate
        break

rooms = {} # code -> {port, proc, created_at, last_active}
rooms_lock = threading.Lock()

def get_free_port():
    with rooms_lock:
        used_ports = {r["port"] for r in rooms.values()}
        for p in range(ROOM_PORT_START, ROOM_PORT_END):
            if p not in used_ports:
                try:
                    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    s.bind(('127.0.0.1', p))
                    s.close()
                    return p
                except OSError:
                    continue
    raise RuntimeError("No free room ports available!")

def generate_room_code():
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # no ambiguous chars like 0/O, 1/I
    with rooms_lock:
        for _ in range(500):
            code = ''.join(random.choice(chars) for _ in range(4))
            if code not in rooms:
                return code
    return f"ROOM{random.randint(100, 999)}"

def spawn_room_server(room_code: str, port: int):
    global SERVER_BINARY
    if not SERVER_BINARY:
        # check again in case binary was placed recently
        for candidate in BINARY_CANDIDATES:
            if os.path.exists(candidate) and os.access(candidate, os.X_OK):
                SERVER_BINARY = candidate
                break

    if not SERVER_BINARY:
        raise RuntimeError("Bally Battle server executable not found!")

    cmd = [
        SERVER_BINARY,
        "--headless",
        "--",
        "--room-server",
        "--code", room_code,
        "--port", str(port)
    ]
    print(f"[Coordinator] Spawning dedicated room server: {' '.join(cmd)}")
    log_file = os.path.join(os.path.expanduser("~"), f"room_{room_code}.log")
    try:
        out = open(log_file, "w")
    except Exception:
        out = subprocess.DEVNULL

    proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
    return proc

def monitor_rooms():
    while True:
        time.sleep(5)
        with rooms_lock:
            dead_codes = []
            for code, info in rooms.items():
                proc = info.get("proc")
                if proc and proc.poll() is not None:
                    print(f"[Coordinator] Room {code} exited with code {proc.returncode}")
                    dead_codes.append(code)
                elif time.time() - info.get("created_at", 0) > 3600:
                    # max room lifetime 1 hour safety cap
                    print(f"[Coordinator] Room {code} exceeded max lifetime, terminating")
                    if proc:
                        try: proc.terminate()
                        except: pass
                    dead_codes.append(code)

            for code in dead_codes:
                rooms.pop(code, None)

def forward_sockets(src, dst):
    try:
        while True:
            r, _, _ = select.select([src], [], [], 1.0)
            if not r:
                continue
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle_client(client_sock, client_addr):
    try:
        client_sock.settimeout(10.0)
        initial_data = b""
        while b"\r\n\r\n" not in initial_data:
            chunk = client_sock.recv(4096)
            if not chunk:
                break
            initial_data += chunk
            if len(initial_data) > 65536:
                break

        if not initial_data:
            client_sock.close()
            return

        header_text = initial_data.decode("utf-8", errors="ignore")
        first_line = header_text.split("\r\n")[0]
        parts = first_line.split(" ")
        if len(parts) < 2:
            client_sock.close()
            return

        method = parts[0].upper()
        raw_path = parts[1]
        parsed_url = urllib.parse.urlparse(raw_path)
        path = parsed_url.path
        query = urllib.parse.parse_qs(parsed_url.query)

        # 1. API: create_room
        if path == "/api/create_room":
            try:
                code = generate_room_code()
                port = get_free_port()
                proc = spawn_room_server(code, port)
                with rooms_lock:
                    rooms[code] = {
                        "port": port,
                        "proc": proc,
                        "created_at": time.time(),
                        "last_active": time.time()
                    }
                # wait a fraction of a second for server to bind port
                time.sleep(0.4)
                resp = json.dumps({"status": "ok", "code": code, "port": port}).encode("utf-8")
                client_sock.sendall(
                    b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Access-Control-Allow-Origin: *\r\n"
                    b"Connection: close\r\n\r\n" + resp
                )
            except Exception as e:
                resp = json.dumps({"status": "error", "message": str(e)}).encode("utf-8")
                client_sock.sendall(
                    b"HTTP/1.1 500 Internal Error\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Connection: close\r\n\r\n" + resp
                )
            client_sock.close()
            return

        # 2. API: join_room
        elif path == "/api/join_room":
            code = query.get("code", [""])[0].strip().upper()
            target_room = None
            with rooms_lock:
                target_room = rooms.get(code)

            if target_room and target_room["proc"].poll() is None:
                resp = json.dumps({"status": "ok", "code": code, "port": target_room["port"]}).encode("utf-8")
                client_sock.sendall(
                    b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Access-Control-Allow-Origin: *\r\n"
                    b"Connection: close\r\n\r\n" + resp
                )
            else:
                resp = json.dumps({"status": "error", "message": f"Room '{code}' not found or match has ended."}).encode("utf-8")
                client_sock.sendall(
                    b"HTTP/1.1 404 Not Found\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Access-Control-Allow-Origin: *\r\n"
                    b"Connection: close\r\n\r\n" + resp
                )
            client_sock.close()
            return

        # 3. API: status / rooms
        elif path in ("/api/status", "/api/rooms", "/"):
            with rooms_lock:
                active_codes = [c for c, r in rooms.items() if r["proc"].poll() is None]
            resp = json.dumps({
                "status": "ok",
                "game": "Bally Battle Dedicated Server",
                "active_rooms": len(active_codes),
                "rooms": active_codes
            }).encode("utf-8")
            client_sock.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/json\r\n"
                b"Access-Control-Allow-Origin: *\r\n"
                b"Connection: close\r\n\r\n" + resp
            )
            client_sock.close()
            return

        # 4. WebSocket proxy for /room/<CODE> or /ws/<CODE>
        elif path.startswith("/room/") or path.startswith("/ws/"):
            parts = path.split("/")
            code = parts[2].strip().upper() if len(parts) > 2 else ""
            target_room = None
            with rooms_lock:
                target_room = rooms.get(code)

            if not target_room or target_room["proc"].poll() is not None:
                client_sock.sendall(
                    b"HTTP/1.1 404 Room Not Found\r\n"
                    b"Content-Type: text/plain\r\n"
                    b"Connection: close\r\n\r\n"
                    b"Room not found or expired."
                )
                client_sock.close()
                return

            # connect to the local room server WebSocket port
            target_port = target_room["port"]
            try:
                backend_sock = socket.create_connection(('127.0.0.1', target_port), timeout=5.0)
            except Exception as e:
                client_sock.sendall(
                    b"HTTP/1.1 502 Bad Gateway\r\n"
                    b"Content-Type: text/plain\r\n"
                    b"Connection: close\r\n\r\n"
                    b"Could not connect to room process."
                )
                client_sock.close()
                return

            # forward the initial handshake bytes
            backend_sock.sendall(initial_data)

            # remove socket timeout for persistent WebSocket connection
            client_sock.settimeout(None)
            backend_sock.settimeout(None)

            t1 = threading.Thread(target=forward_sockets, args=(client_sock, backend_sock), daemon=True)
            t2 = threading.Thread(target=forward_sockets, args=(backend_sock, client_sock), daemon=True)
            t1.start()
            t2.start()
            return

        # default 404
        else:
            client_sock.sendall(
                b"HTTP/1.1 404 Not Found\r\n"
                b"Content-Type: text/plain\r\n"
                b"Connection: close\r\n\r\n"
                b"Not Found"
            )
            client_sock.close()
            return

    except Exception as e:
        try: client_sock.close()
        except: pass

def main():
    print("=" * 60)
    print(f"Bally Battle Coordinator starting on port {COORDINATOR_PORT}")
    print(f"Using server binary: {SERVER_BINARY}")
    print("=" * 60)

    threading.Thread(target=monitor_rooms, daemon=True).start()

    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(('0.0.0.0', COORDINATOR_PORT))
    server_sock.listen(128)

    print(f"[Coordinator] Listening on 0.0.0.0:{COORDINATOR_PORT}...")
    try:
        while True:
            client_sock, client_addr = server_sock.accept()
            threading.Thread(target=handle_client, args=(client_sock, client_addr), daemon=True).start()
    except KeyboardInterrupt:
        print("\n[Coordinator] Shutting down...")
    finally:
        server_sock.close()
        with rooms_lock:
            for info in rooms.values():
                proc = info.get("proc")
                if proc:
                    try: proc.terminate()
                    except: pass

if __name__ == "__main__":
    main()
