---
name: ari-hemingway--format-explainer
description: "Shared formatting conventions for explainer-site-bound skills: the HTML dialect the explainers runtime consumes (figure wrapper, JSON figure spec, diagram-type catalog, spec idioms and gotchas, term and glossary markup with short forms and source links, prose refs, state links, math, palette tokens, relative URLs). Not user-invocable — referenced by `/ari-hemingway--structure-ciechanowski`."
user_invocable: false
---

# Explainer Formatting

Reference rules for any skill that produces an article for the explainers site. Siblings follow these rules; they do not invoke this skill. The figure-spec vocabulary, the expression grammar, and the validator's error catalogue live in `DESIGN.md` at the root of the explainers repo (default `$HOME/Desktop/workspace/explainers`); this skill never copies them. Workflow patterns live in `/ari-hemingway--lib`.

## Prose style

- Kernighan & Ritchie: terse, precise, one idea per sentence, present tense, active voice. Delete any sentence with no concrete fact.
- `we` for building the system, `you` for operating a figure. No first-person singular except in a stated simplification ("for now I ignore the postponement rules").
- Numbers in two forms when both help: `29.530589 days, or 29 days 12 hours 44 minutes`. Real minus sign (`−`), thin space before units is not required.
- Sentence that follows a figure names its controls: `Drag the slider to advance the day; the button in the corner toggles the Sun.`
- Never mention Claude, a skill, or how the article was made outside the footer.

**For reviewers.** The rules above and in `## Prose refs and state links` are the destination's conventions, not findings: never flag present-tense figure narration, an imperative caption, `we`/`you`, or a `data-ref` pointer at figure state as a tone, depth or clarity mismatch; never flag the HTML markup or the word count, which the CLI `validate` and the length table in `/ari-hemingway--review-audience-fit` cover. Flag the opposite: a glossary term used before its `<dfn>`, a paragraph that assumes the reader knows the field, a caption under an interactive figure that does not say what to do, prose that describes something no figure shows (no `data-ref`, no caption pointer). Findings on an HTML body are anchored by section id (or figure id) and a quoted sentence, never a line number.

## Article skeleton

Start from `template/article.html` in the repo. Never hand-write the `<head>`; the template carries the viewport, theme color, palette tokens, the runtime `<script defer>`, the stylesheet, and the KaTeX CSS with relative paths. The body is `<main>` holding, in order: `<h1>`, the opening `<p>`s, the hero `<figure>`, one `<section id="<slug>">` per subsystem with an `<h2>`, `<section id="further">`, `<section id="final">`, the glossary `<details>`, and the footer `<p class="x-footer">🤖🌸 Generated with Claude Code with the ari-hemingway skill</p>`.

## Figures

Interactive figure: one `<figure class="x-fig" id="fig-<slug>" data-aspect="W:H">` containing exactly one `<script type="application/json">` with the spec and one `<figcaption>`. The spec's top-level keys are `shows`, `manipulates`, `notice`; every key and kind is in `DESIGN.md`. Colors are palette token names only. No `<script>` other than the JSON. The build step inserts the poster; never hand-write it.

```html
<figure class="x-fig" id="fig-months" data-aspect="3:2">
<script type="application/json">{ "shows": {...}, "manipulates": {...}, "notice": {...} }</script>
<figcaption>The Moon completes an orbit before it returns to the same phase.</figcaption>
</figure>
```

Static figure: the same wrapper with `data-static` (the validator then requires only the `id`), an `<a href="<live_url>" rel="external">` around `<img src="assets/<name>.png" alt="...">`, and a `<figcaption>`. The image is the baked `ink_url` PNG saved under `articles/<slug>/assets/`; the link is the baked `live_url` (`mermaid.live/view#`, never `/edit#`). Bake both with `/ari-diagram-mermaid`; never retype either URL.
- One viewport per figure. A figure and its whole panel (controls, stepper, caption) fit on one screen together: the runtime caps the canvas so box plus panel stay within about 95vh and lets the width follow the aspect ratio, but the author keeps the figure inside that budget in the first place: an aspect no taller than 1:1 (3:2 or 16:9 by default), at most three controls under the canvas, a one-line caption. A reader never scrolls between the drawing and the slider that drives it.

## Diagram types

A figure is a small model of the thing; the reader changes its state and watches one drawn quantity move. The rules for choosing a type (no shape repeats for neighbouring concepts, a control moves a drawn length, height, position, count or color, never only a caption) live in `/ari-hemingway--structure-ciechanowski` Figures. This catalog is the vocabulary: one entry per type, what moves, the article instance (`articles/college-football-playoff/index.html`, figure id), and the layers and control that define it. Every example is `scene2d`; coordinates and tokens are illustrative, the expressions are the idiom. `y`, `s`, `k` are integer sliders (`step: 1`); `m` a toggle; `era`, `e`, `f` segmented controls.

