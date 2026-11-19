import { strict as assert } from "node:assert"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import Ajv2020 from "ajv/dist/2020.js"
import { loadCmdson } from "../utils/cmdson.ts"

// The cmdson repo is the shared-tier sibling ~/.config/cmdson.
const SCHEMA_URL = new URL("../../../../cmdson/schema/cmdson.schema.json", import.meta.url)

const doc = loadCmdson(new URL("./typing-test.cmdson.json", import.meta.url))
const validator = () =>
  new Ajv2020({ strict: false, validateFormats: false, allErrors: true }).compile(
    JSON.parse(readFileSync(SCHEMA_URL, "utf8")),
  )

test("typing-test document validates against the cmdson schema", () => {
  const validate = validator()
  assert.equal(validate(doc), true, JSON.stringify(validate.errors))
})

test("the schema rejects a document with an unknown field", () => {
  assert.equal(validator()({ ...doc, bogus: 1 }), false)
})

test("the document carries a $schema that resolves to the schema file", () => {
  assert.equal(typeof (doc as Record<string, unknown>)["$schema"], "string")
  const resolved = new URL((doc as Record<string, unknown>)["$schema"] as string, new URL("./typing-test.cmdson.json", import.meta.url))
  assert.equal(resolved.href, SCHEMA_URL.href)
})
