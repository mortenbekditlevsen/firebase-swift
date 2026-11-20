# A WebSocket server for reproducing swift-corelibs-foundation bugs.
#   /fragments        "héllo wörld" in three fragments, split inside é and ö
#   /fragments-ascii  "hello world" in three fragments: "hel", "lo w", "orld"
#   /large            one text frame of 40,000 bytes
#   /missing          refuses the upgrade with 404 Not Found
# (client.swift's /refused connects to port 8766, where nothing listens.)
# Run: python3 server.py   (listens on 127.0.0.1:8765)
import base64, hashlib, socket, threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def frame(opcode, payload, fin):
    first = (0x80 if fin else 0) | opcode
    if len(payload) < 126:
        return bytes([first, len(payload)]) + payload
    return bytes([first, 126]) + len(payload).to_bytes(2, "big") + payload

def serve(conn):
    request = b""
    while b"\r\n\r\n" not in request:
        chunk = conn.recv(4096)
        if not chunk:
            return
        request += chunk
    lines = request.split(b"\r\n")
    path = lines[0].split(b" ")[1].decode()
    headers = {k.strip().lower(): v.strip() for k, _, v in (l.partition(b":") for l in lines[1:] if l)}
    if path == "/missing":
        conn.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        conn.close()
        return
    accept = base64.b64encode(hashlib.sha1(headers[b"sec-websocket-key"] + GUID).digest())
    conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
    if path == "/large":
        conn.sendall(frame(0x1, b"0123456789" * 4000, True))
    else:
        if path == "/fragments":
            parts = [b"h\xc3", b"\xa9llo w\xc3", b"\xb6rld"]  # "héllo wörld" in UTF-8
        else:
            parts = [b"hel", b"lo w", b"orld"]
        conn.sendall(frame(0x1, parts[0], False) + frame(0x0, parts[1], False) + frame(0x0, parts[2], True))
    while conn.recv(4096):  # until the client closes
        pass
    conn.close()

listener = socket.create_server(("127.0.0.1", 8765))
while True:
    conn, _ = listener.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
