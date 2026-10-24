---
name: ari-poem-limerick
description: Compose a limerick on any subject and verify its mechanics (AABBA rhyme, anapestic meter, syllable counts) against a strict grid before showing it. The user sees only the finished five lines.
---

# Limerick

Write a limerick that scans. The subject comes from the user; the mechanics come from
here. Drafting happens in a grid file, `bin/check` proves the grid, and the reply is the
five lines and nothing else.

## Rules

- **Form.** Five lines, rhyme scheme AABBA. Lines 1, 2, 5 (A) carry three beats; lines 3, 4
  (B) carry two.
- **Meter.** Anapestic: `da da DUM`. Beats fall every third syllable. The first foot may
  drop one unstressed syllable (`da DUM`), so the first beat lands on syllable 2 or 3.
  After the last beat, at most one unstressed syllable. No stressed syllable anywhere else.
- **Endings.** Within a rhyme group the ending type is consistent: all A lines end with a
  beat (masculine) or all end beat-plus-one (feminine); same for the B lines.
- **Rhyme.** By sound, not spelling. A lines share one rhyme sound, B lines another, and the
  two differ. `SHA` reads as "shah". No rhyming a word with itself.
- **Syllables and stress by pronunciation.** Say the word; count what you say. `every` is
  two, `fire` is one, `poem` is two. Stress follows the dictionary: `naNTUCKet`, not
  `NANtucket`. When a word could scan two ways, pick the reading a listener would hear and
  mark that.
- **Never bend the grid to the words.** If a line fails, change the words. Never relax a
  rule, never mark a stress you would not say aloud.
- **Output is the verse only.** The reply is exactly the five lines as plain text. No grid,
  no table, no counts, no commentary, no mention of checking or of the grid file, unless
  the user asks how a line was verified.

## Investigation folder

```
/tmp/poem-limerick/<UTC timestamp>/
└── grid.txt    # the syllable grid bin/check reads; drafts stay here too
```

`bin/init` creates it and prints `grid_file=`. One folder per run, so re-runs never
clobber a prior grid.

## Grid format

One line per verse line, in order. Each syllable is one token; stressed syllables are
UPPERCASE, unstressed lowercase. Word boundaries do not matter to the checker, so write
`nan TUCK et` or `nan-TUCK-et` as you like, as long as each syllable is its own token.
After ` | ` give the rhyme sound of the line's ending as you would say it. Blank lines and
`#` lines are ignored.

```
there ONCE was a MAN from nan TUCK et | uk-it
who KEPT all his CASH in a BUCK et    | uk-it
but his DAUGH ter named NAN           | an
ran a WAY with a MAN                  | an
and AS for the BUCK et nan TUCK et    | uk-it
```

## Workflow

### Take the subject

Use what the user gave. If there is no subject at all, ask for one line about it and stop.
Never invent facts about a real person or event; the subject material is the user's.

### Set up

```zsh
zsh $HOME/.claude/skills/ari-poem-limerick/bin/init
```

### Draft and prove

Write the five lines into `grid.txt` in the grid format, saying each line aloud in your
head to place stresses and count syllables. Then:

```zsh
zsh $HOME/.claude/skills/ari-poem-limerick/bin/check --grid <grid_file>
```

`check` prints one line per failure, naming the verse line and the rule it broke, and
exits non-zero. Fix by rewording the failing line, rewrite the grid, run `check` again.
Up to five cycles; if a line still fails, discard that line and write a different one.
Never present a verse `check` has not passed.

### Present

Read the words back off the grid (lowercase them, restore normal capitalization and
punctuation) and reply with the five lines. Nothing else.

## File storage

- `bin/init` — creates the investigation folder, prints `grid_file=`
- `bin/check` — verifies a grid file: line count, syllable tokens, beat placement, endings, rhyme
