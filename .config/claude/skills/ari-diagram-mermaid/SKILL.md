---
name: ari-diagram-mermaid
description: Create, validate, and share Mermaid.js diagrams in Airtable brand colors that stay legible under any viewer theme. `bake` pins the theme in the source, refuses low-contrast text, and mints the mermaid.ink image plus mermaid.live view link for Google Docs and GitHub.
---

# ari-diagram-mermaid

Create, validate, and share Mermaid.js diagrams with Airtable brand colors that stay legible whatever theme the viewer's mermaid.live applies. `bake` refuses a source whose text can vanish into its fill, then copies a ready-to-paste markdown link to the clipboard for embedding in Google Docs.

## Rules

- **Never hand-reproduce the baked link.** `bake` prints the link, copies it to the clipboard, and writes a `.url` sidecar. You MAY print or relay the link — but only verbatim from `bake`'s output or the sidecar file. NEVER retype, transcribe, reconstruct, or regenerate it yourself: it's a long base64 string, slow and error-prone to reproduce when the script already emitted the exact bytes. Never copy a link from the mermaid.live address bar either: the editor re-encodes its own theme into the URL (a dark-mode tab turns `theme: default` into `redux-dark-color`), so that link renders differently from the baked one. Simplest path: tell the user it's on the clipboard.
- **Default output is `markdown_link`.** Override the format only when the user explicitly asks for another form (e.g. a GitHub-native fenced block), or when a Google Doc pipeline needs the sidecars: bake `ink_url` and `live_url` on the same `.mmd` and let the caller compose `[![alt](<ink_url>?width=620)](<live_url>)`. mermaid.ink honors `?width=` (and `?height=`, `?scale=`); 620 px is 465 pt, inside a Letter page's 468 pt text width. Drive's markdown import turns that form into an inline image whose link opens the diagram fullscreen on mermaid.live (`/view#`, never `/edit#`: the reader gets the diagram, not the editor).
- **Contrast is pinned in the source, never left to the viewer.** Line 1 of every diagram is `%%{init: {'theme':'default'}}%%`: the directive travels inside the code, so it beats whatever theme a viewer's editor writes into the URL config. Every `classDef` or `style` that sets `fill` also sets `color`, at a contrast ratio of at least 3:1 (WCAG AA for bold text); a subgraph `style` with a light fill takes `color:#333`. Text you did not color (edge labels, un-classed nodes, subgraph titles) inherits the pinned theme's dark-on-light. `bake` checks the directive and every fill/color pair mechanically and stops on the first source that fails.

## Workflow

1. **Set up the session** — creates a fresh temp folder and prints the `.mmd` path to write to. Emit exactly this one Bash call:
   ```zsh
   zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/init.zsh
   ```
   It prints `diagram_dir=` and `diagram_file=`; write the diagram to `diagram_file`. Pass `--name NAME` for a custom basename.
2. **Write** the diagram source to the printed `diagram_file`
   - Start with the Airtable color theme block below; its first line pins the theme
   - Apply classes to nodes using `class` directives
   - Style a subgraph as `style ID fill:#F5F5F5,stroke:#666666,color:#333`
3. **Bake**: `zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/bake <diagram_file>`
   - Runs the contrast gate, confirms the render, mints the embed URL, and copies it to the clipboard in one step
   - On a gate failure it lists every offending line as `line|directive|name|fill|color|ratio|reason`; fix the source and re-run until valid
4. **Present** to user:
   - The markdown link is on the clipboard (and printed by `bake`, and in the `url_file` sidecar). Tell the user it's copied.
   - If you surface the link inline, relay it verbatim from `bake`'s output or the sidecar — never retype it (see Rules).
   - For a Google Doc published through `/ari-hemingway--share-gdoc`: bake `ink_url` and `live_url`, then embed `[![alt](<ink_url>?width=620)](<live_url>)`; its finish step fails an image whose link is not the `mermaid.live/view#` form. For a hand-edited Doc: paste the markdown link, or Insert > Image > By URL and add the live link to the image.

## Airtable Color Theme (always include)

