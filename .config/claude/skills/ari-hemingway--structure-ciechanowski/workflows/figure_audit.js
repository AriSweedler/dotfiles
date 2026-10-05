export const meta = {
  name: 'explainer-figure-audit',
  description: 'Audit every figure of an explainer for usefulness, rebuild the weak ones until they score 4, verify before vs after',
  phases: [
    { title: 'Audit', detail: 'one auditor per figure: does it show its insight and earn the drag' },
    { title: 'Improve', detail: 'a builder rewrites each figure scored 3 or less, validates and screenshots it' },
    { title: 'Verify', detail: 'a verifier compares before and after against the insight; the loop repeats until 4 or the cap' },
  ],
}

// args: {workdir, ciech, repo, figures: [{slug, fid, aspect}], title?, manifest?, bin?, data?, rounds?, target?}
//   workdir  where drafts go: <workdir>/v2/<slug>.{json,html,png}
//   ciech    the ciechanowski investigation folder (figures/, insights.json, preview/, scaffold/)
//   repo     the explainers repo (DESIGN.md, tools/explainers.cjs, template/)
//   figures  the list figure_manifest.py prints
//   title    the article title (default: read from the manifest's first entry)
//   manifest default <workdir>/manifest.json (figure_manifest.py writes it)
//   bin      the skill's bin/ (default: $HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin)
//   data     one sentence naming extra data files the builders may read (optional)
//   rounds   build+verify rounds per weak figure (default 2); target: the score that stops the loop (default 4)
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
for (const k of ['workdir', 'ciech', 'repo', 'figures']) if (!A[k]) throw new Error(`args.${k} is required`)
const M = A.figures
const W = A.workdir, D = A.ciech, R = A.repo
const MAN = A.manifest || `${W}/manifest.json`
const BIN = A.bin || '$HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin'
const TITLE = A.title ? `"${A.title}"` : 'named in the manifest'
const DATA = A.data ? ` Data available: ${A.data}.` : ''
const ROUNDS = A.rounds || 2
const TARGET = A.target || 4

const AUDIT = { type: 'object', properties: {
  slug: { type: 'string' }, score: { type: 'integer', minimum: 1, maximum: 5 },
  verdict: { type: 'string', description: 'one sentence a reader would agree with' },
  problems: { type: 'array', items: { type: 'string' } },
  proposal: { type: 'string', description: 'the one concrete change (layers, controls, states, data) that would make the figure show its insight and be worth the drag; within the runtime vocabulary' },
  needs_runtime_change: { type: 'boolean' }, runtime_change: { type: 'string' },
  same_shape_as: { type: 'array', items: { type: 'string' }, description: 'slugs of other figures with the same visual shape' },
}, required: ['slug', 'score', 'verdict', 'problems', 'proposal', 'needs_runtime_change', 'same_shape_as'] }
const BUILD = { type: 'object', properties: {
  slug: { type: 'string' }, spec_path: { type: 'string' }, screenshot_path: { type: 'string' },
  validated: { type: 'boolean' }, summary: { type: 'string' },
  ids_renamed: { type: 'array', items: { type: 'object', properties: { from: { type: 'string' }, to: { type: 'string' } }, required: ['from', 'to'] } },
  prose_note: { type: 'string', description: 'what the paragraph after the figure must now say or point at' },
  gave_up_reason: { type: 'string' },
}, required: ['slug', 'spec_path', 'screenshot_path', 'validated', 'summary', 'ids_renamed', 'prose_note'] }
const VERDICT = { type: 'object', properties: {
  slug: { type: 'string' }, accept: { type: 'boolean' }, score_before: { type: 'integer' }, score_after: { type: 'integer' },
  notes: { type: 'string' }, must_fix_before_accept: { type: 'array', items: { type: 'string' } },
}, required: ['slug', 'accept', 'score_before', 'score_after', 'notes', 'must_fix_before_accept'] }

