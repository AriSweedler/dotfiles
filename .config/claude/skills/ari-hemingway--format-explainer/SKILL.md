---
name: ari-hemingway--format-explainer
description: "Shared formatting conventions for explainer-site-bound skills: the HTML dialect the explainers runtime consumes (figure wrapper, JSON figure spec, term and glossary markup, prose refs, state links, math, palette tokens, relative URLs). Not user-invocable — referenced by `/ari-hemingway--structure-ciechanowski`."
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

## Prose refs and state links

- Pointing at figure state: `<span data-fig="fig-months" data-ref="sun-line">the orange arrow</span>`. `data-ref` names a layer, control, or readout id declared in that figure; the validator rejects anything else.
- A ref inherits the visibility of what it points at. When the layer, readout, or control a `data-ref` names is hidden in the figure's current state (a toggle switched off, a state's `visible.hide`), the runtime renders the span as plain prose: no token color, no underline, no hover highlight. It returns when the layer does. Hiding information in the figure hides it in the text, so write the sentence to read correctly when the span is plain.
- Jumping a figure to a named state: `<a href="#fig-months" data-state="sidereal">after one sidereal month</a>`. The href stays a real fragment so the link works without JavaScript.
- Control vocabulary follows `DESIGN.md` "Slider anatomy" and "Stepper anatomy" in the explainers repo: a *slider* has a *track* (its *fill* and *rail*), a *knob* the reader drags, a *halo* on hover, and on a discrete slider *stops* marked by *ticks* and *sockets*; a drag control's on-canvas point is a *handle*. The *stepper* under a figure has *steps* ("step 2 of 3"), *paddles* ‹ ›, a *latch* between them, or a *pill* of steps when there are five or fewer; the reader *steps in* and *steps off*, and the figure is *free* or *stepped*. Captions and prose use these words and never "thumb", "button", "dot" or "circle" for the knob, nor "arrow" for a paddle.

## Terms and glossary

Three places, one definition:

- First use, exactly once per term, defined by apposition in the same sentence: `<dfn id="t-synodic-month"><a href="#g-synodic-month">synodic month</a></dfn>, the mean time from one new Moon to the next, ...`
- Later uses: `<a class="term" href="#g-synodic-month">synodic month</a>`. The runtime shows the glossary definition as a tooltip on hover or focus; click or tap goes to the row.
- The glossary, last element in `<main>`: `<details id="glossary" class="x-glossary"><summary>Glossary</summary><dl>` with one `<div class="row" id="g-<slug>"><dt>term <a class="x-back" href="#t-<slug>" aria-label="back to first use">↩</a></dt><dd>definition</dd></div>` per table row, in table order. The `<dd>` is the accepted table's definition and the only copy of it.

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
