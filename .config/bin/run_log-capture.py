"""run_log-capture — run_log's capture engine. Runs a command with stdout and stderr each on
its own pty (or its own pipe, when run_log's matching fd is not a terminal), so the command
sees exactly the isatty() answers it would see without run_log. Both streams are echoed to
the terminal and captured:

    <capture-dir>/<N>.fd        fd N, byte-for-byte as the command wrote it
    <capture-dir>/<N>.fd.plain  fd N as the user saw it: escapes stripped, \\r redraws resolved
    <capture-dir>/stdout, stderr, stdout.plain, stderr.plain
                                symlinks to 1.fd, 2.fd, 1.fd.plain, 2.fd.plain

Every <N>.fd in the capture dir gets a .plain copy, so run_log's --fd N files
(opened by run_log itself) are covered too.

stdin is inherited untouched, so prompts, YubiKey taps and /dev/tty reads behave as in a bare
terminal. Terminal queries (colour, device attributes, cursor position) are captured but not
echoed: the terminal's reply would land in the shell's input after the command exits, as stray
typed text on the prompt. Called by run_log; not meant to be run directly.

Usage: python3 -I run_log-capture.py <capture-dir> <command> [args...]
Exit status: the command's, or 128 + the signal number that killed it.
"""

import errno
import fcntl
import glob
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
CAPTURE_SUFFIX = ".fd"
PLAIN_SUFFIX = ".plain"

# OSC first: its introducer (ESC ]) also matches the two-byte escape class.
ESCAPE_RE = re.compile(
    rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC: titles, hyperlinks
    rb"|\x1b\[[0-?]*[ -/]*[@-~]"  # CSI: colors, cursor moves, erase
    rb"|\x1b[()*+][0-9A-Za-z]"  # charset designation
    rb"|\x1b[@-Z\\-_]"  # remaining two-byte escapes
)


# Sequences that make the terminal type a reply into the tty. Dropped from the echo only.
QUERY_RE = re.compile(
    rb"\x1b\]\d+(?:;\d+)*;\?(?:\x07|\x1b\\)"  # OSC colour queries: 4;N;? 10;? 11;? 12;?
    rb"|\x1b\[[>=]?0?c"  # device attributes DA1/DA2/DA3
    rb"|\x1b\[\??[56]n"  # status and cursor-position reports
    rb"|\x1b\[\?[\d;]*\$p"  # mode reports (DECRQM)
    rb"|\x1b\[>0?q"  # terminal version (XTVERSION)
    rb"|\x1b\[\?u"  # keyboard protocol query
    rb"|\x1b\[1[468]t"  # window and cell size reports
    rb"|\x1bP\+q[0-9A-Fa-f;]*\x1b\\"  # termcap queries (XTGETTCAP)
)
# An escape cut off at the end of a read: held until the next read completes it.
PARTIAL_ESCAPE_RE = re.compile(rb"\x1b(?:\][^\x07\x1b]*\x1b?|P[^\x1b]*\x1b?|\[[0-?]*[ -/]*)?\Z")


class Stream:
    def __init__(self, real_fd, alias, capture_dir):
        self.real_fd = real_fd
        file_name = f"{real_fd}{CAPTURE_SUFFIX}"
        self.path = os.path.join(capture_dir, file_name)
        link_named(capture_dir, alias, file_name)
        link_named(capture_dir, alias + PLAIN_SUFFIX, file_name + PLAIN_SUFFIX)
        self.is_tty = os.isatty(real_fd)
        self.echo_open = True
        self.pending = b""
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

    def echo(self, chunk, final=False):
        """Writes to the real fd minus terminal queries; a closed reader (run_log | head) stops
        the echo, not the capture."""
        data = self.pending + chunk
        self.pending = b""
        if not final:
            partial = PARTIAL_ESCAPE_RE.search(data)
            if partial:
                data, self.pending = data[: partial.start()], data[partial.start() :]
        view = memoryview(QUERY_RE.sub(b"", data))
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


def link_named(capture_dir, alias, target):
    """Relative symlink, so a moved or copied capture dir keeps working."""
    os.symlink(target, os.path.join(capture_dir, alias))


def plain_text(raw):
    text = ESCAPE_RE.sub(b"", raw)
    lines = text.split(b"\n")
    # A progress bar redraws with \r: the user sees only what follows the last one. A trailing
    # \r (CRLF) is a line ending, not a redraw.
    return b"\n".join(line.rstrip(b"\r").rsplit(b"\r", 1)[-1] for line in lines)


def write_plain_copies(capture_dir):
    for path in glob.glob(os.path.join(glob.escape(capture_dir), "*" + CAPTURE_SUFFIX)):
        with open(path, "rb") as src:
            raw = src.read()
        with open(path + PLAIN_SUFFIX, "wb") as dst:
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
                stream.echo(b"", final=True)
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
        write_plain_copies(capture_dir)
    return 128 - rc if rc < 0 else rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
