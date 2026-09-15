export const meta = {
  name: 'scaffold-definitions-refine',
  description: 'Select the most important terms from a discover pass, rewrite them in dependency layers with Simplified Technical English, enforce linear ordering mechanically (axiomatic fallback), and re-verify facts',
  phases: [
    { title: 'Select', detail: 'judge panel picks the core terms' },
    { title: 'Layer', detail: 'rewrite so each row uses only earlier rows' },
    { title: 'Verify', detail: 'factual refuters on the final rows' },
  ],
}

// args: {topic, grounding?, input_json, terms?: [], judges?, min_votes?, target_rows?, must_terms?,
//        max_sentences?, max_words?, ste100?, axiomatic?, fix_rounds?}
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
if (!A.topic) throw new Error('args.topic is required')
if (!A.input_json) throw new Error('args.input_json (path to the discover result) is required')
const TOPIC = A.topic
const GROUNDING = `${A.grounding || ''} Read only: never install, modify, or send anything. Return only the structured output.`
const INPUT = A.input_json
const JUDGES = A.judges || 3
const MIN_VOTES = A.min_votes || JUDGES
const TARGET = A.target_rows || '25 to 35'
const MUST = A.must_terms || []
const MAX_SENTENCES = A.max_sentences || 2
const MAX_WORDS = A.max_words || 25
const STE100 = A.ste100 !== false
const AXIOMATIC = A.axiomatic !== false
const FIX_ROUNDS = A.fix_rounds || 5

const SELECT_SCHEMA = { type: 'object', properties: { selected: { type: 'array', items: { type: 'object', properties: { term: { type: 'string' }, why: { type: 'string' } }, required: ['term', 'why'] } } }, required: ['selected'] }
const ROWS_SCHEMA = { type: 'object', properties: { rows: { type: 'array', items: { type: 'object', properties: {
  term: { type: 'string' }, definition: { type: 'string' }, doc_url: { type: 'string' },
}, required: ['term', 'definition', 'doc_url'] } } }, required: ['rows'] }
const ROW_SCHEMA = { type: 'object', properties: { term: { type: 'string' }, definition: { type: 'string' } }, required: ['term', 'definition'] }
const VERDICTS_SCHEMA = { type: 'object', properties: { verdicts: { type: 'array', items: { type: 'object', properties: {
  term: { type: 'string' }, ok: { type: 'boolean' }, issues: { type: 'array', items: { type: 'string' } },
  corrected_definition: { type: 'string' }, corrected_doc_url: { type: 'string' },
}, required: ['term', 'ok', 'issues', 'corrected_definition', 'corrected_doc_url'] } } }, required: ['verdicts'] }

const norm = s => s.toLowerCase().replace(/[^a-z0-9/]+/g, ' ').trim()
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const mentionRe = term => new RegExp(`(^|[^a-z0-9])${escapeRe(term.toLowerCase()).replace(/[\s_-]+/g, '[\\s_-]*')}(s|es|ed|d|ing)?(?=$|[^a-z0-9])`, 'i')
const words = s => s.split(/\s+/).filter(Boolean).length

