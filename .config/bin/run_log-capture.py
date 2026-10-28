"""run_log-capture — run_log's capture engine. Runs a command with stdout and stderr each on
its own pty (or its own pipe, when run_log's matching fd is not a terminal), so the command
sees exactly the isatty() answers it would see without run_log. Both streams are echoed to
the terminal and captured twice:

    <capture-dir>/stdout        stdout, byte-for-byte as the command wrote it (colors kept)
    <capture-dir>/stderr        stderr, byte-for-byte
    <capture-dir>/stdout.plain  stdout as the user saw it: escapes stripped, \\r redraws resolved
    <capture-dir>/stderr.plain  stderr, likewise

stdin is inherited untouched, so prompts, YubiKey taps and /dev/tty reads behave as in a bare
terminal. Called by run_log; not meant to be run directly.

Usage: python3 -I run_log-capture.py <capture-dir> <command> [args...]
Exit status: the command's, or 128 + the signal number that killed it.
"""

import errno
import fcntl
import os
import re
import select
import signal
import subprocess
import sys
import termios

# A select() timeout doubles as the window-size poll: the command, not this process, usually
# owns the terminal's foreground process group, so SIGWINCH never reaches us.
WINSIZE_POLL_S = 0.25
READ_CHUNK = 65536

# OSC first: its introducer (ESC ]) also matches the two-byte escape class.
ESCAPE_RE = re.compile(
    rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC: titles, hyperlinks
    rb"|\x1b\[[0-?]*[ -/]*[@-~]"  # CSI: colors, cursor moves, erase
    rb"|\x1b[()*+][0-9A-Za-z]"  # charset designation
    rb"|\x1b[@-Z\\-_]"  # remaining two-byte escapes
)


class Stream:
    def __init__(self, real_fd, name, capture_dir):
        self.real_fd = real_fd
        self.name = name
        self.path = os.path.join(capture_dir, name)
        self.is_tty = os.isatty(real_fd)
        self.echo_open = True
        self.winsize = None
        if self.is_tty:
            self.read_fd, self.child_fd = os.openpty()
            attrs = termios.tcgetattr(real_fd)
            # Clear OPOST so the command's bytes reach the capture untranslated (no \n → \r\n);
            # the real terminal still applies its own output processing on echo.
            attrs[1] &= ~termios.OPOST
            termios.tcsetattr(self.child_fd, termios.TCSANOW, attrs)
            self.sync_winsize()
        else:
            self.read_fd, self.child_fd = os.pipe()
        self.capture = open(self.path, "ab", buffering=0)

    def sync_winsize(self):
        if not self.is_tty:
            return
        try:
            size = fcntl.ioctl(self.real_fd, termios.TIOCGWINSZ, b"\0" * 8)
        except OSError:
            return
        if size != self.winsize:
            fcntl.ioctl(self.read_fd, termios.TIOCSWINSZ, size)
            self.winsize = size

    def echo(self, chunk):
        """Writes to the real fd; a closed reader (run_log | head) stops the echo, not the capture."""
        view = memoryview(chunk)
        while self.echo_open and view:
            try:
                view = view[os.write(self.real_fd, view):]
            except BrokenPipeError:
                self.echo_open = False
            except InterruptedError:
                continue

    def read(self):
        """Returns the next chunk, or b"" at end of stream (a pty master reports EOF as EIO)."""
        try:
            return os.read(self.read_fd, READ_CHUNK)
        except OSError as err:
            if err.errno == errno.EIO:
                return b""
            raise


def plain_text(raw):
    text = ESCAPE_RE.sub(b"", raw)
    lines = text.split(b"\n")
    # A progress bar redraws with \r: the user sees only what follows the last one. A trailing
    # \r (CRLF) is a line ending, not a redraw.
    return b"\n".join(line.rstrip(b"\r").rsplit(b"\r", 1)[-1] for line in lines)


def write_plain_copy(stream):
    with open(stream.path, "rb") as src:
        raw = src.read()
    with open(stream.path + ".plain", "wb") as dst:
        dst.write(plain_text(raw))


def pump(streams):
    by_fd = {s.read_fd: s for s in streams}
    while by_fd:
        ready, _, _ = select.select(list(by_fd), [], [], WINSIZE_POLL_S)
        for stream in streams:
            stream.sync_winsize()
        for fd in ready:
            stream = by_fd[fd]
            chunk = stream.read()
            if not chunk:
                del by_fd[fd]
                os.close(fd)
                continue
            stream.capture.write(chunk)
            stream.echo(chunk)


def main(argv):
    if len(argv) < 3:
        print(f"usage: {argv[0]} <capture-dir> <command> [args...]", file=sys.stderr)
        return 2
    capture_dir, command = argv[1], argv[2:]
    streams = [Stream(1, "stdout", capture_dir), Stream(2, "stderr", capture_dir)]

    # close_fds=False keeps run_log's --fd N descriptors; the pty/pipe ends are non-inheritable.
    child = subprocess.Popen(
        command, stdout=streams[0].child_fd, stderr=streams[1].child_fd, close_fds=False
    )
    # Ctrl-C and Ctrl-\ are the command's to handle; this process keeps draining until it exits.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGQUIT, signal.SIG_IGN)
    for stream in streams:
        os.close(stream.child_fd)

    try:
        pump(streams)
    finally:
        rc = child.wait()
        for stream in streams:
            stream.capture.close()
            write_plain_copy(stream)
    return 128 - rc if rc < 0 else rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