- **staircase timeline**: bar height is the quantity across eras; a highlighted copy marks the era the slider sits in. `fig-hero`: teams in the title field, 0 to 24.

```json
{ "id": "axis", "kind": "segment", "from": [-10, -1.2], "to": [10, -1.2], "stroke": "grey" },
{ "id": "era0", "kind": "polygon", "points": [[-10,-0.9],[1.7,-0.9],[1.7,-0.5],[-10,-0.5]], "stroke": "grey", "dash": [4,3] },
{ "id": "era0-hi", "kind": "polygon", "points": [[-10,-0.9],[1.7,-0.9],[1.7,-0.5],[-10,-0.5]], "stroke": "grey", "width": 2,
  "highlight": true, "visible": "clamp(min(y-1936+1, 1992-y),0,1)" },
{ "id": "era1", "kind": "polygon", "points": [[1.7,-0.9],[2.3,-0.9],[2.3,-0.1],[1.7,-0.1]], "stroke": "grey", "dash": [4,3] }
// control: { "kind": "slider", "name": "y", "min": 1936, "max": 2032, "step": 1, "default": 2025, "format": "{y:.0f}" }
```

- **map over time**: dots appear, move (an arrow), change size or color as a season slider advances; every school dot carries `hover` with the school's name (and `logo` when badges exist). `fig-realignment` (moves as arrows), `fig-big-12` (hollow rings where founders left), `fig-pac-12` (departures recolored to their new league).

```json
{ "id": "land", "kind": "polygon", "points": [[-74.7,49.4], "..."], "stroke": "grey" },
{ "id": "arizona-pac-12", "kind": "circle", "cx": -87.4, "cy": 32.2, "r": 0.42, "fill": "purple",
  "visible": "clamp(min(y-1990+1, 2023-y+1),0,1)" },
{ "id": "arizona-big-12", "kind": "circle", "cx": -87.4, "cy": 32.2, "r": 0.42, "fill": "green",
  "visible": "clamp(min(y-2024+1, 2026-y+1),0,1)" },
{ "id": "arizona-move", "kind": "arrow", "from": [-87.4, 32.2], "to": [-83.1, 36.5], "stroke": "green",
  "visible": "1 - min(abs(y-2024),1)" }
// controls: slider y 1990..2026 step 1; { "kind": "play", "target": "y", "rate": 2 }
```

- **map with a money slider**: dot area becomes dollars as the reader drags. `fig-group-of-five`: Ohio State balloons, Toledo stays a pinprick.

```json
{ "id": "ohio-state", "kind": "circle", "cx": -83.0, "cy": 40.0, "r": "lerp(0.42, 1.52, money)", "fill": "blue" },
{ "id": "toledo", "kind": "circle", "cx": -83.6, "cy": 41.7, "r": "lerp(0.42, 0.45, money)", "fill": "grey" }
// readout: { "id": "bigten-per", "at": [-98.5, 29.6], "text": "a Big Ten school: ${lerp(0,20.9,money):.1f}M a year", "token": "blue", "visible": "clamp(money*20,0,1)" }
// control: { "kind": "slider", "name": "money", "min": 0, "max": 1, "step": 0.05, "default": 0, "format": "{money*100:.0f}%" }
```

- **split map and bars**: a map and a bar panel share one slider. `fig-big-ten`: four Pacific dots land and the payout bars rise.

```json
"shows": { "type": "scene2d", "view": { "x": [-99.5, -51.5], "y": [23.5, 50.5] },
  "layers": [ { "id": "oregon", "kind": "circle", "cx": -97.0, "cy": 44.1, "r": 0.5, "fill": "orange", "visible": "clamp(y-2024+1,0,1)" } ],
  "split": [ { "at": "right", "shows": { "type": "scene2d", "view": { "x": [0, 10], "y": [0, 10] },
    "layers": [ { "id": "payout", "kind": "polygon", "fill": "blue",
      "points": [[1,0],[3,0],[3,"lerp(2.2, 7.5, clamp((y-1990)/36,0,1))"],[1,"lerp(2.2, 7.5, clamp((y-1990)/36,0,1))"]] } ] } } ] }
// control: slider y 1990..2026 step 1; the panel reads the same scope
```

- **pool and shares**: one bar peels into N equal chunks as a slider divides it. `fig-media-rights-deal`: $1,370M into 18.