const RUBRIC = `Rubric, five yes/no questions, each with one sentence of evidence: (1) a reader who drags the control sees the insight happen, rather than reading it in a label; (2) the control changes something the reader cares about, not decoration; (3) a single sentence of prose could NOT do the same job; (4) the figure's visual shape differs from its neighbours (compare the neighbouring entries' screenshots in the manifest); (5) the figure carries a number, comparison or motion the prose lacks. Score = count of yes (1-5).`

const common = (m) => `Figure "${m.fid}" (slug "${m.slug}", aspect ${m.aspect}) in the interactive explainer ${TITLE}, written in the style of Bartosz Ciechanowski.
FIRST read the manifest ${MAN} (a JSON array) and find the entry whose slug is "${m.slug}": it gives the concept, the section, the KEY INSIGHT the figure must show without telling, what the planner said it should draw (shows), the caption, the prose paragraph after the figure (which points at layer ids via data-ref), the ids and states the prose references, the spec path and the screenshot path. Read the spec and view the screenshot.
Also read ${R}/DESIGN.md (Vocabulary, Controls, States, Expression grammar) and the "Diagram types" catalog in $HOME/.claude/skills/ari-hemingway--format-explainer/SKILL.md. Hard constraints: figure types scene2d | plot | timeline; colors only the article's palette tokens (at most six); at most three controls; one JSON spec, no JavaScript; timeline bars cannot be pointed at by prose; plot and timeline panels do not draw readouts; expressions have no comparisons, so use clamp/min/abs idioms (x==v: 1 - min(abs(x-v),1); a<=x<=b: clamp(min(x-a+1, b-x+1),0,1); x>=v: clamp(x-v+1,0,1)); the default control values must equal one declared state; a figure whose only controls are segmented or toggle sets notice.steps to "none" so the stepper does not duplicate the control's pill. Every control must move a drawn quantity (length, height, position, count or color); a control that only swaps captions or recolors a list is not a figure.${DATA} Helper code: ${BIN}/figlib.py and the generators ${BIN}/*_fig.py; scaffold rows in ${D}/scaffold/definitions_pass1.json.`

