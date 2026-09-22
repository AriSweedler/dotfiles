---
name: ari-hemingway--structure-ciechanowski
description: "Produce one linear, toy-to-real interactive explainer in the style of Bartosz Ciechanowski (ciechanow.ski): sections are a scaffold's subsystems in assembly order, every definition row becomes a concept with one key insight and one show-not-tell figure, prose is written last, and the table becomes a collapsed glossary cross-linked with first uses. Emits an article directory (HTML + JSON figure specs) for the explainers runtime, validated by its CLI and previewed on localhost. Use to teach a system a reader must understand in order, not to look things up."
---

# Ciechanowski Explainer

Produce one long-form interactive explainer, read in order, that builds a system from its simplest mechanism to the whole: the form of Bartosz Ciechanowski's [GPS](https://ciechanow.ski/gps/), [Internal Combustion Engine](https://ciechanow.ski/internal-combustion-engine/), [Moon](https://ciechanow.ski/moon/) and [Earth and Sun](https://ciechanow.ski/earth-and-sun/). The skeleton is a scaffold's subsystem DAG; the concepts are its definition rows; each concept gets one key insight and one figure that shows it; the explanation is written last, in the table's vocabulary. Output is an article directory in the explainers repo.

Formatting rules and the HTML dialect: see `/ari-hemingway--format-explainer`. Workflow patterns (investigation folder, restore context, drafting, fact-check, present/output): see `/ari-hemingway--lib`. Vocabulary and figure-spec schema: `DESIGN.md` in the explainers repo, never a copy here. If any rule here appears to contradict `/ari-hemingway--format-explainer`, the format skill wins.

## Document structure

One `articles/<slug>/index.html` from `template/article.html`, in this order:

1. Title: the subject noun (`GPS`, `The Hebrew Calendar`). No subtitle, no `[🤖 AI generated]` prefix in the `<h1>`; the marker goes in `<meta name="generator">` and the footer.
2. Opening: three sentences (why it matters, why it is opaque, what the article will do), then the hero figure: the whole finished system, before any explanation.
3. One `<section>` per subsystem, in assembly order, headed by the subsystem's noun. Inside, one block per concept, in table order: setup prose, the figure with a caption that names its controls, prose that points at figure state, the implication, then a transition that carries a fact about what was built and what it unlocks.
4. `Further Watching and Reading`: three to six annotated `rel="external"` links.
5. `Final Words`: one short paragraph.
6. The glossary: the accepted definitions table as a collapsed `<details id="glossary">`, one row per term, each row linking back to the term's first use.
7. Footer: `🤖🌸 Generated with Claude Code with the ari-hemingway skill`.

## Rules

### Concepts, insights, figures

- A concept is one row of the accepted definitions table. Every row is a concept; no concept exists outside the table. New jargon in prose sends you back to the scaffold to add a row.
- Every concept gets exactly one key insight: one sentence, at most 25 words, that a reader could repeat to explain the concept. It may lean only on earlier concepts; `check_definitions_order.zsh` on the insights list, in table order, enforces this mechanically.
- Every concept gets exactly one figure whose job is to show the key insight without telling it. Figures are counted per concept, never per word. A figure is static (Mermaid through `/ari-diagram-mermaid`) when nothing in it needs to move; otherwise it is an interactive JSON figure spec in the runtime's vocabulary. The skill writes HTML and JSON, never JavaScript.
- A figure spec has three keys that mirror the concept: `shows` (layers and readouts), `manipulates` (controls), `notice` (ordered named states the reader steps through, and the layer ids the prose will point at). Every spec passes `node tools/explainers.cjs validate` and `states` before any prose is written around it.
- Sections are the scaffold's cluster communities, named by their noun, ordered by the table position of their first row. Within a section, concepts follow table order. Universal rows belong to the section of the next hoisted row after them.

### Prose

- Written last, after every insight and figure is accepted. Kernighan & Ritchie: terse, present tense, active voice, one idea per sentence, no sentence over 30 words, paragraphs of at most six sentences on one topic. `we` builds ("let's add a second satellite"), `you` operates the figure ("drag the slider"). Transitions state a fact, never what the article does next; the one allowed exception is a flagged simplification ("For now we ignore X; that is the last section."). Glossary terms keep the table's spelling everywhere in prose, and the prose never coins a synonym for one ("leap year" for a 13-month year).
- The figure's caption names its controls in the imperative ("Drag the slider or press play; the inset magnifies the ray tips.") and carries the not-to-scale caveat; the prose never repeats the caption. The prose after a figure points at figure state through `data-ref` spans ("the red arc"), never through words the figure does not show, in sentences of one idea each.
- Hiding information in a figure hides it in the prose. A `data-ref` to a layer the reader has switched off renders plain, so a sentence never depends on the highlight to be understood, and refs to an optional layer live in the sentences about that option ("with the Sun direction shown, the orange arrow...").
- Terms are defined at the point of need, once, by apposition in the same sentence, with the first-use markup; later uses carry the term link. The glossary `<dd>` is the only copy of the definition.
- Every simplification is flagged in the sentence that makes it ("for now we ignore the postponement rules") and repaid in a named later section.
- Math appears only after the figure that motivates it; formulas show their variables and skip derivations. Numbers come in two forms when both help ("29.530589 days, or 29 days 12 hours 44 minutes").
- Scale is the reference's: 5,000 to 18,000 words and 20 to 70 figures for a full article; a first article may be 2,000 to 3,000 words and 8 to 10 figures. The concept count sets the figure count, so scale is chosen by choosing the scaffold's table size, not by trimming figures.

### Toolchain gates