```json
{ "id": "bar0", "kind": "polygon", "fill": "blue",
  "points": [[-6,3.05],["-6 + 12*lerp(T0, T0/N0, split)/1370",3.05],["-6 + 12*lerp(T0, T0/N0, split)/1370",4.05],[-6,4.05]] },
{ "id": "pool0", "kind": "polygon", "points": [[-6,3.05],[6,3.05],[6,4.05],[-6,4.05]], "stroke": "grey", "visible": "split" },
{ "id": "cut0_1", "kind": "segment", "from": [-5.33,3.05], "to": [-5.33,4.05], "stroke": "grey", "visible": "clamp(40*(split-1.0)+1,0,1)" },
{ "id": "cut0_2", "kind": "segment", "from": [-4.67,3.05], "to": [-4.67,4.05], "stroke": "grey", "visible": "clamp(40*(split-0.94)+1,0,1)" }
// constants: { "T0": 1370, "N0": 18 }; control: slider split 0..1 step 0.05; notice.steps "none"
```

- **cohort bars**: rows by arrival year; a toggle lays them end to end. `fig-sec`: fourteen full shares, two newcomers' stubs.

```json
{ "id": "bar-alabama", "kind": "polygon", "fill": "red",
  "points": [["lerp(0,0.1,m)","lerp(15.9,9.2,m)"],["lerp(24,2.29,m)","lerp(15.9,9.2,m)"],["lerp(24,2.29,m)","lerp(16.7,12.4,m)"],["lerp(0,0.1,m)","lerp(16.7,12.4,m)"]] },
{ "id": "sep-1992", "kind": "segment", "from": [-5.8,6.8], "to": [35.3,6.8], "stroke": "grey", "dash": [2,4], "visible": "(1-m)" },
{ "id": "axis", "kind": "segment", "from": [0,8.7], "to": [34,8.7], "stroke": "grey", "visible": "m" }
// control: { "kind": "toggle", "name": "m", "label": ["per school", "whole league"], "default": false, "position": "below" }; notice.steps "none"
```

- **before and after in dollars**: a segmented control redraws every bar against a ghost of the other case. `fig-power-four`: old deal vs new deal.

```json
{ "id": "sh0", "kind": "polygon", "fill": "blue",
  "points": [[-5,3.57],["-5 + 10*lerp(109.3,377,era)/400",3.57],["-5 + 10*lerp(109.3,377,era)/400",4.43],[-5,4.43]] },
{ "id": "ghost0", "kind": "polygon", "stroke": "grey", "dash": [4,3], "visible": "era",
  "points": [[-5,3.57],["-5 + 10*109.3/400",3.57],["-5 + 10*109.3/400",4.43],[-5,4.43]] },
{ "id": "lab0", "kind": "text", "at": [-5.3, 4], "text": "Big Ten", "size": 12, "align": "right" }
// control: { "kind": "segmented", "name": "era", "options": [{ "value": 0, "label": "2025, old deal" }, { "value": 1, "label": "2026, new deal" }], "default": 1 }; notice.steps "none"
```

- **pick and stack a set**: a `chips` control (multiselect, one scrolling row) lights the members of every pressed group and stacks their amounts on one bar; `p.<key>` is 1 while pressed and `p.count` counts them. `fig-conference`: press leagues, their schools light, their badges line up, their pots stack. Use it instead of a segmented control once there are more than five options or when combinations matter.

```json
{ "id": "potfill-sec", "kind": "polygon", "fill": "red", "visible": "p.sec",
  "points": [["-98.5 + 11.5*(0)",25],["-98.5 + 11.5*(0) + 11.5*1.03",25],["-98.5 + 11.5*(0) + 11.5*1.03",26.8],["-98.5 + 11.5*(0)",26.8]] },
{ "id": "badge-acc", "kind": "image", "src": "assets/logos/conf-acc.svg", "rect": ["-51.8 - 4.3*(1 + p.sec + p.big_ten)", 50.4, 4.0, 2.7], "visible": "p.acc" }
// control: { "kind": "chips", "name": "p", "options": [{ "key": "sec", "label": "SEC" }, { "key": "big_ten", "label": "Big Ten" }], "default": ["sec"], "token": "grey" }
// keys are identifiers (big_ten, not big-ten); a state sets "p": ["sec","big_ten"]; a readout may show "{p.count:.0f} leagues"; notice.steps "none"
```


- **fragmentation**: one wide box splits into proportional boxes as a slider passes dated stops. `fig-board-of-regents`: one seller to many.

