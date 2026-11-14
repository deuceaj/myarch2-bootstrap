#!/usr/bin/env python3
"""Receive files sent from the test VM over QEMU's user network.

    vm-receive.py OUTFILE [PORT]      (default port 9999, listens on 127.0.0.1)

Inside the VM, QEMU maps 10.0.2.2 to Primus's 127.0.0.1, so the guest sends with:
    cat FILES > /dev/tcp/10.0.2.2/9999
Accepts one connection, writes it to OUTFILE, exits.
"""
import socket
import sys

out = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 9999
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(1)
print(f"waiting on 127.0.0.1:{port} -> {out}", flush=True)
conn, _ = srv.accept()
n = 0
with open(out, "wb") as f:
    while chunk := conn.recv(65536):
        f.write(chunk)
        n += len(chunk)
print(f"received {n} bytes", flush=True)
