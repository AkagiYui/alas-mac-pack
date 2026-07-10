#!/usr/bin/env python3
"""
Open a real pywebio websocket session against a running Alas webui and report
whether the initial page (index() -> AlasGUI.run) renders without an internal
error. A plain HTTP GET only returns the bootstrap HTML; the session — which
loads cwd-relative assets like ./assets/gui/css/alas.css — only runs over the
websocket, so this is what catches asset / working-directory bugs.

Usage: webui-session-check.py <port>
Exit 0 if the session renders cleanly, non-zero (with details) otherwise.
"""
import asyncio
import json
import sys

import websockets

PORT = sys.argv[1] if len(sys.argv) > 1 else "22267"
URL = f"ws://127.0.0.1:{PORT}/"
BAD = ("FileNotFoundError", "Traceback", "内部错误", "No such file", "Internal Server Error")


async def check():
    async with websockets.connect(URL, open_timeout=15, max_size=None) as ws:
        blob = ""
        try:
            # Collect the server's initial command burst for a few seconds.
            while True:
                msg = await asyncio.wait_for(ws.recv(), timeout=6)
                blob += msg if isinstance(msg, str) else msg.decode("utf-8", "ignore")
        except (asyncio.TimeoutError, Exception):
            pass
    hit = next((b for b in BAD if b in blob), None)
    if hit:
        print(f"  session ERROR (matched {hit!r}):")
        print("  " + blob[:800].replace("\n", "\n  "))
        return 1
    if not blob:
        print("  session produced no output (unexpected)")
        return 2
    print(f"  session rendered OK ({len(blob)} bytes of commands, no errors)")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.get_event_loop().run_until_complete(check()))