```json
{ "id": "ncaa", "kind": "polygon", "points": [[-9.8,1.9],[9.2,1.9],[9.2,3.1],[-9.8,3.1]], "stroke": "grey", "visible": "clamp(1984-y,0,1)" },
{ "id": "b10p10", "kind": "polygon", "points": [[-9.8,1.9],[-5.3,1.9],[-5.3,3.1],[-9.8,3.1]], "stroke": "blue", "visible": "clamp(y-1984+1,0,1)" },
{ "id": "cfa", "kind": "polygon", "points": [[-5.1,1.9],[9.2,1.9],[9.2,3.1],[-5.1,3.1]], "stroke": "orange",
  "visible": "clamp(y-1984+1,0,1)*clamp(1996-y,0,1)" }
// readout: { "id": "sellers", "at": [-9.8, 4.4], "text": "sellers: {1 + clamp(y-1984+1,0,1) + clamp(y-1991+1,0,1) + clamp(y-1996+1,0,1):.0f}", "token": "grey" }
// control: { "kind": "slider", "name": "y", "values": [1983, 1984, 1991, 1996, 1997], "default": 1983, "format": "{y:.0f}" }
```

- **wiring over seasons**: fixed nodes; colored wires move with a season picker. `fig-bowl-coalition` (1992-1997); the bowl-contract years in `fig-bowl-game`.

```json
{ "id": "c-big-ten", "kind": "polygon", "points": [[-9.6,3.2],[-6,3.2],[-6,4],[-9.6,4]], "stroke": "grey" },
{ "id": "b-rose", "kind": "polygon", "points": [[6,3.2],[9.6,3.2],[9.6,4],[6,4]], "stroke": "grey" },
{ "id": "w-big-ten-rose", "kind": "segment", "from": [-6,3.6], "to": [6,3.6], "stroke": "grey", "width": 1.5 },
{ "id": "w-sec-sugar", "kind": "segment", "from": [-6,0.6], "to": [6,1.4], "stroke": "orange", "width": 3, "visible": "clamp(1995-s,0,1)" },
{ "id": "w-sec-pool", "kind": "segment", "from": [-6,0.6], "to": [2.6,1.4], "stroke": "orange", "width": 3, "visible": "clamp(s-1995+1,0,1)" }
// control: { "kind": "slider", "name": "s", "min": 1992, "max": 1997, "step": 1, "default": 1994, "format": "{s:.0f} season" }
```

- **sweep strip**: one dot per year on a baseline; a cursor forks the split years as it passes. `fig-ap-poll`: AP Poll vs coaches, 1950-2013.

```json
{ "id": "base", "kind": "segment", "from": [1949.5,-11.4], "to": [2013.5,-11.4], "stroke": "grey" },
{ "id": "yr-1954", "kind": "circle", "cx": 1954, "cy": 0, "r": 0.4, "fill": "grey", "visible": "clamp(1954-s,0,1)" },
{ "id": "ap-1954", "kind": "circle", "cx": 1954, "cy": 2, "r": 0.4, "fill": "orange", "visible": "clamp(s-1954+1,0,1)" },
{ "id": "co-1954", "kind": "circle", "cx": 1954, "cy": -2, "r": 0.4, "fill": "blue", "visible": "clamp(s-1954+1,0,1)" },
{ "id": "tally", "kind": "text", "at": [1978.5, 18.2], "size": 12,
  "text": "two champions in {clamp(s-1954+1,0,1)+clamp(s-1957+1,0,1)+clamp(s-1965+1,0,1):.0f} seasons" }
// controls: slider s 1950..2013 step 1; { "kind": "play", "target": "s", "rate": 4 }
```

- **re-scored standings**: stacked bars whose segment widths are the real components; a control swaps formulas. `fig-bcs`: 2003 under both formulas.

```json
{ "id": "row1-s0", "kind": "polygon", "fill": "red",
  "points": [["-4.9 + lerp(0,0,e)",2.7],["-4.9 + lerp(5.55,3.85,e)",2.7],["-4.9 + lerp(5.55,3.85,e)",3.9],["-4.9 + lerp(0,0,e)",3.9]] },
{ "id": "row1-s1", "kind": "polygon", "fill": "blue",
  "points": [["-4.9 + lerp(5.55,3.85,e)",2.7],["-4.9 + lerp(9.45,7.7,e)",2.7],["-4.9 + lerp(9.45,7.7,e)",3.9],["-4.9 + lerp(5.55,3.85,e)",3.9]] },
{ "id": "cut", "kind": "segment", "from": [-9.9,0.1], "to": [8.1,0.1], "stroke": "grey", "dash": [6,4] }
// control: { "kind": "segmented", "name": "e", "options": [{ "value": 0, "label": "1998-2003" }, { "value": 1, "label": "2004-2013" }], "default": 1 }; notice.steps "none"
```

