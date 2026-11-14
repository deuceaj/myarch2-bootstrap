#!/usr/bin/env python3
"""Type text into the test VM as keystrokes, through QEMU's QMP socket.

    vm-type.py SOCKET 'text to type' [--enter]

US keyboard layout. Whatever window has focus inside the VM receives the keys.
"""
import json
import socket
import sys
import time

PLAIN = {
    " ": "spc", "-": "minus", "=": "equal", "/": "slash", ".": "dot", ",": "comma",
    ";": "semicolon", "'": "apostrophe", "`": "grave_accent", "[": "bracket_left",
    "]": "bracket_right", "\\": "backslash", "\t": "tab", "\n": "ret",
}
SHIFTED = {
    "_": "minus", "+": "equal", "?": "slash", ">": "dot", "<": "comma", ":": "semicolon",
    '"': "apostrophe", "~": "grave_accent", "{": "bracket_left", "}": "bracket_right",
    "|": "backslash", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
    "&": "7", "*": "8", "(": "9", ")": "0",
}


def keys_for(ch):
    if ch.isascii() and ch.isalpha():
        return (["shift"] if ch.isupper() else []) + [ch.lower()]
    if ch.isdigit():
        return [ch]
    if ch in PLAIN:
        return [PLAIN[ch]]
    if ch in SHIFTED:
        return ["shift", SHIFTED[ch]]
    raise SystemExit(f"can't type character {ch!r}")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    sock_path, text = sys.argv[1], sys.argv[2]
    if "--enter" in sys.argv[3:]:
        text += "\n"
    plan = [keys_for(c) for c in text]          # validate everything before typing

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    f = s.makefile("rw")
    f.readline()                                 # QMP greeting

    def cmd(obj):
        f.write(json.dumps(obj) + "\n")
        f.flush()
        while True:                              # skip async events
            reply = json.loads(f.readline())
            if "return" in reply or "error" in reply:
                if "error" in reply:
                    raise SystemExit(reply["error"])
                return

    cmd({"execute": "qmp_capabilities"})
    for keys in plan:
        cmd({"execute": "send-key",
             "arguments": {"keys": [{"type": "qcode", "data": k} for k in keys]}})
        time.sleep(0.015)
    print(f"typed {len(text)} characters")


main()
