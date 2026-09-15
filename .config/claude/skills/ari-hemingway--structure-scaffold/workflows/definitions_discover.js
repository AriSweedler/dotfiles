export const meta = {
  name: 'scaffold-definitions-discover',
  description: 'Sweep a topic from several angles, draft a definition for every candidate term with a verified doc link, refute per batch, run a completeness critic, report the dependency graph',
  phases: [
    { title: 'Plan', detail: 'choose sweep angles when none were given' },
    { title: 'Discover', detail: 'multi-angle sweep for candidate terms' },
    { title: 'Define', detail: 'first-pass definitions with verified doc links' },
    { title: 'Verify', detail: 'accuracy and structure refuters per batch' },
    { title: 'Critic', detail: 'missing and redundant terms' },
  ],
}

// args: {topic, grounding?, angles?: [{key, prompt}], must_terms?: [], subsystems_hint?, batch_size?}
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
if (!A.topic) throw new Error('args.topic is required')
const TOPIC = A.topic
const GROUNDING = `${A.grounding || ''} Read only: never install, modify, or send anything. Return only the structured output.`
const MUST = A.must_terms || []
const BATCH = A.batch_size || 6
const HINT = A.subsystems_hint || 'the standalone subsystem explanations a scaffold article of this topic would need'

const ANGLES_SCHEMA = { type: 'object', properties: { angles: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, prompt: { type: 'string' } }, required: ['key', 'prompt'] } } }, required: ['angles'] }
const TERMS_SCHEMA = { type: 'object', properties: { terms: { type: 'array', items: { type: 'object', properties: {
  term: { type: 'string', description: 'Canonical noun form, capitalized as the official docs capitalize it' },
  aliases: { type: 'array', items: { type: 'string' } },
  draft: { type: 'string', description: 'One or two sentence first-pass definition' },
  doc_url: { type: 'string', description: 'Best canonical documentation URL, or empty string' },
  depends_on: { type: 'array', items: { type: 'string' }, description: 'Other terms of this topic the draft relies on' },
  evidence: { type: 'string', description: 'Where you saw it: command output, file path, doc section' },
}, required: ['term', 'draft', 'doc_url', 'depends_on', 'evidence'] } } }, required: ['terms'] }
const DEFS_SCHEMA = { type: 'object', properties: { definitions: { type: 'array', items: { type: 'object', properties: {
  term: { type: 'string' }, definition: { type: 'string' }, doc_url: { type: 'string' }, doc_url_verified: { type: 'boolean' },
  depends_on: { type: 'array', items: { type: 'string' }, description: 'Exact spellings from the master list that the definition uses' },
  drop: { type: 'boolean', description: 'true if the term is a duplicate, not topic jargon, or too niche' }, drop_reason: { type: 'string' },
}, required: ['term', 'definition', 'doc_url', 'doc_url_verified', 'depends_on', 'drop'] } } }, required: ['definitions'] }
const VERDICTS_SCHEMA = { type: 'object', properties: { verdicts: { type: 'array', items: { type: 'object', properties: {
  term: { type: 'string' }, ok: { type: 'boolean' }, issues: { type: 'array', items: { type: 'string' } },
  corrected_definition: { type: 'string' }, corrected_doc_url: { type: 'string' }, corrected_depends_on: { type: 'array', items: { type: 'string' } },
}, required: ['term', 'ok', 'issues', 'corrected_definition', 'corrected_doc_url', 'corrected_depends_on'] } } }, required: ['verdicts'] }
const MISSING_SCHEMA = { type: 'object', properties: {
  missing: { type: 'array', items: { type: 'object', properties: { term: { type: 'string' }, why: { type: 'string' }, draft: { type: 'string' }, doc_url: { type: 'string' }, depends_on: { type: 'array', items: { type: 'string' } } }, required: ['term', 'why', 'draft', 'doc_url', 'depends_on'] } },
  remove: { type: 'array', items: { type: 'object', properties: { term: { type: 'string' }, why: { type: 'string' } }, required: ['term', 'why'] } },
}, required: ['missing', 'remove'] }