- **real bracket**: seeded names fill a bracket; a control picks the rule that filled it. `fig-cfp`: 2014, 2024, 2025.

```json
{ "id": "f1-l1", "kind": "segment", "from": [-5.4,3.6], "to": [0.2,3.6], "stroke": "blue", "visible": "1 - min(abs(f-1),1)" },
{ "id": "b-bye1", "kind": "segment", "from": [-5.4,4.9], "to": [0.2,4.9], "stroke": "blue", "visible": "clamp(f-1,0,1)" },
{ "id": "f2-s1", "kind": "text", "at": [-5.7,4.9], "text": "1 Oregon", "size": 11, "align": "right", "visible": "1 - min(abs(f-2),1)" },
{ "id": "f3-s1", "kind": "text", "at": [-5.7,4.9], "text": "1 Indiana", "size": 11, "align": "right", "visible": "1 - min(abs(f-3),1)" }
// readout: { "id": "games", "at": [-11.3,-5.05], "text": "games: {3 + 8*clamp(f-1,0,1):.0f}", "token": "grey" }
// control: { "kind": "segmented", "name": "f", "options": [{ "value": 1, "label": "2014: four teams" }, { "value": 2, "label": "2024: champions seeded 1-4" }, { "value": 3, "label": "2025: straight seeding" }], "default": 2 }
```

- **turning ring**: a hand sweeps around fixed nodes; labels accumulate where it dwells. `fig-new-years-six`: the semifinal rotation.

```json
{ "id": "semi-rose", "kind": "circle", "cx": 0, "cy": 2.9, "r": 0.9, "fill": "blue",
  "visible": "min(1 - min(abs(floor(s+0.25)-2014),1) + 1 - min(abs(floor(s+0.25)-2017),1), 1)" },
{ "id": "t-rose", "kind": "text", "at": [0, 2.98], "text": "Rose", "size": 12 },
{ "id": "hand", "kind": "segment", "from": [0,0], "to": ["1.85*cos(pi/2 - wrap(s-2014,0,3)*2*pi/3)", "1.85*sin(pi/2 - wrap(s-2014,0,3)*2*pi/3)"], "stroke": "blue", "width": 2 },
{ "id": "hub", "kind": "circle", "cx": 0, "cy": 0, "r": 0.14, "fill": "blue" }
// controls: slider s 2014..2026 step 1; { "kind": "play", "target": "s", "rate": 1, "loop": true }
```

- **pay ladder**: rungs appear on a baseline as the year passes; later figures reuse the ladder and add one rung. `fig-amateurism`, `fig-obannon`, `fig-alston`.

```json
{ "id": "base", "kind": "segment", "from": [-11.3,-2.6], "to": [10.8,-2.6], "stroke": "grey" },
{ "id": "none", "kind": "polygon", "points": [[-11,-2.5],[1.5,-2.5],[1.5,-1.2],[-11,-1.2]], "stroke": "grey", "dash": [4,4], "visible": "clamp(1956-y,0,1)" },
{ "id": "gia", "kind": "polygon", "points": [[-11,-2.5],[1.5,-2.5],[1.5,-1.2],[-11,-1.2]], "fill": "grey", "visible": "clamp(y-1956+1,0,1)" },
{ "id": "coa", "kind": "polygon", "points": [[-11,-1.2],[1.5,-1.2],[1.5,-0.4],[-11,-0.4]], "fill": "green", "visible": "clamp(y-2015+1,0,1)" },
{ "id": "coa-t", "kind": "text", "at": [-10.7,-0.8], "text": "cost of attendance", "size": 11, "align": "left", "visible": "clamp(y-2015+1,0,1)" }
// controls: slider y 1950..2026 step 1; { "kind": "play", "target": "y", "rate": 6 }
```

- **gated flow**: payer boxes, a checkpoint, a slider that routes the money. `fig-nil` (year), `fig-csc` (deal size and payer).

```json
{ "id": "player", "kind": "polygon", "points": [[2.5,0.6],[8.5,0.6],[8.5,3],[2.5,3]], "stroke": "grey" },
{ "id": "a-school", "kind": "arrow", "from": [-3,3.9], "to": [2.5,2.6], "stroke": "grey", "width": 1.5 },
{ "id": "ao0", "kind": "arrow", "from": [-3,1.7], "to": [2.5,1.7], "stroke": "orange", "width": 1.5, "visible": "clamp(y-2021+1,0,1)" },
{ "id": "ax0", "kind": "segment", "from": [-3,1.7], "to": [2.5,1.7], "stroke": "red", "dash": [3,5], "visible": "1 - clamp(y-2021+1,0,1)" },
{ "id": "recruit", "kind": "polygon", "points": [[2.5,-3.5],[8.5,-3.5],[8.5,-1.9],[2.5,-1.9]], "stroke": "grey", "visible": "clamp(y-2022+1,0,1)" }
// control: { "kind": "slider", "name": "y", "min": 2020, "max": 2024, "step": 1, "default": 2020, "format": "{y:.0f}" }
```

