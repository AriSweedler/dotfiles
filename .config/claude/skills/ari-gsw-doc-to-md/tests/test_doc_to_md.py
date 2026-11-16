#!/usr/bin/env python3
"""bin/doc_to_md.py against hand-built Docs JSON, no network.

Golden files: fixtures/doc.json renders to fixtures/doc.md (the reading dialect) and fixtures/doc.publish.md
(--publish). The fixture holds every element the converter knows: title and headings, bold, italic,
monospace, runs split inside one link, a Drive link, a rich link chip, a person, a date, an ordered list with
a nested bullet, a second list, a table with a pipe, a two-paragraph cell and a short row, a diagram linked to
mermaid.live, and a horizontal rule. A change to the output fails here; when the change is intended,
regenerate with --regen and read the diff.

Units: doc id and tab parsing, tab selection (the sole tab, a named tab, a nested child tab, a multi-tab doc
with none named, an unknown tab), the mermaid.ink round trip, and the output path rules.
Run: python3 tests/test_doc_to_md.py [--regen]"""
import base64
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
LIB = SKILL.parent / "ari-skill-pythonscripts" / "lib"
CONVERTER = SKILL / "bin" / "doc_to_md.py"
FIXTURES = HERE / "fixtures"
sys.path.insert(0, str(LIB))
spec = importlib.util.spec_from_file_location("doc_to_md", CONVERTER)
assert spec and spec.loader
d2m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d2m)


def convert(*args):
    """Run the converter as the entrypoint does, with the shared lib on PYTHONPATH."""
    env = {"PYTHONPATH": str(LIB), "PATH": "/usr/bin:/bin", "NO_COLOR": "1"}
    return subprocess.run([sys.executable, str(CONVERTER), *args], capture_output=True, text=True, env=env)


def dies(fn, *args):
    """The message a die() call logs, or None when fn returns."""
    err = io.StringIO()
    with redirect_stderr(err):
        try:
            fn(*args)
        except SystemExit:
            return err.getvalue()
    return None


class GoldenTest(unittest.TestCase):
    def check(self, golden, *flags):
        result = convert("--json-file", str(FIXTURES / "doc.json"), "--stdout", *flags)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, (FIXTURES / golden).read_text(encoding="utf-8"),
                         f"output differs from {golden}; if intended: python3 {Path(__file__).name} --regen")
        return result

    def test_reading_dialect(self) -> None:
        self.check("doc.md")

    def test_publish_dialect(self) -> None:
        result = self.check("doc.publish.md", "--publish")
        self.assertIn("dropped anchor text for a Drive URL | text='a Drive file'", result.stderr)

    def test_publish_never_leaks_the_expiring_image_uri(self) -> None:
        self.assertNotIn("googleusercontent", (FIXTURES / "doc.publish.md").read_text(encoding="utf-8"))


class UnitTest(unittest.TestCase):
    def test_doc_ids(self) -> None:
        for source in ("https://docs.google.com/document/d/1AbC_def-123/edit?tab=t.0", "https://drive.google.com/file/d/1AbC_def-123/view",
                       "https://drive.google.com/open?id=1AbC_def-123", "1AbC_def-123xxxxxxxxxxxx"):
            want = "1AbC_def-123xxxxxxxxxxxx" if not source.startswith("https") else "1AbC_def-123"
            self.assertEqual(d2m.resolve_doc_id(source), want, source)
        self.assertIn("not a Google Doc URL or id", dies(d2m.resolve_doc_id, "short") or "")

    def test_tab_from_url_and_flag(self) -> None:
        class Args:
            tab = None
            source = "https://docs.google.com/document/d/x/edit?tab=t.abc"
        self.assertEqual(d2m.resolve_requested_tab_id(Args), "t.abc")
        Args.tab = "t.flag"
        self.assertEqual(d2m.resolve_requested_tab_id(Args), "t.flag", "--tab wins over the URL")

    def test_tab_selection(self) -> None:
        one = json.loads((FIXTURES / "doc.json").read_text(encoding="utf-8"))
        two = json.loads((FIXTURES / "two-tabs.json").read_text(encoding="utf-8"))
        md, tab_title = d2m.render_doc(one, None, False)
        self.assertTrue(md.startswith("# Request flow"))
        self.assertIsNone(tab_title, "a sole tab adds no filename suffix")
        self.assertIn("multiple tabs", dies(d2m.render_doc, two, None, False) or "")
        md, tab_title = d2m.render_doc(two, "t.2", False)
        self.assertEqual((md, tab_title), ("Child body\n", "Child"), "a child tab is found depth-first")
        self.assertIn("tab not found | tab_id='t.9' available='t.0, t.1, t.2'", dies(d2m.render_doc, two, "t.9", False) or "")
        legacy = {"title": "Old", "body": one["tabs"][0]["documentTab"]["body"], "lists": one["tabs"][0]["documentTab"]["lists"]}
        self.assertTrue(d2m.render_doc(legacy, None, False)[0].startswith("# Request flow"), "a tabless doc renders its body")

    def test_mermaid_ink_round_trip(self) -> None:
        state = {"code": "graph TD; A-->B", "mermaid": "{}"}
        pako = base64.urlsafe_b64encode(zlib.compress(json.dumps(state).encode())).decode().rstrip("=")
        ink = d2m.mermaid_ink_url(f"https://mermaid.live/edit#pako:{pako}")
        self.assertIsNotNone(ink)
        payload = ink.removeprefix(d2m.MERMAID_INK_PREFIX)
        self.assertEqual(json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))), state)
        with redirect_stderr(io.StringIO()):
            self.assertIsNone(d2m.mermaid_ink_url("https://mermaid.live/view#pako:not-zlib"))
            self.assertIsNone(d2m.mermaid_ink_url("https://example.com/x.png"))

    def test_output_paths(self) -> None:
        self.assertEqual(d2m.default_filename("[🤖 AI generated] Request flow", None), "ai-generated-request-flow.md")
        self.assertEqual(d2m.default_filename("Doc", "Aside 1: Notes"), "doc__aside-1-notes.md")
        self.assertEqual(d2m.default_filename("🤖", None), "google-doc.md", "a title with no letters still names a file")
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(d2m.resolve_out_path(tmp, "Doc", None), Path(tmp) / "doc.md", "--out a directory")
            self.assertEqual(d2m.resolve_out_path(f"{tmp}/x.md", "Doc", None), Path(tmp) / "x.md", "--out a file")

    def test_an_existing_output_is_kept_without_force(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out.md"
            out.write_text("mine", encoding="utf-8")
            result = convert("--json-file", str(FIXTURES / "doc.json"), "--out", str(out))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(out.read_text(encoding="utf-8"), "mine")
            result = convert("--json-file", str(FIXTURES / "doc.json"), "--out", str(out), "--force")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(out.read_text(encoding="utf-8").startswith("# Request flow"))


def regen() -> None:
    for golden, flags in (("doc.md", []), ("doc.publish.md", ["--publish"])):
        result = convert("--json-file", str(FIXTURES / "doc.json"), "--stdout", *flags)
        result.check_returncode()
        (FIXTURES / golden).write_text(result.stdout, encoding="utf-8")
        print(f"wrote {FIXTURES / golden}")


if __name__ == "__main__":
    if "--regen" in sys.argv:
        regen()
    else:
        unittest.main()
