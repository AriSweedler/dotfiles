---
name: ari-hemingway--structure-ciechanowski
description: "Produce one linear, toy-to-real interactive explainer in the style of Bartosz Ciechanowski (ciechanow.ski): sections are a scaffold's subsystems in assembly order, every definition row becomes a concept with one key insight and one show-not-tell figure, prose is written last, and the table becomes a collapsed glossary cross-linked with first uses. Emits an article directory (HTML + JSON figure specs) for the explainers runtime, validated by its CLI and previewed on localhost. Use to teach a system a reader must understand in order, not to look things up."
---

# Ciechanowski Explainer

Produce one long-form interactive explainer, read in order, that builds a system from its simplest mechanism to the whole: the form of Bartosz Ciechanowski's [GPS](https://ciechanow.ski/gps/), [Internal Combustion Engine](https://ciechanow.ski/internal-combustion-engine/), [Moon](https://ciechanow.ski/moon/) and [Earth and Sun](https://ciechanow.ski/earth-and-sun/). The skeleton is a scaffold's subsystem DAG; the concepts are its definition rows; each concept gets one key insight and one figure that shows it; the explanation is written last, in the table's vocabulary. Output is an article directory in the explainers repo.

Formatting rules and the HTML dialect: see `/ari-hemingway--format-explainer`. Workflow patterns (investigation folder, restore context, drafting, fact-check, present/output): see `/ari-hemingway--lib`. Vocabulary and figure-spec schema: `DESIGN.md` in the explainers repo, never a copy here. If any rule here appears to contradict `/ari-hemingway--format-explainer`, the format skill wins.

## Arguments

`--autonomous` — per `## Autonomous mode` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. This skill's wait points: Skeleton, Key insights, Figures and Figure review (each accepted as presented once its check passes; stuck figures are listed under `Defaults taken`), the Workflow failure menu (resume once, then pause), and the Output commit (a local commit proceeds; the publish gate in `/ari-hemingway--share-explainer` pauses).

## Document structure

One `articles/<slug>/index.html` from `template/article.html`, in this order:

1. Title: the subject noun (`GPS`, `The Hebrew Calendar`). No subtitle, no `[🤖 AI generated]` prefix in the `<h1>`; the marker goes in `<meta name="generator">` and the footer.
2. Opening: three sentences (why it matters, why it is opaque, what the article will do), then the hero figure: the whole finished system, before any explanation.
3. One `<section>` per subsystem, in assembly order, headed by the subsystem's noun. Inside, one block per concept, in table order: setup prose, the figure with a caption that names its controls, prose that points at figure state, the implication, then a transition that carries a fact about what was built and what it unlocks.
4. `Further Watching and Reading`: three to six annotated `rel="external"` links.
5. `Final Words`: one short paragraph.
6. The glossary: the accepted definitions table as a collapsed `<details id="glossary">`, one row per term, each row linking back to the term's first use and to its source; a row with a declared short form shows `Term (short)`.
7. Footer: `🤖🌸 Generated with Claude Code with the ari-hemingway skill`.

## Rules

### Concepts, insights, figures

- A concept is one row of the accepted definitions table. Every row is a concept; no concept exists outside the table. New jargon in prose sends you back to the scaffold to add a row.
- Every concept gets exactly one key insight: one sentence, at most 25 words, that a reader could repeat to explain the concept. It may lean only on earlier concepts; `check_definitions_order.zsh` on the insights list, in table order, enforces this mechanically. Each insight row also carries `shows`: one sentence naming what the figure must draw, the quantity and the control that moves it. `shows` drives the figure plan.
- Every concept gets exactly one figure whose job is to show the key insight without telling it. Figures are counted per concept, never per word. A figure is static (Mermaid through `/ari-diagram-mermaid`) when nothing in it needs to move; otherwise it is an interactive JSON figure spec in the runtime's vocabulary, emitted by a generator (`bin/*_fig.py`, or a bespoke script on `bin/figlib.py`) into `figures/<concept-slug>.json`. The skill writes Python that emits JSON, and HTML, never JavaScript.
- A figure spec has three keys that mirror the concept: `shows` (layers and readouts), `manipulates` (controls), `notice` (ordered named states the reader steps through, and the layer ids the prose will point at). Every spec passes `node tools/explainers.cjs validate` and `states` on a scratch page before any prose is written around it.
- Sections are the scaffold's cluster communities, named by their noun, ordered by the table position of their first hoisted row; a universal row never sets a section's position. The caller may pass an explicit section order instead. Within a section, concepts follow table order. Universal rows belong to the section of the next hoisted row after them.