- **career strip**: one person's seasons as boxes; the rule change flips which seasons are played. `fig-transfer-portal`.

```json
{ "id": "s1", "kind": "polygon", "points": [[-9.4,-0.2],[-5.5,-0.2],[-5.5,2.2],[-9.4,2.2]], "fill": "green" },
{ "id": "sit0", "kind": "polygon", "points": [[-4.7,-0.2],[-0.8,-0.2],[-0.8,2.2],[-4.7,2.2]], "stroke": "red", "dash": [5,4], "visible": "clamp(2021-y,0,1)" },
{ "id": "play0", "kind": "polygon", "points": [[-4.7,-0.2],[-0.8,-0.2],[-0.8,2.2],[-4.7,2.2]], "fill": "green", "visible": "1-(clamp(2021-y,0,1))" }
// readout: { "id": "count", "at": [9.4,3.5], "text": "seasons played: {4-clamp(2021-y,0,1)-clamp(2024-y,0,1):.0f} of 4", "token": "green" }
// control: { "kind": "segmented", "name": "y", "options": [{ "value": 2017, "label": "2017 · no portal" }, { "value": 2021, "label": "2021 · one free transfer" }, { "value": 2024, "label": "2024 · unlimited" }], "default": 2024 }
```

- **filling fund**: yearly slabs stack as the slider advances; each slab split by payer. `fig-house-settlement`.

```json
{ "id": "p0", "kind": "polygon", "points": [[-9,0.5],[-7.4,0.5],[-7.4,1.46],[-9,1.46]], "fill": "grey", "visible": "clamp(y-2025+1,0,1)" },
{ "id": "p0-conf", "kind": "polygon", "points": [[-9,1.46],[-7.4,1.46],[-7.4,2.9],[-9,2.9]], "fill": "blue", "visible": "clamp(y-2025+1,0,1)" },
{ "id": "o0", "kind": "polygon", "points": [[-9,0.5],[-7.4,0.5],[-7.4,2.9],[-9,2.9]], "stroke": "grey", "dash": [4,4], "visible": "clamp(2025-y,0,1)" },
{ "id": "o1", "kind": "polygon", "points": [[-7.2,0.5],[-5.6,0.5],[-5.6,2.9],[-7.2,2.9]], "stroke": "grey", "dash": [4,4], "visible": "clamp(2026-y,0,1)" }
// control: { "kind": "slider", "name": "y", "min": 2025, "max": 2034, "step": 1, "default": 2025, "format": "{y:.0f}-{y-1999:.0f}" }
```

- **formula bar**: one bar is the base; a shaded fraction is the cap; a slider grows both. `fig-revenue-sharing`: 22% of $93M.

```json
{ "id": "keep", "kind": "polygon", "fill": "grey",
  "points": [["-9.2 + 0.125*C0*(1+G)^k",1.4],["-9.2 + 0.125*R*(1+G)^k",1.4],["-9.2 + 0.125*R*(1+G)^k",5.6],["-9.2 + 0.125*C0*(1+G)^k",5.6]] },
{ "id": "cap", "kind": "polygon", "fill": "red",
  "points": [[-9.2,1.4],["-9.2 + 0.125*C0*(1+G)^k",1.4],["-9.2 + 0.125*C0*(1+G)^k",5.6],[-9.2,5.6]] },
{ "id": "flat", "kind": "segment", "from": [-6.64,0.95], "to": [-6.64,5.7], "stroke": "grey", "dash": [4,4] }
// constants: { "R": 93, "C0": 20.5, "G": 0.04 }; control: { "kind": "slider", "name": "k", "min": 0, "max": 10, "step": 1, "default": 1, "format": "{2025+k:.0f}-{26+k:.0f}" }
```

A need the runtime cannot meet (check `node tools/explainers.cjs vocab` first) is a runtime request, not a workaround in the spec: record it under `Runtime requests` in the scratchpad, name it at Present, and note the substitute type in `figures/plan.md`. `logo` requires `hover` on the same layer (`SPEC_MISSING_KEY` otherwise).

The rules for choosing among these (hover names on every school dot, a slider only when its middle values matter, continuous connectors, one pill) are `### Figure design` in `$HOME/.claude/skills/ari-hemingway--structure-ciechanowski/SKILL.md`; this catalog only shows the shapes.

## Spec idioms and gotchas