// Same contract as bin/check_definitions_order.zsh; kept in sync by hand.
const checkOrder = (rows, terms) => {
  const violations = []
  terms.filter(t => !rows.some(r => norm(r.term) === norm(t))).forEach(t => violations.push({ term: t, kind: 'missing', issue: 'row missing' }))
  rows.forEach((row, i) => {
    if (!terms.some(t => norm(t) === norm(row.term))) violations.push({ term: row.term, kind: 'extra', issue: 'not in the term list; remove' })
    const text = row.definition
    if (mentionRe(row.term).test(text)) violations.push({ term: row.term, kind: 'self', issue: 'mentions its own term' })
    rows.forEach((other, j) => {
      if (j <= i) return
      if (norm(other.term).includes(norm(row.term)) && norm(other.term).length > norm(row.term).length) return
      if (mentionRe(other.term).test(text)) violations.push({ term: row.term, kind: 'forward', other: other.term, issue: `uses "${other.term}", defined later (row ${j + 1} > row ${i + 1})` })
    })
    const sentences = text.split(/(?<=[.!?])\s+(?=[A-Z(`/~<])/).filter(s => s.trim())
    if (sentences.length > MAX_SENTENCES) violations.push({ term: row.term, kind: 'length', issue: `${sentences.length} sentences; max ${MAX_SENTENCES}` })
    sentences.forEach(s => { if (words(s) > MAX_WORDS) violations.push({ term: row.term, kind: 'length', issue: `sentence has ${words(s)} words; max ${MAX_WORDS}` }) })
    if (/\betc\b|\.\.\.|…|\bvarious\b|\band so on\b/i.test(text)) violations.push({ term: row.term, kind: 'filler', issue: 'contains etc/.../various/and so on' })
  })
  return violations
}

phase('Select')
let terms = A.terms && A.terms.length ? A.terms : null
let votes = null
if (!terms) {
  const LENSES = [
    'a new engineer who must read standalone explanations of the topic\'s subsystems and needs the vocabulary those explanations will use without re-explaining',
    'a maintainer who wants the minimal set of nouns whose absence would make the official documentation unreadable; prefer nouns for things (places, files, objects, states) over command names, and cut anything a reader can infer from plain English',
    'an editor of a reference glossary: distinct concepts only, no near-duplicates, no CLI subcommands unless the subcommand IS the concept, no API method names unless they name a first-class concept',
    'a teacher building a one-page cheat sheet: only terms that appear in more than one part of the system',
    'a reviewer who removes anything a reader can look up in thirty seconds and keeps only what unlocks understanding of the rest',
  ]
  const picks = await parallel(Array.from({ length: JUDGES }, (_, i) => () => agent(
    `Read the JSON file at ${INPUT}. Its "definitions" array holds candidate glossary terms for ${TOPIC} with first-pass definitions. Select the core shared-jargon set from the perspective of ${LENSES[i % LENSES.length]}. Target ${TARGET} terms.${MUST.length ? ` You MUST include: ${MUST.join(', ')}.` : ''} Return exact spellings as they appear in the file. Do not invent terms not in the file.`,
    { label: `select:${i}`, phase: 'Select', schema: SELECT_SCHEMA })))
  const tally = new Map(), spelling = new Map()
  for (const p of picks.filter(Boolean)) for (const s of p.selected) { const k = norm(s.term); tally.set(k, (tally.get(k) || 0) + 1); if (!spelling.has(k)) spelling.set(k, s.term) }
  for (const m of MUST) { const k = norm(m); tally.set(k, JUDGES); if (!spelling.has(k)) spelling.set(k, m) }
  votes = [...tally].map(([k, n]) => ({ term: spelling.get(k), votes: n })).sort((a, b) => b.votes - a.votes || a.term.localeCompare(b.term))
  terms = votes.filter(v => v.votes >= MIN_VOTES).map(v => v.term)
  log(`Selected ${terms.length} terms with >= ${MIN_VOTES} of ${JUDGES} votes; dropped ${votes.length - terms.length}`)
}

phase('Layer')
const styleRules = STE100
  ? `ASD-STE100 (Simplified Technical English): active voice, present tense, one idea per sentence, everyday words, no parentheticals longer than a path or an example.`
  : `Terse K&R style: precise, no marketing, no hedging.`
const basePrompt = `You are the dedicated rewriter for the shared-jargon table of a scaffold article about ${TOPIC}. ${GROUNDING}

Read ${INPUT}: its "definitions" array holds accurate but verbose first-pass definitions and verified doc URLs. Rewrite ONLY these terms, ordered so that every row uses only earlier rows (most fundamental first):
${terms.map((t, i) => `${i + 1}. ${t}`).join('\n')}

Rules, checked mechanically after you return:
1. At most ${MAX_SENTENCES} sentences per definition; at most ${MAX_WORDS} words per sentence. Prefer one sentence.
2. First sentence says what the thing IS (a directory, a file, a process, a state, a step). A second sentence relates it to earlier rows or gives the one fact a newcomer needs.
3. ${styleRules} No "etc", "...", "various", "and so on", no hedging.
4. A definition may mention a table term ONLY if that term is an earlier row; mentions are matched as whole words including plurals and -ed/-ing forms. It must not mention its own term.
5. Any other jargon must be replaced with plain words or dropped. Keep one concrete example (a path or a name) when it helps.
6. Keep facts true to the first-pass text; drop detail rather than invent. Keep the verified doc_url from the file; empty string if it had none.`

let res = await agent(basePrompt, { label: 'rewrite:0', phase: 'Layer', schema: ROWS_SCHEMA, effort: 'high' })
let rows = res ? res.rows : []
let violations = checkOrder(rows, terms)
let round = 0
while (violations.length && round < FIX_ROUNDS) {
  round++
  log(`Check round ${round}: ${violations.length} violations`)
  const fixed = await agent(`${basePrompt}

Your previous table failed the mechanical check. Fix ALL of these and return the complete corrected table (reorder rows and rewrite definitions as needed; you may not add or drop terms):
${violations.map(v => `- ${v.term}: ${v.issue}`).join('\n')}

PREVIOUS TABLE:
${rows.map((r, i) => `${i + 1}. ${r.term} | ${r.definition} | ${r.doc_url}`).join('\n')}`,
    { label: `rewrite:${round}`, phase: 'Layer', schema: ROWS_SCHEMA, effort: 'high' })
  if (!fixed) break
  rows = fixed.rows
  violations = checkOrder(rows, terms)
}

// Axiomatic fallback: a forward reference that survives the fix rounds means a genuine cycle.
// Make the most-referenced later term axiomatic: a dedicated STE100 agent rewrites it using NO
// table terms, and it moves to the top of the table as a root row.
const axioms = []
let axiomRounds = 0
while (AXIOMATIC && violations.some(v => v.kind === 'forward') && axiomRounds < 3) {
  axiomRounds++
  const counts = new Map()
  violations.filter(v => v.kind === 'forward').forEach(v => counts.set(v.other, (counts.get(v.other) || 0) + 1))
  const [target] = [...counts].sort((a, b) => b[1] - a[1])[0]
  const current = rows.find(r => norm(r.term) === norm(target))
  const axiom = await agent(`You are the dedicated ASD-STE100 rewriter making an AXIOMATIC definition for the term "${target}" in a glossary of ${TOPIC}. ${GROUNDING}

An axiomatic definition is a root row: it uses NO other table term at all, only everyday words and at most one concrete example. Table terms you must NOT use (including plurals and -ed/-ing forms): ${terms.filter(t => norm(t) !== norm(target)).join(', ')}. At most ${MAX_SENTENCES} sentences, ${MAX_WORDS} words each, active voice, present tense. Do not mention "${target}" itself.

Current definition to simplify: ${current ? current.definition : '(none)'}
First-pass source material: read ${INPUT} and search for the term.`,
    { label: `axiom:${target}`, phase: 'Layer', schema: ROW_SCHEMA, effort: 'high' })
  if (!axiom) break
  rows = [{ term: target, definition: axiom.definition, doc_url: current ? current.doc_url : '' }, ...rows.filter(r => norm(r.term) !== norm(target))]
  axioms.push(target)
  log(`Axiomatic definition adopted for "${target}"`)
  violations = checkOrder(rows, terms)
  let r2 = 0
  while (violations.length && r2 < 2) {
    r2++
    const fixed = await agent(`${basePrompt}

"${target}" is now an AXIOMATIC root row (row 1) — keep its definition verbatim. Fix ALL of these and return the complete table:
${violations.map(v => `- ${v.term}: ${v.issue}`).join('\n')}

TABLE:
${rows.map((r, i) => `${i + 1}. ${r.term} | ${r.definition} | ${r.doc_url}`).join('\n')}`,
      { label: `rewrite:axiom${axiomRounds}-${r2}`, phase: 'Layer', schema: ROWS_SCHEMA, effort: 'high' })
    if (!fixed) break
    rows = fixed.rows
    violations = checkOrder(rows, terms)
  }
}
log(`Layer check: ${violations.length} violations after ${round} fix rounds and ${axioms.length} axioms`)

phase('Verify')
const BATCH = 10
const batches = []
for (let i = 0; i < rows.length; i += BATCH) batches.push(rows.slice(i, i + BATCH))
const termList = rows.map(r => r.term).join(', ')
const noBloat = `Do NOT flag brevity or omitted detail: these rows are intentionally minimal; flag only false or misleading statements and wrong doc URLs. A corrected_definition must obey: max ${MAX_SENTENCES} sentences, max ${MAX_WORDS} words each, plain words, and may mention only these table terms, and only ones BEFORE the corrected row: ${termList}.`
const verdictSets = await parallel(batches.flatMap((batch, i) => [
  () => agent(`You are a skeptical FACTUAL reviewer of glossary rows for ${TOPIC}, working from the official documentation. ${GROUNDING} Refute anything wrong or outdated. ${noBloat}\n\nROWS:\n${batch.map(r => `- ${r.term}: ${r.definition}\n  doc_url: ${r.doc_url || '-'}`).join('\n')}`,
    { label: `verify-docs:${i}`, phase: 'Verify', schema: VERDICTS_SCHEMA }),
  () => agent(`You are a second, independent FACTUAL reviewer of glossary rows for ${TOPIC}, working hands-on: verify each claim with read-only commands, files, or live behavior where possible and fall back to documentation only when nothing local can show it. ${GROUNDING} ${noBloat}\n\nROWS:\n${batch.map(r => `- ${r.term}: ${r.definition}`).join('\n')}`,
    { label: `verify-hands-on:${i}`, phase: 'Verify', schema: VERDICTS_SCHEMA }),
]))
const corrections = new Map()
for (const vs of verdictSets.filter(Boolean)) for (const v of vs.verdicts) {
  if (v.ok) continue
  const k = norm(v.term)
  const c = corrections.get(k) || { issues: [], definition: '', doc_url: '' }
  c.issues.push(...v.issues)
  if (v.corrected_definition && !c.definition) c.definition = v.corrected_definition
  if (v.corrected_doc_url) c.doc_url = v.corrected_doc_url
  corrections.set(k, c)
}
let finalRows = rows.map(r => {
  const c = corrections.get(norm(r.term))
  if (!c) return { ...r, review_issues: [] }
  return { ...r, definition: c.definition || r.definition, doc_url: c.doc_url || r.doc_url, review_issues: c.issues }
})
let postViolations = checkOrder(finalRows, terms)
let postRound = 0
while (postViolations.length && postRound < 3) {
  postRound++
  log(`Post-review check round ${postRound}: ${postViolations.length} violations`)
  const fixed = await agent(`${basePrompt}

Reviewers corrected some rows for accuracy and the table now fails the mechanical check. Keep the reviewers' facts${axioms.length ? ` and keep the axiomatic rows verbatim (${axioms.join(', ')})` : ''}, fix ALL of these, return the complete table:
${postViolations.map(v => `- ${v.term}: ${v.issue}`).join('\n')}

TABLE:
${finalRows.map((r, i) => `${i + 1}. ${r.term} | ${r.definition} | ${r.doc_url}`).join('\n')}`,
    { label: `rewrite:post-review-${postRound}`, phase: 'Layer', schema: ROWS_SCHEMA, effort: 'high' })
  if (!fixed) break
  const issuesByKey = new Map(finalRows.map(r => [norm(r.term), r.review_issues]))
  finalRows = fixed.rows.map(r => ({ ...r, review_issues: issuesByKey.get(norm(r.term)) || [] }))
  postViolations = checkOrder(finalRows, terms)
}
log(`Final: ${finalRows.length} rows, ${postViolations.length} violations, ${corrections.size} rows corrected by reviewers, ${axioms.length} axiomatic`)
return { topic: TOPIC, rows: finalRows, violations: postViolations, terms, votes, axioms, corrected_count: corrections.size }
