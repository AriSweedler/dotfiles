#!/usr/bin/env node
// Read a passage on stdin, emit a monkeytype.com URL that opens a custom
// typing test with that text, words in order, on stdout.
//
// Monkeytype's ?testSettings= payload is lz-string compressToEncodedURIComponent
// of a JSON tuple: [mode, mode2, customTextSettings, punctuation, numbers,
// language, difficulty, funbox]. customText mode "repeat" preserves word order.
// (frontend/src/ts/controllers/url-handler.tsx in monkeytypegame/monkeytype)

const fs = require("fs");
const path = require("path");
const LZString = require(path.join(__dirname, "lz-string.js"));

// Typographic characters from the Gutenberg text are miserable to type
// literally; fold them to their ASCII equivalents.
const TYPOGRAPHY = [
  [/[‘’]/g, "'"],
  [/[“”]/g, '"'],
  [/[—–]/g, "-"],
  [/…/g, "..."],
];

function normalize(text) {
  let out = text;
  for (const [pattern, replacement] of TYPOGRAPHY) {
    out = out.replace(pattern, replacement);
  }
  // Fold anything else non-ASCII (accented vowels etc.) to its base letter.
  return out.normalize("NFKD").replace(/[̀-ͯ]/g, "");
}

const text = normalize(fs.readFileSync(0, "utf8"));
const words = text.split(/\s+/).filter(Boolean);
if (words.length === 0) {
  console.error("monkeytype_url: no words on stdin");
  process.exit(1);
}

const settings = [
  "custom",
  null,
  {
    text: words,
    mode: "repeat",
    limit: { mode: "word", value: words.length },
    pipeDelimiter: false,
  },
  null,
  null,
  null,
  null,
  null,
];

const payload = LZString.compressToEncodedURIComponent(JSON.stringify(settings));
process.stdout.write(`https://monkeytype.com/?testSettings=${payload}\n`);
