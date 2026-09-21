# ari-diagram-mermaid

Create, validate, and share Mermaid.js diagrams with Airtable brand colors. `bake` copies a ready-to-paste markdown link to the clipboard for embedding in Google Docs.

## Rules

- **Never hand-reproduce the baked link.** `bake` prints the markdown link, copies it to the clipboard, and writes a `.url` sidecar. You MAY print or relay the link — but only verbatim from `bake`'s output or the sidecar file. NEVER retype, transcribe, reconstruct, or regenerate it yourself: it's a long base64 string, slow and error-prone to reproduce when the script already emitted the exact bytes. Simplest path: tell the user it's on the clipboard.
- **Default output is `markdown_link`.** Override `MERMAID_FORMAT` only when the user explicitly asks for another form (e.g. a GitHub-native fenced block), or when a Google Doc pipeline needs the sidecars: bake `ink_url` and `live_url` on the same `.mmd` and let the caller compose `[![alt](<ink_url>?width=620)](<live_url>)`. mermaid.ink honors `?width=` (and `?height=`, `?scale=`); 620 px is 465 pt, inside a Letter page's 468 pt text width. Drive's markdown import turns that form into an inline image whose link opens the diagram fullscreen on mermaid.live (`/view#`, never `/edit#`: the reader gets the diagram, not the editor).

## Workflow

1. **Set up the session** — creates a fresh temp folder and prints the `.mmd` path to write to. Emit exactly this one Bash call:
   ```zsh
   zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/init.zsh
   ```
   It prints `diagram_dir=` and `diagram_file=`; write the diagram to `diagram_file`. Pass `--name NAME` for a custom basename.
2. **Write** the diagram source to the printed `diagram_file`
   - Always include the Airtable color theme classDefs below
   - Apply classes to nodes using `class` directives
3. **Bake**: `zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/bake <diagram_file>`
   - Validates, generates the embed URL, and copies it to clipboard in one step
   - If invalid: read the error, fix the source, re-run (loop until valid)
4. **Present** to user:
   - The markdown link is on the clipboard (and printed by `bake`, and in the `url_file` sidecar). Tell the user it's copied.
   - If you surface the link inline, relay it verbatim from `bake`'s output or the sidecar — never retype it (see Rules).
   - For a Google Doc published through `/ari-hemingway--share-gdoc`: bake `ink_url` and `live_url`, then embed `[![alt](<ink_url>?width=620)](<live_url>)`; its finish step fails an image whose link is not the `mermaid.live/view#` form. For a hand-edited Doc: paste the markdown link, or Insert > Image > By URL and add the live link to the image.

## Airtable Color Theme (always include)

```mermaid
classDef blue fill:#2D7FF9,stroke:#1A5BC4,color:#fff,stroke-width:2px,font-weight:bold
classDef teal fill:#20D9D2,stroke:#179B96,color:#fff,stroke-width:2px,font-weight:bold
classDef green fill:#20C933,stroke:#168E24,color:#fff,stroke-width:2px,font-weight:bold
classDef yellow fill:#FCB400,stroke:#B88000,color:#333,stroke-width:2px,font-weight:bold
classDef orange fill:#FF6F2C,stroke:#CC5823,color:#fff,stroke-width:2px,font-weight:bold
classDef red fill:#F82B60,stroke:#C42249,color:#fff,stroke-width:2px,font-weight:bold
classDef pink fill:#FF08C2,stroke:#CC069B,color:#fff,stroke-width:2px,font-weight:bold
classDef purple fill:#8B46FF,stroke:#6F38CC,color:#fff,stroke-width:2px,font-weight:bold
classDef gray fill:#666666,stroke:#444444,color:#fff,stroke-width:2px,font-weight:bold

linkStyle default stroke-width:2px
```

## Tools

`bin/init.zsh` — Session setup: creates a fresh `/tmp/ari-diagram-mermaid/<timestamp>/` folder and prints `diagram_dir=` / `diagram_file=` for the workflow. Replaces hand-rolled `mktemp` + `date` (BSD `date` lacks `%3N`).

`bin/bake` — All-in-one: validates, generates URL, prints to stdout, and writes a `.url` sidecar file next to the `.mmd` (e.g., `diagram.ink_url.url`). Copies to clipboard if available (macOS `pbcopy`, Linux `xclip`/`xsel`; silently skips on headless systems).

| `MERMAID_FORMAT=`        | Output                                                      |
| ------------------------ | ----------------------------------------------------------- |
| `markdown_link` (default) | Image linked to its source (`[![](img)](view)`), no alt, no width cap |
| `ink_url`                 | Direct mermaid.ink PNG image URL; append `?width=620` for Docs      |
| `live_url`                | Fullscreen mermaid.live URL (`/view#pako:`); the link target for a Docs image. Swap `view` for `edit` in the path to open the editor; the payload is identical |

Set `MERMAID_VALIDATE_ONLY=1` to validate without generating URLs or copying to clipboard.

## Line breaks in node labels

Use `<br/>` for line breaks inside node labels — never use `\n`. The `\n` escape is not rendered as a newline by Mermaid and will appear as literal text.

```mermaid
%% GOOD
A["First line<br/>Second line"]

%% BAD — \n renders literally
A[First line\nSecond line]
```

Node labels that contain `<br/>` must be wrapped in double quotes: `["..."]` or `{"..."}`.

## Notes

- The mermaid.ink URL is a live-rendered PNG — works anywhere images are supported.
- For GitHub comments, use native mermaid fenced blocks instead of the image URL:
  ````
  ```mermaid
  <diagram source>
  ```
  ````