### Figure design

A figure is a small model of the thing: the reader changes its state and watches the quantity of interest move. The catalog of diagram types, one example spec per type, is `/ari-hemingway--format-explainer` "Diagram types"; this skill chooses from it and never copies it.

- Every figure has a type from the catalog, recorded in `figures/plan.md` before any spec is generated. Two neighbouring concepts never share a shape. A family of concepts that wants one model (five conferences) carries a different quantity each time (members, churn, payout tiers, departures) or becomes one figure with a picker.
- A control moves a drawn quantity: a length, height, position, count or color changes when the reader drags. A control that only swaps captions, recolors a list or reveals a sentence is a paragraph with a switch on it, the list-behind-a-toggle shape, and is rejected at the plan.
- Dollars are lengths: money is drawn to one scale (a bar, a slab, a dot area), never printed as the only evidence, and two amounts the prose compares sit on one axis. Time is a slider that assembles the drawing as it advances; a slider with one step that matters is a toggle in disguise.
- Text layers carry numbers, names and short labels. The insight is never written on the canvas; the stepper caption and the prose carry the words.
- One pill: a figure whose only controls are segmented or toggle sets `notice.steps` to `none` (`figlib.spec` and `assemble.py` do this); a slider figure keeps the stepper and its default equals a declared step.
- `not_to_scale` and `simplified` caveats stay in the spec and the build echoes them; a drawing that is to scale drops the caveat.
- A map of schools names each school on hover: every school dot carries `hover` (the name) and, when badges exist, `logo`.
- A slider only when the values between its ends mean something (a season, a dollar amount, a count). Two states that matter is a toggle; a few named cases is a segmented control or chips; a static chart has no control at all.
- A bracket, flow or wiring diagram is drawn continuous: every connector meets the line it joins. Check the screenshot at the joins before accepting the figure.

### Prose

- Written last, after every insight and figure is accepted. Kernighan & Ritchie: terse, present tense, active voice, one idea per sentence, no sentence over 30 words, paragraphs of at most six sentences on one topic. `we` builds ("let's add a second satellite"), `you` operates the figure ("drag the slider"). Transitions state a fact, never what the article does next; the one allowed exception is a flagged simplification ("For now we ignore X; that is the last section."). Glossary terms keep the table's spelling everywhere in prose, and the prose never coins a synonym for one ("leap year" for a 13-month year).
- The one sanctioned synonym is a row's declared short form (`short` in `definitions_final.json`); its markup is `## Terms and glossary` in `/ari-hemingway--format-explainer`.
- The figure's caption names its controls in the imperative ("Drag the slider or press play; the inset magnifies the ray tips.") and carries the not-to-scale caveat; the prose never repeats the caption. The prose after a figure points at figure state through `data-ref` spans ("the red arc"), never through words the figure does not show, in sentences of one idea each.
- Hiding information in a figure hides it in the prose. A `data-ref` to a layer the reader has switched off renders plain, so a sentence never depends on the highlight to be understood, and refs to an optional layer live in the sentences about that option ("with the Sun direction shown, the orange arrow...").
- Terms are defined at the point of need, once, by apposition in the same sentence, with the first-use markup; later uses carry the term link. The glossary `<dd>` is the only copy of the definition.
- Every simplification is flagged in the sentence that makes it ("for now we ignore the postponement rules") and repaid in a named later section.
- Math appears only after the figure that motivates it; formulas show their variables and skip derivations. Numbers come in two forms when both help ("29.530589 days, or 29 days 12 hours 44 minutes").
- Scale is the reference's: 5,000 to 18,000 words and 20 to 70 figures for a full article; a first article may be 2,000 to 3,000 words and 8 to 10 figures. The concept count sets the figure count, so scale is chosen by choosing the scaffold's table size, not by trimming figures.

### Toolchain

The contract between steps is three author-written inputs and one generated output: `figures/<slug>.json` (one spec per figure), `article/body.html` (prose with figure placeholders `<figure data-spec="<slug>" data-aspect="W:H" id="fig-<slug>"><figcaption>…</figcaption></figure>` and the `hero`, `further` and `final` block markers), `article/meta.json` (`title`, `description`, `url`, `lede`, `slugs`, optional `tokens`), and `article/index.html`, which only `assemble.py` writes. The tools live in `bin/`, each with `--help`; every one takes `--folder` (or `INVESTIGATION_FOLDER`) and `--repo` (or `EXPLAINERS_REPO`, default `$HOME/Desktop/workspace/explainers`) and never a hard-coded path:

- `bin/figlib.py`: dict builders for scene2d specs (`box`, `text`, `seg`, `arrow`, `circle`, `slider`, `segmented`, `toggle`, `play`, `state`, `spec`, `dump`) and the comparison idioms the expression grammar lacks (`eq`, `inrange`, `ge`, `lt`). A bespoke generator imports it.
- `bin/bars_fig.py`, `bin/eras_fig.py`, `bin/ladder_fig.py`, `bin/bracket_fig.py`: generic generators (dollars as bars, staircase timeline, pay ladder, real bracket) that print a spec to stdout from `--row`, `--era`, `--rung` or `--formats` arguments and `--state name:value:label:caption`.
- `bin/scratch_page.py --repo <repo> --out <dir>/index.html fig-x=<spec>:W:H …`: a template instance mounting the given specs, the first in the hero slot, for the validator and for screenshots.
- `bin/assemble.py --folder <folder> --repo <repo>`: template + `body.html` + `figures/*.json` + `scaffold/definitions_final.json` → `article/index.html`; prunes `notice.point_at` to the ids the body references, applies the one-pill rule, generates the glossary with short forms and source links, sets the generator meta and the footer.
- `bin/shot.zsh --repo <repo> [--state <name>] <fig-id> <spec> <W:H> <out.png>`: one scratch page per figure under the repo's `articles/_shot-<fid>/`, rendered headlessly from the local server (port 8765, or `--port`), then removed. A fragment deep link (`#fig-x=state`) on the full article screenshots blank in headless Chromium; one scratch page per figure, at the hero slot, is the recipe that works.
- `bin/figure_manifest.py --folder <folder>`: the per-figure manifest for Figure review (concept, insight, `shows`, caption, prose after, refs and states used, spec, screenshot) and, on stdout, the `figures` argument for the workflow.
- `workflows/figure_audit.js`: Workflow script, audit → improve → verify per figure, looping until the target score or the round cap. Args: `{workdir, ciech, repo, figures, title?, manifest?, bin?, data?, rounds?, target?}`.

### Toolchain gates

- The explainers repo path is a pointer, default `$HOME/Desktop/workspace/explainers`. Its `DESIGN.md` is the vocabulary (`node tools/explainers.cjs vocab` and `errors` print the same tables); its `tools/explainers.cjs` is the only judge of validity. Never publish an article the CLI has not passed.
- Before Present, all four commands pass on the article: `validate`, `states`, `build`, `budget`.
- One local server for the whole run: before the first `shot.zsh`, probe `curl -fs http://127.0.0.1:8765/` and, if nothing answers, start `python3 -m http.server 8765` from the repo root with `run_in_background`; stop it at Output. Screenshots go into the investigation folder, never the repo.

## Investigation folder