Each item cites the runtime function where the behaviour lives.

- **`timeline` bars are not `point_at` targets.** `collectShows` in `lib/spec.js` files `bars[].id` (with series, guides and readouts) under `cat.other`, not `cat.layers`; `checkSemantics` then fails `SPEC_POINT_AT_MISSING` for any `notice.point_at` id outside `cat.layers` and `cat.objects`. A bar id does pass the page-level `REF_ID_UNKNOWN` check (`refIds` is every declared id), so the span validates and never highlights. When prose must point at a bar, draw the timeline from `scene2d` layers (`polygon` bars on a `segment` axis, as the staircase timeline above) and `point_at` those.
- **`readouts` are not `point_at` targets either.** A readout's `id` passes `REF_ID_UNKNOWN` (prose may `data-ref` it and it highlights), but `notice.point_at` accepts only layer and object ids, so listing a readout there fails `SPEC_POINT_AT_MISSING`. Point at the readout from prose and leave it out of `point_at`.
- **`plot` and `timeline` panels never draw `readouts`.** The schema accepts `shows.readouts` on every figure type (`SHOWS_SHARED` in `lib/spec.js`) and `compilePanel` in `lib/scene2d/scene2d.js` compiles them, but `paintPanel` calls `drawReadout` only through `paintScene`, the `scene2d` branch; the `plot` and `timeline` branches go to `drawPlot` and `drawTimeline` and return. The spec validates and the number is missing. Put the value in the slider `format` (`"{y:.0f}: {n:.0f} schools"`) or build the figure in `scene2d`.
- **Comparisons are written with `clamp`, `min` and `abs`.** The grammar has no `<`, `==` or `?:` (`tokenize` in `lib/expr.js` accepts only `+ - * / % ^ ( ) ,`; DESIGN.md "Expression grammar"). For an integer control `x` (`step: 1`, or a `values` slider) the idioms are, each evaluating to 0 or 1:

  | wanted | expression |
  |---|---|
  | `x == v` | `1 - min(abs(x-v),1)` |
  | `a <= x <= b` | `clamp(min(x-a+1, b-x+1),0,1)` |
  | `x >= v` | `clamp(x-v+1,0,1)` |

  These assume an integer control (`step: 1`, or a `values` slider whose stops are integers); `bin/figlib.py` in the ciechanowski skill exports them as `eq`, `inrange`, `ge`, `lt`, so a generator imports them instead of retyping them.
  | `x < v` | `clamp(v-x,0,1)` |

  A count is a sum of such terms: `"{10 + clamp(y-1993+1,0,1) + 2*clamp(y-2014+1,0,1):.0f} members"` in a readout or `text` layer, and a layer's `visible` takes any of them directly. Under `play` (`advance` in `lib/site/figure.js` adds `rate * dt`; `coerce` in `lib/core/state.js` snaps only a `values` slider) and during a `goto` ease, `x` passes through fractions, so an equality reads as a one-step tent and a threshold as a one-step ramp; both read as a fade. Wrap the control (`floor(x+0.25)`) when the layer must switch, not fade.
- **The default state is an exact step.** `mountStepper` in `lib/controls/stepper.js` reads `nearestState(fig.compiled, fig.scope)` and, when `exact` is false, sets the face to `near`, appends ` *` to the counter and replaces the caption with the footnote "* between steps". `nearestState` (`lib/core/state.js`) is exact only when every control the state names equals its target (`eps` 1e-6; toggles and segmented by value). So one `notice.states[]` entry has to equal every control's `default` (`manipulates.controls[].default`), or the figure boots with the asterisk and no caption. When the only controls are segmented or toggle, set `notice.steps` to `"none"`; the states stay deep-linkable and the figure carries one pill, not two.

## Prose refs and state links

- Pointing at figure state: `<span data-fig="fig-months" data-ref="sun-line">the orange arrow</span>`. `data-ref` names a layer, control, or readout id declared in that figure; the validator rejects anything else.
- A ref inherits the visibility of what it points at. When the layer, readout, or control a `data-ref` names is hidden in the figure's current state (a toggle switched off, a state's `visible.hide`), the runtime renders the span as plain prose: no token color, no underline, no hover highlight. It returns when the layer does. Hiding information in the figure hides it in the text, so write the sentence to read correctly when the span is plain.
- Jumping a figure to a named state: `<a href="#fig-months" data-state="sidereal">after one sidereal month</a>`. The href stays a real fragment so the link works without JavaScript.
- Control vocabulary follows `DESIGN.md` "Slider anatomy" and "Stepper anatomy" in the explainers repo: a *slider* has a *track* (its *fill* and *rail*), a *knob* the reader drags, a *halo* on hover, and on a discrete slider *stops* marked by *ticks* and *sockets*; a drag control's on-canvas point is a *handle*. The *stepper* under a figure has *steps* ("step 2 of 3"), *paddles* ‹ ›, a *latch* between them, or a *pill* of steps when there are five or fewer; the reader *steps in* and *steps off*, and the figure is *free* or *stepped*. Captions and prose use these words and never "thumb", "button", "dot" or "circle" for the knob, nor "arrow" for a paddle.