phase('Audit')
const results = await pipeline(M,
  (m) => agent(`You are a strict figure reviewer for an interactive explainer. Judge whether this figure is worth the reader's attention. Read-only.\n\n${common(m)}\n\n${RUBRIC} Then write the ONE concrete change that would raise it to ${TARGET} or 5 inside the vocabulary (name layers, controls, states, data), choosing a diagram type from the catalog that no neighbour uses. If the best change needs the runtime to change (tooltips, images per dot, more colors), say so in needs_runtime_change and runtime_change, and still give the best in-vocabulary proposal. Default to a harsh score; most first drafts are too plain.`,
    { label: `audit:${m.slug}`, phase: 'Audit', schema: AUDIT }),
  async (a, m) => {
    if (!a) return { audit: null, rounds: [], final: null }
    if (a.score >= TARGET) return { audit: a, rounds: [], final: null }
    const rounds = []
    let proposal = a.proposal, mustFix = [], scoreBefore = a.score
    for (let round = 1; round <= ROUNDS; round++) {
      const fixes = mustFix.length ? `\nThe previous round's verifier rejected the rebuild; fix every item before anything else: ${mustFix.join(' | ')}` : ''
      const b = await agent(`You are a figure builder for an interactive explainer. Rebuild one weak figure so it shows its insight. You write JSON specs, never JavaScript.\n\n${common(m)}\n\nAuditor's verdict (score ${a.score}): ${a.verdict}\nProblems: ${a.problems.join(' | ')}\nProposal to implement: ${proposal}${fixes}\n\nWrite the new complete spec to ${W}/v2/${m.slug}.json. Keep every id the prose references when its meaning survives; otherwise list the rename in ids_renamed and say in prose_note what the paragraph must point at instead. Keep the states the prose links, or rename them the same way. You may copy a generator as a template under ${W}/v2/ (never edit files under ${BIN}, ${D}/figures or the repo's articles/). Then prove it: build a scratch page with\n  python3 ${BIN}/scratch_page.py --repo ${R} --out ${W}/v2/${m.slug}.html ${m.fid}=${W}/v2/${m.slug}.json:${m.aspect}\nrun\n  node ${R}/tools/explainers.cjs validate ${W}/v2/${m.slug}.html && node ${R}/tools/explainers.cjs states ${W}/v2/${m.slug}.html\nand fix every error until both exit 0 (warnings about posters, integrity, og:image and unreferenced point_at are fine). Then screenshot the default state with\n  zsh ${BIN}/shot.zsh --repo ${R} ${m.fid} ${W}/v2/${m.slug}.json ${m.aspect} ${W}/v2/${m.slug}.png\n(a python3 -m http.server on port 8765 at the repo root is already running) and look at the PNG; iterate if labels collide, text is clipped, the canvas is mostly empty, or the insight is not visible. Report validated=true only if validate and states both exit 0. If you cannot beat the current figure, say why in gave_up_reason and set validated=false.`,
        { label: `build:${m.slug}#${round}`, phase: 'Improve', schema: BUILD, effort: 'high' })
      if (!b || !b.validated) { rounds.push({ round, build: b, verdict: null }); break }
      const v = await agent(`You judge whether a rebuilt figure is better than the original. Read-only.\n\n${common(m)}\n\nRebuilt spec: ${b.spec_path}; rebuilt screenshot: ${b.screenshot_path}. Builder's summary: ${b.summary}. Auditor's score for the original: ${a.score}; the proposal was: ${proposal}.\n\nView the original screenshot (from the manifest) and the rebuilt PNG, and read the new spec. ${RUBRIC} Score the rebuilt figure. Accept only if it scores higher than the original AND at least ${TARGET} AND still shows the key insight AND has no visible defect (overlapping labels, clipped text, empty canvas, more than three controls, a duplicated pill, a control that moves nothing drawn). List everything that must change before acceptance.`,
        { label: `verify:${m.slug}#${round}`, phase: 'Verify', schema: VERDICT, effort: 'high' })
      rounds.push({ round, build: b, verdict: v })
      if (!v) break
      if (v.accept && v.score_after >= TARGET) break
      mustFix = v.must_fix_before_accept || []
      scoreBefore = v.score_after
      if (round === ROUNDS) log(`${m.slug}: stays at ${v.score_after} after ${ROUNDS} rounds; reason recorded in details`)
    }
    const last = rounds.length ? rounds[rounds.length - 1] : null
    return { audit: a, rounds, final: last && last.verdict && last.verdict.accept ? last : null }
  })
const out = results.map((r, i) => ({ slug: M[i].slug, ...r }))
const weak = out.filter(r => r.audit && r.audit.score < TARGET)
const accepted = out.filter(r => r.final)
const stuck = weak.filter(r => !r.final)
log(`Audited ${out.filter(r => r.audit).length}/${M.length}; weak ${weak.length}; accepted ${accepted.length}; stuck ${stuck.length}`)
return {
  scores: out.map(r => ({ slug: r.slug, before: r.audit ? r.audit.score : null, after: r.final ? r.final.verdict.score_after : (r.audit ? r.audit.score : null), verdict: r.audit ? r.audit.verdict : null, runtime: r.audit ? r.audit.needs_runtime_change : null })),
  weak: weak.map(r => r.slug),
  accepted: accepted.map(r => ({ slug: r.slug, spec: r.final.build.spec_path, screenshot: r.final.build.screenshot_path, ids_renamed: r.final.build.ids_renamed, prose_note: r.final.build.prose_note })),
  stuck: stuck.map(r => ({ slug: r.slug, reason: r.rounds.length ? ((r.rounds[r.rounds.length - 1].verdict || {}).notes || (r.rounds[r.rounds.length - 1].build || {}).gave_up_reason || 'builder failed') : 'builder failed' })),
  details: out,
}