Root path: `/tmp/hemingway/ciechanowski/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence follow `/ari-hemingway--lib`. Additional files:

```
scaffold/                 # copied from the scaffold folder: definitions_final.json, clusters.json, definitions_pass1.json, sources.md
skeleton.md               # TOC: the ordering rule used, sections in assembly order, concepts per section, accepted by the user
insights.json             # {rows:[{term, definition:<key insight>, shows:<what the figure draws>, doc_url}]} in table order; passes check_definitions_order
figures/plan.md           # per concept: diagram type from the catalog, the drawn quantity each control moves, controls, states
figures/<concept-slug>.json    # one figure spec per concept (interactive) or .mmd + sidecars (static)
figures/gen/*.py          # bespoke generators on bin/figlib.py; a generic generator's invocation goes in plan.md
figure-review/            # manifest.json, result.json, v2/<slug>.{json,html,png} from the audit workflow
article/body.html         # the prose with figure placeholders: the author's file
article/meta.json         # title, description, url, lede, slugs {term: glossary-slug}, optional tokens {name: [light, dark]}
article/index.html        # assembled by bin/assemble.py, built in place by the CLI, never edited by hand
preview/*.png             # page.png and c-<slug>[-<state>].png per figure
```

Scratchpad fields appended after `Last phase`:
```
- **Scaffold**: <path of the scaffold investigation folder> (<n> rows, <k> sections)
- **Repo**: <explainers repo path> @ <git short sha>
- **Scale**: full | first-article
- **Section order**: first hoisted row | caller: <order>
- **Palette**: <token=hex, ...> (≤6)
- **Figures**: <n> interactive, <m> static; validate/states/build/budget: pass|fail
- **Figure review**: <n> audited, <k> rebuilt, <s> accepted at 4 or 5, <r> stuck: <slug: reason, ...>
- **Article**: articles/<slug>/index.html (<words> words, <figures> figures)
```

## Workflow

### Gather pointers

Collect the topic, the scaffold investigation folder (or nothing, to run one), the explainers repo path, the article slug, the scale, the palette, and an explicit section order if the caller has one. Derive `{topic-slug}` and create the investigation folder per `/ari-hemingway--lib` with `--skill-name ciechanowski`. Write the initial scratchpad.

### Restore context

Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Acquire the skeleton

If no scaffold folder was given, invoke `/ari-hemingway--structure-scaffold` in Skeleton mode; it stops after its Cluster step and prints its folder. Copy `definitions_final.json`, `clusters.json`, `definitions_pass1.json` and `sources.md` into `scaffold/`. Run the mechanical check on `definitions_final.json`; a failing table is the scaffold's problem, not this skill's.

Print: `Acquire complete — {n} rows, {k} communities. Next: Skeleton.`

### Skeleton

Assign every table row to a section: a hoisted row to its community; a universal row to the community of the next hoisted row after it in table order. Order the sections by the table position of their first hoisted row; a universal row never sets a section's position, so a `Conference` row in table slot 1 that the postseason section inherits does not pull that section to the front. When the caller passed a section order, use it and skip the rule. The accepted table is already in dependency order, while `cross_edges` in `clusters.json` run both ways between real subsystems and cannot order them. A foundational row that the cluster step hoisted into a late community (a `Day` term merged into a year-shape community) belongs to every section; re-run the cluster step with `--universal "<term>"` rather than hand-moving it. Write `skeleton.md`: one line naming the ordering rule (`first hoisted row` or `caller`), then one `##` per section with its concepts in table order. Present it and wait; apply changes by editing `skeleton.md` or re-running the cluster step, never by hand-moving table rows.

Print: `Skeleton complete — {k} sections, {n} concepts, ordered by {rule}. Next: Insights.`

### Key insights

One agent per section writes, per concept, one insight and one `shows` sentence from the row, `definitions_pass1.json` and `sources.md`. Write `insights.json` in table order and run:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <folder>/insights.json
```

Fix every violation. Present the insights as a three-column table (concept, insight, shows) and wait.

Print: `Insights complete — {n} insights, 0 violations. Next: Figures.`

### Figures

Write `figures/plan.md` first: for each concept, static or interactive, the diagram type from the catalog in `/ari-hemingway--format-explainer` "Diagram types", the drawn quantity each control moves, the controls (at most three) and the named states. Reject the plan while two neighbouring concepts share a shape or a control moves nothing drawn. Then generate. Static: write the `.mmd` and bake it per `/ari-diagram-mermaid` (`ink_url` and `live_url`), embed per `/ari-hemingway--format-explainer`. Interactive: a generic generator from `bin/` when one fits, otherwise a bespoke `figures/gen/<slug>_fig.py` on `bin/figlib.py`; either way the output is `figures/<concept-slug>.json` with `notice.states` covering the insight and `notice.point_at` listing every layer the prose will reference. One author for all figures, or one agent per section with `DESIGN.md` and the "Spec idioms and gotchas" of `/ari-hemingway--format-explainer` in its brief; each spec is proven on a scratch page before it counts:

```zsh
python3 $HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin/scratch_page.py --repo <repo> --out <repo>/articles/_scratch-<slug>/index.html fig-<slug>=<folder>/figures/<slug>.json:<W>:<H>
node <repo>/tools/explainers.cjs validate <repo>/articles/_scratch-<slug>/index.html
node <repo>/tools/explainers.cjs states <repo>/articles/_scratch-<slug>/index.html
```

**`rm -rf <repo>/articles/_scratch-<slug>` afterwards, on success or failure**; `W:H` is the aspect `plan.md` gives the figure. Up to ten figures, one author writes them all; above that, one agent per section. Present the figure list (concept, type, controls, states) and wait.

Print: `Figures complete — {n} interactive, {m} static, 0 validator errors. Next: Figure review.`

### Figure review

The validator proves a spec is legal; this step asks whether the figure is worth the reader's attention. It runs on every new article before prose, and as a post-processing pass on any existing explainer whose investigation folder still holds `figures/*.json` and `article/body.html` (restore it with `Restore context` and run this step alone); an article without that folder is first split back into those files by hand, since the manifest reads them.

With the local server up (`### Toolchain gates`), screenshot every figure's default state and build the manifest:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin/shot.zsh --repo <repo> fig-<slug> <folder>/figures/<slug>.json <W:H> <folder>/preview/c-<slug>.png
python3 $HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin/figure_manifest.py --folder <folder>
```

`figure_manifest.py` writes `figure-review/manifest.json` and prints the `figures` list. Run the audit workflow: read `workflows/figure_audit.js` once and pass its text as `script` (the Workflow tool refuses a `scriptPath` outside the working directory; invoking this skill is the user's opt-in):

```
Workflow({script: <full text of workflows/figure_audit.js>,
          args: {workdir: "<folder>/figure-review", ciech: "<folder>", repo: "<repo>",
                 figures: <the printed list>, title: "<article title>", rounds: 2, target: 4}})
```

Per figure, one auditor scores five yes/no questions, score = count of yes: (1) a reader who drags sees the insight happen, not a label that states it; (2) the control changes something the reader cares about; (3) a sentence could not do the same job; (4) the shape differs from the neighbours; (5) the figure carries a number, comparison or motion the prose lacks. A figure below the target (4) goes to a builder, who rebuilds it to the auditor's one proposal, validates it on a scratch page and screenshots it, then to a verifier, who scores the rebuild by the same rubric against the before and after screenshots and accepts only a higher score of at least 4 with no visible defect (overlapping labels, clipped text, empty canvas, more than three controls, a duplicated pill, a control that moves nothing drawn). A rejection feeds its must-fix list into the next round; the loop stops at 4 or after `rounds` rounds, and a figure still below the target after `rounds` records its reason. Read the result (`scores`, `accepted`, `stuck`), save it as `figure-review/result.json`, then integrate: each accepted `v2/<slug>.json` replaces `figures/<slug>.json` (or its generator is updated and re-run), its `ids_renamed` and `prose_note` go into the figure's `plan.md` entry so Prose points at the new ids, and every changed spec is re-proven as in Figures. Record the stuck figures and their reasons in the scratchpad. Present the score table (figure, before, after, verdict) and wait.

Print: `Figure review complete — {n} audited, {k} rebuilt, {s} accepted at 4 or 5, {r} stuck with reasons. Next: Prose.`

### Prose

Write `article/body.html` and `article/meta.json`: the hero block and its figure placeholder, then each `<section>` from its insights and figures, with one placeholder per figure and its caption, then the `further` and `final` blocks. Follow `Drafting` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`: overwrite `body.html` whole each iteration; the glossary and the footer come from the assembler, never from the body. Assemble, build and gate:

```zsh
python3 $HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin/assemble.py --folder <folder> --repo <repo>
node <repo>/tools/explainers.cjs build <folder>/article/index.html
node <repo>/tools/explainers.cjs validate <folder>/article/index.html
node <repo>/tools/explainers.cjs states <folder>/article/index.html
node <repo>/tools/explainers.cjs budget <folder>/article/index.html --budget 170k
```

Review against three criteria: (a) jargon outside the table, (b) prose that describes something no figure shows, (c) claims not grounded in `sources.md`. Fix `body.html`, re-assemble and re-gate.

Print: `Prose complete — {words} words, {figures} figures, 4 gates green. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, `### External topic`: the published files are `article/body.html`, `article/meta.json` and `figures/*.json`; one claim per figure covers its constants and format strings; the doc URLs in the table are the sources. The 20% `[TODO: verify]` gate applies.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Preview.`

### Preview

Run `git -C <repo> status --short articles/<slug>` first: uncommitted changes there → STOP (someone's work would be overwritten). Then copy `article/index.html` and `article/assets/` only (never `body.html` or `meta.json`) to `articles/<slug>/`, print `git diff --stat articles/<slug>`, open the article headlessly from the local server and save `preview/page.png`. Then one `shot.zsh` per figure: the default state to `preview/c-<slug>.png` and each named state with `--state <name>` to `preview/c-<slug>-<state>.png`. Never screenshot a state through a fragment deep link on the full article; it renders blank in headless Chromium. Look at the screenshots. A figure that renders blank, overflows, or hides its controls is a bug in the spec, fixed before Present.

Print: `Preview complete — {n} screenshots at {folder}/preview. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, listing `articles/<slug>/index.html` in the repo and the preview folder; no menu is added.

### Output

The article already lives in the repo. Stop the local server. Invoke `/ari-hemingway--share-explainer` on `<repo>/articles/<slug>`: its dry-run shows the card diff, the commit message and the push target; `--apply` commits, pushes and watches the deploy once the user confirms. Record the published URL under `Published` in the scratchpad.

Print: `Output complete — articles/<slug>/index.html, {words} words, {figures} figures, {published URL or 'publish gate pending'}.`
