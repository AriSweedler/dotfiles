import { strict as assert } from "node:assert"
import { test } from "node:test"
import { argBuilderFromCmdson, CmdsonDoc, loadCmdson } from "../utils/cmdson.ts"

const doc = loadCmdson(new URL("./typing-test.cmdson.json", import.meta.url))
const builder = argBuilderFromCmdson("typing", "typing test builder", doc)

test("projected groups match the keyboard surface", () => {
  assert.deepEqual(builder.groups, [
    {
      name: "action",
      label: "action",
      defaultKey: "n",
      options: [
        { key: "n", label: "next", value: "next" },
        { key: "c", label: "current", value: "current" },
        { key: "p", label: "previous", value: "previous" },
      ],
    },
    {
      name: "words",
      label: "words",
      defaultKey: "1",
      options: [
        { key: "0", label: "5 words", value: "5" },
        { key: "1", label: "50 words", value: "50" },
        { key: "2", label: "100 words", value: "100" },
        { key: "3", label: "300 words", value: "300" },
      ],
    },
  ])
})

test("every selection fires karabiner-typing-test <action> --words <n>", () => {
  for (const action of ["next", "current", "previous"]) {
    for (const words of ["5", "50", "100", "300"]) {
      assert.deepEqual(builder.fire({ action, words }), {
        kind: "script",
        name: "karabiner-typing-test",
        args: [action, "--words", words],
      })
    }
  }
})

test("documents the karabiner profile cannot serve throw at bake", () => {
  const bad = (change: (d: CmdsonDoc) => void) => {
    const d: CmdsonDoc = structuredClone(doc)
    change(d)
    return () => argBuilderFromCmdson("typing", "t", d)
  }
  assert.throws(bad((d) => { d.params![1].value!.initial = 7 }), /no initial\/default/)
  assert.throws(bad((d) => { d.params![1].value!.openPolicy = "exclude" }), /openPolicy exclude/)
  assert.throws(bad((d) => { d.params![0].bind = { at: "env" } }), /env bind/)
  assert.throws(bad((d) => { delete d.params![1].value!.choices }), /no choices/)
})