const norm = s => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().replace(/s$/, '')

phase('Plan')
let angles = A.angles
if (!angles || !angles.length) {
  const plan = await agent(`You are planning a glossary sweep for ${TOPIC}. ${GROUNDING}\n\nPropose 5 to 8 independent research angles that together enumerate every named concept a newcomer must know: official terminology pages, the on-disk or on-wire layout, the CLI or API surface, the configuration or definition language, the build or distribution pipeline, the ecosystem around it, and so on. Each angle is a self-contained instruction for one researcher: name the concrete sources (URLs, commands, paths) it must sweep. Return {angles: [{key, prompt}]}.`,
    { label: 'plan-angles', phase: 'Plan', schema: ANGLES_SCHEMA })
  angles = plan ? plan.angles : []
  log(`Planned ${angles.length} angles: ${angles.map(a => a.key).join(', ')}`)
}
if (!angles.length) throw new Error('no sweep angles')

phase('Discover')
const sweeps = await parallel(angles.map(a => () => agent(
  `You are enumerating jargon for a glossary of ${TOPIC}. ${GROUNDING}\n\nAngle: ${a.prompt}\n\nFor each concept return the canonical term (noun form), aliases, a one-or-two-sentence first-pass draft, the single best canonical doc URL (empty string if none), the other terms of this topic the draft relies on, and the evidence you saw. Be exhaustive within your angle; 10 to 30 terms is typical.`,
  { label: `sweep:${a.key}`, phase: 'Discover', schema: TERMS_SCHEMA })))

const byKey = new Map()
for (const sweep of sweeps.filter(Boolean)) for (const t of sweep.terms) {
  const k = norm(t.term)
  if (!byKey.has(k)) byKey.set(k, { term: t.term, aliases: new Set(), drafts: [], doc_urls: new Set(), depends_on: new Set(), evidence: [] })
  const m = byKey.get(k)
  ;(t.aliases || []).forEach(x => m.aliases.add(x))
  m.drafts.push(t.draft)
  if (t.doc_url) m.doc_urls.add(t.doc_url)
  t.depends_on.forEach(x => m.depends_on.add(x))
  m.evidence.push(t.evidence)
}
const merged = [...byKey.values()].map(m => ({ ...m, aliases: [...m.aliases], doc_urls: [...m.doc_urls], depends_on: [...m.depends_on] }))
log(`Discovered ${merged.length} distinct terms from ${sweeps.filter(Boolean).length} sweeps`)
const masterList = () => merged.map(m => m.term)

const definePrompt = (batch, master) => `You are writing first-pass glossary definitions for ${TOPIC}. ${GROUNDING}

MASTER TERM LIST (the only jargon a definition may lean on without explaining it; spell exactly as listed):
${master.map(t => `- ${t}`).join('\n')}

Rules:
- One or two sentences. Say what the thing IS, then how it relates to neighbors. No marketing, no hedging.
- List every master-list term you used in depends_on with exact spelling. Any other jargon must be explained inline in plain words.
- Prefer defining in terms of MORE fundamental concepts.
- doc_url: choose the single most canonical page or anchor, then VERIFY it resolves (WebFetch or curl -sIL) and covers the term; set doc_url_verified. If it fails, try one alternative, else return empty string with doc_url_verified=false.
- drop=true with a reason for duplicates, non-jargon, or terms too niche for a newcomer.

TERMS TO DEFINE:
${batch.map(m => `### ${m.term}\naliases: ${m.aliases.join(', ') || '-'}\ndrafts:\n${m.drafts.map(d => `  - ${d}`).join('\n')}\ncandidate urls: ${m.doc_urls.join(' | ') || '-'}\nevidence: ${m.evidence.join(' | ')}`).join('\n\n')}`