## Terms and glossary

Three places, one definition:

- First use, exactly once per term, defined by apposition in the same sentence: `<dfn id="t-synodic-month"><a href="#g-synodic-month">synodic month</a></dfn>, the mean time from one new Moon to the next, ...`
- Later uses: `<a class="term" href="#g-synodic-month">synodic month</a>`. The runtime shows the glossary definition as a tooltip on hover or focus; click or tap goes to the row.
- The glossary, last element in `<main>`: `<details id="glossary" class="x-glossary"><summary>Glossary</summary><dl>` with one `<div class="row" id="g-<slug>"><dt>term <a class="x-back" href="#t-<slug>" aria-label="back to first use">↩</a></dt><dd>definition <a rel="external" href="<doc_url>">source</a></dd></div>` per table row, in table order. The `<dd>` is the accepted table's definition and the only copy of it.
- Every row ends with its source: the table row's `doc_url` as `<a rel="external" href="<doc_url>">source</a>`, the last child of the `<dd>`. No glossary row, footnote or caveat is published without a resource that links to it. A row whose table has no `doc_url` is a scaffold defect: fix the table upstream (`/ari-hemingway--structure-scaffold` refine), never publish the row bare. The validator allows it: `checkGlossary` (`tools/src/glossary.mjs`) requires one non-empty `<dd>` and the `x-back` link and reads nothing else inside the row; `checkUrls` (`tools/src/article.mjs`) skips any `<a>` whose `rel` contains `external`. The same link without `rel="external"` fails `URL_ABSOLUTE`. The tooltip (`lib/site/term.js`) copies `dd.textContent`, so the word "source" trails the definition on hover; keep the link text to that one word.
- Short form. A row may declare `short` (the scaffold's `definitions_final.json` carries the optional field; `SEC` for Southeastern Conference). The slug stays the full term's. The first use defines both by apposition, with the short form right after the `<dfn>`: `<dfn id="t-southeastern-conference"><a href="#g-southeastern-conference">Southeastern Conference</a></dfn> (SEC), the league of ...`. Later `a.term` links may use the short form as link text: `<a class="term" href="#g-southeastern-conference">SEC</a>`. The `<dt>` shows both: `<dt>Southeastern Conference (SEC) <a class="x-back" ...>↩</a></dt>`. A term without `short` has no sanctioned synonym; the link text is the term. The validator never reads link text, so both forms resolve.

Slugs are shared across all three places: lowercase, hyphens, ASCII. The validator rejects a first use without a row, a row without a first use, and a term link whose row is missing.

## Math

Inline `<span class="x-tex">T_{syn} = \frac{1}{1/T_{sid} - 1/Y}</span>`, display `<div class="x-tex">...</div>`. The build step renders them with KaTeX in place and keeps the source in `data-tex`. Color a symbol with a palette token through the `\tok{<token>}{...}` macro; any other token name, and any `\color` or `\textcolor`, fails the build. Math follows the figure that motivates it, never precedes it.

## Palette

At most six tokens per article, declared once as `--c-<name>: light-dark(#light, #dark)` in the template's inline `<style>` `:root` rule, each at 3:1 contrast or better against `--bg` in both schemes. The same token names color canvas layers, slider tracks, and equation symbols; prose points at colored things through `data-ref` spans, never through color words alone. A color literal anywhere outside `:root` is a violation.

## Links and URLs

- Every `src` and `href` is relative to the article directory or a fragment, except `fonts.googleapis.com`, `fonts.gstatic.com`, and `<a rel="external">` links in prose and in Further Watching and Reading.
- Named external entities (an author, a textbook, a channel, a spec) are linked at first mention with `rel="external"`.
- Further Watching and Reading: a `<ul>` of three to six links, each with one sentence saying what it adds.

## Gates

An article is not formatted until `node tools/explainers.cjs validate`, `states`, `build` and `budget --budget 170k` all pass on it. The CLI's `file:line: CODE figure-id: message` lines are the review; fix the source, never the CLI. `node tools/explainers.cjs vocab` prints the closed vocabulary and `errors` the 48-code catalogue; both come from `lib/spec.js`, the same module the runtime uses.
