#!/usr/bin/env python3
"""Drive the REAL Neovim TUI through a PTY and emulate the terminal with pyte.

This is the closest reproduction of the user's Ghostty session: the built-in
TUI emits real escape sequences (including scroll regions / line insert-delete
optimisations) that the external-UI msgpack path never exercises.

Compares the incrementally painted terminal against a forced full repaint.
"""
import os, pty, sys, time, select, subprocess, argparse
import pyte

FILE_DEFAULT = "/Users/rafaelricco/Projects/personal/interview-prep/companies/aspenview/rounds/02-technical/study.md"


class Tui:
    def __init__(self, argv, cols=92, rows=30, env=None):
        self.cols, self.rows = cols, rows
        self.screen = pyte.Screen(cols, rows)
        self.stream = pyte.ByteStream(self.screen)
        e = dict(os.environ)
        e.update({"TERM": "xterm-256color", "COLORTERM": "truecolor", "LINES": str(rows), "COLUMNS": str(cols)})
        if env:
            e.update(env)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ.clear(); os.environ.update(e)
            os.execvp(argv[0], argv)
        import fcntl, termios, struct
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def pump(self, seconds=0.35):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    return
                if data:
                    self.stream.feed(data)

    def send(self, data):
        os.write(self.fd, data.encode() if isinstance(data, str) else data)

    def display(self):
        return [line.rstrip() for line in self.screen.display]

    def close(self):
        try:
            os.write(self.fd, b"\x1b:qa!\r")
            time.sleep(0.4)
        except Exception:
            pass
        try:
            os.kill(self.pid, 9)
        except Exception:
            pass


def dups(rows):
    return [(i, rows[i]) for i in range(1, len(rows)) if rows[i].strip() and rows[i] == rows[i - 1]]


def run_case(t, label, keys, setup_cmd=None, per_key=0.09):
    if setup_cmd:
        t.send(setup_cmd); t.pump(0.5)
    t.send("\x1b"); t.pump(0.2)
    t.send(":1\r"); t.pump(0.3)
    t.send("\x0c")           # <C-l> = full redraw, clean baseline
    t.pump(0.6)
    for k in keys:
        t.send(k)
        t.pump(per_key)
    t.pump(0.5)
    got = t.display()
    t.send("\x1b"); t.pump(0.15)
    t.send("\x0c")           # full repaint = ground truth
    t.pump(0.7)
    want = t.display()
    bad = [(i, want[i], got[i]) for i in range(len(got)) if got[i] != want[i]]
    d = dups(got)
    print(f"\n===== {label} =====")
    if not bad and not d:
        print("  OK")
    if d:
        print(f"  !! {len(d)} DUPLICATED adjacent row(s) on the terminal:")
        for i, r in d[:8]:
            print(f"      row {i:2d}: {r[:84]!r}")
    if bad:
        print(f"  {len(bad)} row(s) differ from a full repaint:")
        for i, w, g in bad[:12]:
            print(f"   row {i:2d}")
            print(f"     after redraw : {w[:84]!r}")
            print(f"     on terminal  : {g[:84]!r}")
    return bad, d


ap = argparse.ArgumentParser()
ap.add_argument("--file", default=FILE_DEFAULT)
ap.add_argument("--clean", action="store_true", help="minimal config instead of the user's")
ap.add_argument("--cols", type=int, default=92)
ap.add_argument("--rows", type=int, default=30)


def main():
    a = ap.parse_args()

    if a.clean:
        init = "/tmp/preview_tui_init.lua"
        with open(init, "w") as f:
            f.write("""
vim.opt.rtp:prepend('/Users/rafaelricco/Projects/personal/preview.nvim')
vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.showmode = false
vim.o.ruler = false
vim.o.wrap = true
vim.o.scrolloff = 8
vim.cmd('filetype plugin indent on')
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
  vim.bo.filetype = 'markdown'
  require('preview').setup({ default_mode = 'preview' })
end })
""")
        argv = ["nvim", "-u", init, a.file]
    else:
        argv = ["nvim", a.file]

    t = Tui(argv, cols=a.cols, rows=a.rows)
    t.pump(7.0 if not a.clean else 3.0)

    # Turn preview on via the real command.
    t.send(":Preview preview\r")
    t.pump(1.5)
    print("first screen after enabling preview:")
    for i, r in enumerate(t.display()[:12]):
        print(f"  {i:2d}|{r}")

    cases = [
        ("v + j x10",            [":14\r", "v"] + ["j"] * 10),
        ("v + j x10 FAST",       [":14\r", "v"] + ["j"] * 10),
        ("V + j x10",            [":14\r", "V"] + ["j"] * 10),
        ("v + l x70 (wrap)",     [":16\r", "v"] + ["l"] * 70),
        ("j x30 across code",    [":1\r"] + ["j"] * 30),
        ("<C-e> x12",            [":1\r"] + ["\x05"] * 12),
        ("<C-d> x4",             [":1\r"] + ["\x04"] * 4),
        ("v + G",                [":14\r", "v", "G"]),
    ]

    any_bad = False
    for label, keys in cases:
        per = 0.02 if "FAST" in label else 0.09
        bad, d = run_case(t, label, keys, per_key=per)
        any_bad = any_bad or bool(bad or d)

    if not any_bad:
        print("\nNO ARTIFACT under the TUI in this matrix")
    t.close()


if __name__ == "__main__":
    main()