const verifyPrompt = (lens, defs, master) => `You are a skeptical reviewer of glossary definitions for ${TOPIC}. ${GROUNDING}

MASTER TERM LIST: ${master.join(', ')}

Lens: ${lens === 'accuracy'
  ? 'FACTUAL ACCURACY. Check each definition against the official sources and any local evidence you can gather. Refute anything wrong, outdated, or misleading. Confirm the doc_url resolves and is canonical; propose a better one if not.'
  : 'STRUCTURE. (1) Every piece of jargon a definition uses must be in the master list AND listed in depends_on, or be explained inline; flag missing/extra depends_on entries. (2) No circularity. (3) One or two sentences, what-it-IS first. (4) Prefer more-fundamental terms. Return corrected_depends_on as the complete exact-spelling list.'}

Default to ok=false when uncertain. When not ok, supply a full corrected_definition (and corrected_doc_url / corrected_depends_on when relevant).

DEFINITIONS:
${defs.map(d => `- ${d.term}: ${d.definition}\n  doc_url: ${d.doc_url || '-'} (verified=${d.doc_url_verified})\n  depends_on: ${d.depends_on.join(', ') || '-'}`).join('\n')}`

const applyVerdicts = (defs, accuracy, structure) => {
  const acc = new Map((accuracy?.verdicts || []).map(v => [norm(v.term), v]))
  const str = new Map((structure?.verdicts || []).map(v => [norm(v.term), v]))
  return defs.map(d => {
    const a = acc.get(norm(d.term)), s = str.get(norm(d.term))
    const out = { ...d, review_issues: [] }
    if (a && !a.ok) {
      out.review_issues.push(...a.issues.map(i => `accuracy: ${i}`))
      if (a.corrected_definition) out.definition = a.corrected_definition
      if (a.corrected_doc_url) { out.doc_url = a.corrected_doc_url; out.doc_url_verified = true }
      if (a.corrected_depends_on?.length) out.depends_on = a.corrected_depends_on
    }
    if (s && !s.ok) {
      out.review_issues.push(...s.issues.map(i => `structure: ${i}`))
      if (s.corrected_definition && !(a && !a.ok && a.corrected_definition)) out.definition = s.corrected_definition
      if (s.corrected_depends_on?.length) out.depends_on = s.corrected_depends_on
    }
    return out
  })
}

const toBatches = list => { const b = []; for (let i = 0; i < list.length; i += BATCH) b.push(list.slice(i, i + BATCH)); return b }
const defineAndVerify = async (batchList, master, tag) => pipeline(
  batchList,
  (batch, _item, i) => agent(definePrompt(batch, master), { label: `define:${tag}${i}`, phase: 'Define', schema: DEFS_SCHEMA }),
  async (res, _item, i) => {
    if (!res) return []
    const defs = res.definitions.filter(d => !d.drop)
    const dropped = res.definitions.filter(d => d.drop)
    if (dropped.length) log(`define:${tag}${i} dropped ${dropped.map(d => `${d.term} (${d.drop_reason || 'no reason'})`).join('; ')}`)
    if (!defs.length) return []
    const [accuracy, structure] = await parallel([
      () => agent(verifyPrompt('accuracy', defs, master), { label: `verify-accuracy:${tag}${i}`, phase: 'Verify', schema: VERDICTS_SCHEMA }),
      () => agent(verifyPrompt('structure', defs, master), { label: `verify-structure:${tag}${i}`, phase: 'Verify', schema: VERDICTS_SCHEMA }),
    ])
    return applyVerdicts(defs, accuracy, structure)
  })

log(`Defining ${merged.length} terms in ${Math.ceil(merged.length / BATCH)} batches`)
let definitions = (await defineAndVerify(toBatches(merged), masterList(), 'b')).flat().filter(Boolean)
log(`${definitions.length} definitions survived round 1`)

