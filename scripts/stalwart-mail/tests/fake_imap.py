"""A tiny in-memory stand-in for imaplib.IMAP4_SSL, enough for the server code."""

import re


class FakeImap:
    def __init__(self, folders=None, uidvalidity=7):
        # folders: name -> {uid: raw bytes}
        self.folders = folders if folders is not None else {"INBOX": {}, "Drafts": {}}
        self.flags = {}  # (folder, uid) -> flag string
        self.uv = uidvalidity
        self.selected = None
        self.readonly = None
        self.calls = []
        self.appended = []
        self.logged_out = False

    def list(self):
        out = []
        for n in self.folders:
            special = " \\Drafts" if n == "Drafts" else ""
            out.append(f'(\\HasNoChildren{special}) "/" "{n}"'.encode())
        return "OK", out

    def select(self, mailbox, readonly=False):
        self.calls.append(("select", mailbox, readonly))
        name = mailbox.strip('"')
        if name not in self.folders:
            return "NO", [b"no such mailbox"]
        self.selected, self.readonly = name, readonly
        return "OK", [b"1"]

    def response(self, code):
        return code, [str(self.uv).encode()]

    def uid(self, cmd, *args):
        self.calls.append(("uid", cmd) + args)
        box = self.folders[self.selected]
        if cmd == "SEARCH":
            return "OK", [" ".join(str(u) for u in sorted(box)).encode()]
        if cmd == "FETCH":
            uids = [int(x) for x in args[0].split(",")]
            what = args[1]
            out = []
            for u in uids:
                if u not in box:
                    continue
                raw = box[u]
                head, _, _ = raw.partition(b"\r\n\r\n")
                fl = self.flags.get((self.selected, u), "\\Seen")
                if "RFC822.SIZE" in what:
                    out.append(f"{u} (UID {u} RFC822.SIZE {len(raw)} FLAGS ({fl}))".encode())
                elif "HEADER.FIELDS" in what:
                    want = re.search(r"HEADER\.FIELDS \(([^)]*)\)", what).group(1).split()
                    lines = []
                    for ln in head.decode().split("\r\n"):
                        if ln.split(":")[0].upper() in want:
                            lines.append(ln)
                    blob = ("\r\n".join(lines) + "\r\n\r\n").encode()
                    out.append((f"{u} (UID {u} FLAGS ({fl}) BODY[HEADER.FIELDS ({' '.join(want)})] {{{len(blob)}}}".encode(), blob))
                    out.append(b")")
                else:
                    out.append((f"{u} (UID {u} BODY[] {{{len(raw)}}}".encode(), raw))
                    out.append(b")")
            return "OK", out
        if cmd == "STORE":
            self.flags[(self.selected, int(args[0]))] = args[2]
            return "OK", [b"ok"]
        if cmd == "EXPUNGE":
            self.folders[self.selected].pop(int(args[0]), None)
            return "OK", [b"ok"]
        return "BAD", [b"unknown"]

    def append(self, mailbox, flags, date, message):
        self.calls.append(("append", mailbox, flags))
        self.appended.append((mailbox, flags, message))
        name = mailbox.strip('"')
        box = self.folders[name]
        box[max(box, default=0) + 1] = message.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        return "OK", [b"done"]

    def logout(self):
        self.logged_out = True
        return "BYE", [b""]