- The explainers repo path is a pointer, default `$HOME/Desktop/workspace/explainers`. Its `DESIGN.md` is the vocabulary (`node tools/explainers.cjs vocab` and `errors` print the same tables); its `tools/explainers.cjs` is the only judge of validity. Never publish an article the CLI has not passed.
- Before Present, all four commands pass on the article: `validate`, `states`, `build`, `budget`.
- Preview runs on localhost with `python3 -m http.server` from the repo root; a headless screenshot of the article and of one figure in each state goes into the investigation folder.

## Investigation folder

Root path: `/tmp/hemingway/ciechanowski/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence follow `/ari-hemingway--lib`. Additional files:

```
scaffold/                 # copied from the scaffold folder: definitions_final.json, clusters.json, definitions_pass1.json, sources.md
skeleton.md               # TOC: sections in assembly order, concepts per section, accepted by the user
insights.json             # {rows:[{term, definition:<key insight>, doc_url}]} in table order; passes check_definitions_order
figures/<concept-slug>.json    # one figure spec per concept (interactive) or .mmd + sidecars (static)
article/index.html        # the draft, built in place by the CLI
preview/*.png             # headless screenshots
```

Scratchpad fields appended after `Last phase`:
```
- **Scaffold**: <path of the scaffold investigation folder> (<n> rows, <k> sections)
- **Repo**: <explainers repo path> @ <git short sha>
- **Scale**: full | first-article
- **Palette**: <token=hex, ...> (≤6)
- **Figures**: <n> interactive, <m> static; validate/states/build/budget: pass|fail
- **Article**: articles/<slug>/index.html (<words> words, <figures> figures)
```

## Workflow

### Gather pointers

Collect the topic, the scaffold investigation folder (or nothing, to run one), the explainers repo path, the article slug, the scale, and the palette. Derive `{topic-slug}` and create the investigation folder per `/ari-hemingway--lib` with `--skill-name ciechanowski`. Write the initial scratchpad.

### Restore context

Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Acquire the skeleton

If no scaffold folder was given, invoke `/ari-hemingway--structure-scaffold` in Skeleton mode; it stops after its Cluster step and prints its folder. Copy `definitions_final.json`, `clusters.json`, `definitions_pass1.json` and `sources.md` into `scaffold/`. Run the mechanical check on `definitions_final.json`; a failing table is the scaffold's problem, not this skill's.

Print: `Acquire complete — {n} rows, {k} communities. Next: Skeleton.`

### Skeleton

Assign every table row to a section: a hoisted row to its community; a universal row to the community of the next hoisted row after it in table order. Order the sections by the table position of their first row: the accepted table is already in dependency order, while `cross_edges` in `clusters.json` run both ways between real subsystems and cannot order them. A foundational row that the cluster step hoisted into a late community (a `Day` term merged into a year-shape community) belongs to every section; re-run the cluster step with `--universal "<term>"` rather than hand-moving it. Write `skeleton.md`: one `##` per section with its concepts in table order. Present it and wait; apply changes by editing `skeleton.md` or re-running the cluster step, never by hand-moving table rows.

Print: `Skeleton complete — {k} sections, {n} concepts. Next: Insights.`

### Key insights

One agent per section writes one insight per concept from the row, `definitions_pass1.json` and `sources.md`. Write `insights.json` in table order and run:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <folder>/insights.json
```

Fix every violation. Present the insights as a two-column table (concept, insight) and wait.

Print: `Insights complete — {n} insights, 0 violations. Next: Figures.`

### Figures

For each concept, decide static or interactive, then write the figure. Static: write the `.mmd` and bake it per `/ari-diagram-mermaid` (`ink_url` and `live_url`), embed per `/ari-hemingway--format-explainer`. Interactive: write `figures/<concept-slug>.json` against `DESIGN.md`, with `notice.states` covering the insight and `notice.point_at` listing every layer the prose will reference. One agent per section; each agent runs the validator on a scratch article that mounts only its figures and iterates until clean:

```zsh
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs validate <folder>/article/index.html
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs states <folder>/article/index.html
```

Present the figure list (concept, kind, controls, states) and wait.

Print: `Figures complete — {n} interactive, {m} static, 0 validator errors. Next: Prose.`

### Prose

Write the article from `template/article.html`: opening and hero figure, then each section from its insights and figures, then Further Watching and Reading, Final Words, the glossary generated from `definitions_final.json`, the footer. Follow `Drafting` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`: overwrite `article/index.html` whole each iteration. Then build and gate:

```zsh
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs build <folder>/article/index.html
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs validate <folder>/article/index.html
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs states <folder>/article/index.html
node $HOME/Desktop/workspace/explainers/tools/explainers.cjs budget <folder>/article/index.html --budget 170k
```

Review against three criteria: (a) jargon outside the table, (b) prose that describes something no figure shows, (c) claims not grounded in `sources.md`. Fix and re-gate.

Print: `Prose complete — {words} words, {figures} figures, 4 gates green. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Every number in prose, every readout format string, and every constant in a figure spec is a claim; the doc URLs in the table are the sources. The 20% `[TODO: verify]` gate applies.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Preview.`

### Preview

Copy `article/` to `articles/<slug>/` in the repo, serve the repo root on localhost, open the article headlessly, and save screenshots of the page and of each figure's first and last state into `preview/`. Look at them. A figure that renders blank, overflows, or hides its controls is a bug in the spec, fixed before Present.

Print: `Preview complete — {n} screenshots at {folder}/preview. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, listing `articles/<slug>/index.html` in the repo and the preview folder. Option 1 reads `Finalize — commit the article to the explainers repo`.

### Output

The article already lives in the repo. Show `git status` and the diff summary, then commit on confirmation with a message naming the article and its figure count. Publishing to the hosted site is a later sibling; until it exists, the local preview is the destination.

Print: `Output complete — articles/<slug>/index.html, {words} words, {figures} figures, committed {sha}.`
