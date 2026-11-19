import { readFileSync } from "node:fs"
import { ArgGroup, ArgOption } from "./actions.ts"
import { argBuilder } from "./argbuilder.ts"
import { script } from "./mode.ts"

type Choice = { value: string | number; key?: string; label?: string }
type Param = {
  name: string
  bind: { at: string; token?: string; join?: "space" | "equals" }
  value?: {
    choices?: Array<string | Choice>
    open?: boolean
    openPolicy?: "close" | "exclude"
    default?: string | number
    initial?: string | number
    meta?: { karabiner?: { omitChoices?: Array<string | number> } }
  }
}
export type CmdsonDoc = { cmdson: string; name: string; exec?: string[]; params?: Param[]; subcommands?: unknown[] }

export const loadCmdson = (path: URL): CmdsonDoc => JSON.parse(readFileSync(path, "utf8"))

const fail = (doc: CmdsonDoc, param: string, why: string): never => {
  throw new Error(`cmdson doc not projectable to argbuilder | doc=${doc.name} param=${param} why=${why}`)
}

const toGroup = (doc: CmdsonDoc, param: Param): ArgGroup => {
  const value = param.value
  if (!value?.choices) return fail(doc, param.name, "no choices")
  if (value.open && value.openPolicy === "exclude") return fail(doc, param.name, "openPolicy exclude")
  const omitted = new Set((value.meta?.karabiner?.omitChoices ?? []).map(String))
  const options: ArgOption[] = value.choices
    .map((c) => (typeof c === "string" ? { value: c } : c))
    .filter((c) => !omitted.has(String(c.value)))
    .map((c) => {
      if (!c.key) return fail(doc, param.name, `choice ${c.value} has no key`)
      return { key: c.key, label: c.label ?? String(c.value), value: String(c.value) }
    })
  const preselected = String(value.initial ?? value.default ?? "")
  const defaultKey = options.find((o) => o.value === preselected)?.key
  if (!defaultKey) return fail(doc, param.name, "no initial/default among the choices")
  return { name: param.name, label: param.name, options, defaultKey }
}

// Projects the documents the karabiner profile can serve: a root command whose
// params are positional or flag binds, each with keyed choices (cmdson spec
// docs/02-frontends.md section 2). Anything else throws at bake.
export const argBuilderFromCmdson = (id: string, title: string, doc: CmdsonDoc) => {
  if (doc.subcommands) fail(doc, "-", "subcommands")
  const params = doc.params ?? []
  for (const p of params) {
    if (p.bind.at === "env") fail(doc, p.name, "env bind")
  }
  const [bin, ...exec] = doc.exec ?? [doc.name]
  return argBuilder(id, title, params.map((p) => toGroup(doc, p)), (selection) =>
    script(bin, [
      ...exec,
      ...params.flatMap((p) => {
        const v = selection[p.name]
        if (p.bind.at === "positional") return [v]
        return p.bind.join === "equals" ? [`${p.bind.token}=${v}`] : [p.bind.token!, v]
      }),
    ]),
  )
}