```mermaid
%%{init: {'theme': 'default'}}%%
classDef blue fill:#2D7FF9,stroke:#1A5BC4,color:#fff,stroke-width:2px,font-weight:bold
classDef teal fill:#20D9D2,stroke:#179B96,color:#333,stroke-width:2px,font-weight:bold
classDef green fill:#20C933,stroke:#168E24,color:#333,stroke-width:2px,font-weight:bold
classDef yellow fill:#FCB400,stroke:#B88000,color:#333,stroke-width:2px,font-weight:bold
classDef orange fill:#FF6F2C,stroke:#CC5823,color:#333,stroke-width:2px,font-weight:bold
classDef red fill:#F82B60,stroke:#C42249,color:#fff,stroke-width:2px,font-weight:bold
classDef pink fill:#FF08C2,stroke:#CC069B,color:#fff,stroke-width:2px,font-weight:bold
classDef purple fill:#8B46FF,stroke:#6F38CC,color:#fff,stroke-width:2px,font-weight:bold
classDef gray fill:#666666,stroke:#444444,color:#fff,stroke-width:2px,font-weight:bold

linkStyle default stroke-width:2px
```

Every pair clears 3:1. White on blue 3.8, red 3.8, pink 3.5, purple 4.8, gray 5.7. `#333` on teal 7.2, green 5.7, yellow 7.0, orange 4.6 (white on those four scored 1.8, 2.2, 7.0 and 2.8).

## Contrast

```mermaid
%% GOOD — theme pinned; the subgraph's light fill carries a dark text color
%%{init: {'theme': 'default'}}%%
flowchart LR
    subgraph OAUTH["OAuth 2.0"]
        AS["Authorization server"]
    end
    style OAUTH fill:#F5F5F5,stroke:#666666,color:#333

%% BAD — no theme pin and a fill with no color: a dark-mode viewer paints the title
%% light on the light fill (white on #F5F5F5 is 1.1:1) and it disappears
flowchart LR
    subgraph OAUTH["OAuth 2.0"]
        AS["Authorization server"]
    end
    style OAUTH fill:#F5F5F5,stroke:#666666
```

`bake` rejects the BAD source twice over: `No theme directive`, then `31|style|OAUTH|#F5F5F5|-|-|fill without color`.

## Tools

`bin/init.zsh` — Session setup: creates a fresh `/tmp/ari-diagram-mermaid/<timestamp>/` folder and prints `diagram_dir=` / `diagram_file=` for the workflow. Replaces hand-rolled `mktemp` + `date` (BSD `date` lacks `%3N`).

`bin/bake` — All-in-one: gates the theme pin and contrast, confirms mermaid.ink renders the source, mints the URL, prints it to stdout, and writes a `.url` sidecar next to the `.mmd` (e.g., `diagram.ink_url.url`). Copies to clipboard if available (macOS `pbcopy`, Linux `xclip`/`xsel`; silently skips on headless systems).

| Flag | Meaning |
| --- | --- |
| `--file PATH` | The `.mmd` source. A bare positional path is accepted for older callers. |
| `--format FORMAT` | One of the formats below (default: `markdown_link`). `MERMAID_FORMAT=` in the environment is the fallback. |
| `--validate-only` | Gate and render-check only; mint no URL. `MERMAID_VALIDATE_ONLY=1` is the fallback. |

| Format | Output |
| --- | --- |
| `markdown_link` (default) | Image linked to its source (`[![](img)](view)`), no alt, no width cap |
| `ink_url` | Direct mermaid.ink PNG image URL; append `?width=620` for Docs |
| `live_url` | Fullscreen mermaid.live URL (`/view#pako:`); the link target for a Docs image. Swap `view` for `edit` in the path to open the editor; the payload is identical |

`lib/contrast.awk` — The WCAG check `bake` runs. Standalone: `awk -v min_ratio=3.0 -f $HOME/.claude/skills/ari-diagram-mermaid/lib/contrast.awk <diagram.mmd>` prints one `line|directive|name|fill|color|ratio|reason` record per violation and nothing when clean.

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
