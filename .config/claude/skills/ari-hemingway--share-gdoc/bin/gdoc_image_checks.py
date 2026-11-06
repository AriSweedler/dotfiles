"""Image findings and shared patterns for gdoc_finish.zsh, so the shell and gdoc_asides.py judge images
and Drive links by the same code (gdoc_api.py).

  --doc-json FILE   a documents.get reply (main tab): one JSON line per inline image on stdout, the
                    fields of gdoc_api.image_findings
  --constant NAME   print one shared pattern: image-link-prefix | drive-link-pattern
"""
import argparse
import json
from pathlib import Path

from skill_log import die
from gdoc_api import DRIVE_LINK_PATTERN, IMAGE_LINK_PREFIX, image_findings

CONSTANTS = {"image-link-prefix": IMAGE_LINK_PREFIX, "drive-link-pattern": DRIVE_LINK_PATTERN}


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--doc-json", type=Path, help="documents.get reply to check")
    parser.add_argument("--constant", choices=sorted(CONSTANTS), help="print one shared pattern")
    args = parser.parse_args()
    if bool(args.doc_json) == bool(args.constant):
        die(f"give exactly one of --doc-json and --constant | doc_json='{args.doc_json}' constant='{args.constant}'")
    return args


def main():
    args = parse_args()
    if args.constant:
        print(CONSTANTS[args.constant])
        return
    if not args.doc_json.is_file():
        die(f"doc json not found | path='{args.doc_json}'")
    doc = json.loads(args.doc_json.read_text(encoding="utf-8"))
    for finding in image_findings(doc):
        print(json.dumps(finding, ensure_ascii=False))


if __name__ == "__main__":
    main()