phase('Critic')
const critic = await agent(`You are the completeness critic for a glossary of ${TOPIC}. ${GROUNDING}

The glossary is the shared jargon a reader needs before reading ${HINT}. A definition may only lean on terms defined earlier in the table.

CURRENT GLOSSARY:
${definitions.map(d => `- ${d.term}: ${d.definition}`).join('\n')}

Answer two things. (1) missing: concepts a definition above relies on, or a subsystem explanation would need, that are absent — give a draft, canonical doc_url, depends_on.${MUST.length ? ` Include these required terms if absent: ${MUST.join(', ')}.` : ''} (2) remove: duplicates, non-jargon, or too-niche entries. Be concrete and exhaustive.`,
  { label: 'completeness-critic', phase: 'Critic', schema: MISSING_SCHEMA })

let round2 = []
if (critic) {
  const removeKeys = new Set(critic.remove.map(r => norm(r.term)))
  if (removeKeys.size) log(`Critic removes: ${critic.remove.map(r => `${r.term} (${r.why})`).join('; ')}`)
  definitions = definitions.filter(d => !removeKeys.has(norm(d.term)))
  const have = new Set(definitions.map(d => norm(d.term)))
  const fresh = critic.missing.filter(m => !have.has(norm(m.term)))
  log(`Critic adds ${fresh.length} missing terms: ${fresh.map(m => m.term).join(', ')}`)
  if (fresh.length) {
    for (const m of fresh) merged.push({ term: m.term, aliases: [], drafts: [m.draft], doc_urls: m.doc_url ? [m.doc_url] : [], depends_on: m.depends_on, evidence: [`critic: ${m.why}`] })
    round2 = (await defineAndVerify(toBatches(merged.slice(merged.length - fresh.length)), masterList(), 'c')).flat().filter(Boolean)
    definitions.push(...round2)
  }
}

// Dependency graph: Kahn's algorithm. Whatever is left is cyclic — expected on a first pass;
// the refine workflow resolves it by selection, layered rewriting, and axiomatic definitions.
const keyOf = d => norm(d.term)
const present = new Map(definitions.map(d => [keyOf(d), d]))
const unresolved = []
const deps = new Map()
for (const d of definitions) {
  const ds = new Set()
  for (const x of d.depends_on) {
    const k = norm(x)
    if (k === keyOf(d)) continue
    if (present.has(k)) ds.add(k); else unresolved.push({ term: d.term, dep: x })
  }
  deps.set(keyOf(d), ds)
}
const indeg = new Map([...deps].map(([k, s]) => [k, s.size]))
const dependents = new Map()
for (const [k, s] of deps) for (const p of s) { if (!dependents.has(p)) dependents.set(p, []); dependents.get(p).push(k) }
const ordered = []
let ready = [...indeg].filter(([, n]) => n === 0).map(([k]) => k).sort()
while (ready.length) {
  const k = ready.shift()
  ordered.push(present.get(k))
  for (const child of dependents.get(k) || []) {
    indeg.set(child, indeg.get(child) - 1)
    if (indeg.get(child) === 0) { ready.push(child); ready.sort() }
  }
}
const cyclic = definitions.filter(d => !ordered.includes(d))
log(`Graph: ${ordered.length} linearizable, ${cyclic.length} in cycles, ${unresolved.length} unresolved dependency mentions`)

const shape = d => ({ term: d.term, definition: d.definition, doc_url: d.doc_url, doc_url_verified: d.doc_url_verified, depends_on: d.depends_on, review_issues: d.review_issues })
return {
  topic: TOPIC,
  definitions: [...ordered, ...cyclic].map(shape),
  ordered: ordered.map(d => d.term),
  cyclic: cyclic.map(d => d.term),
  unresolved,
  critic_removed: critic ? critic.remove : [],
  critic_added: round2.map(d => d.term),
  angles: angles.map(a => a.key),
}
