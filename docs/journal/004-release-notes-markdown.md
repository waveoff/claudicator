# 📓 Dev Journal #004 — Release Notes That Actually Look Like Release Notes

> **Series:** Claudicator Development Journal · Entry 004 of ∞
> **Date:** 2026-06-02
> **Milestone:** Markdown → HTML release notes in the Sparkle update window
> **Status:** ✅ Live — shipped in v0.6.1, confirmed in the real update dialog
> **Author:** Ari + Claude

---

## TL;DR

The Sparkle update window was showing release notes as **raw markdown** — literal
`### Fixed` and `- ` bullets — because `build-dmg.sh` only HTML-escaped the
CHANGELOG section and dropped it into the appcast `<description>` inside a
`white-space: pre-wrap` div. We added a **pure bash/sed/awk markdown→HTML step**
(no new dependencies, per the project rule) that turns headings, bullet lists,
italics, and paragraphs into real tags. Shipped as **v0.6.1** and verified
end-to-end: the live appcast carries `<h4>`/`<ul>`/`<li>`/`<em>`, and the actual
in-app update dialog now renders formatted text. This closes the follow-up flagged
in #003 (open question #6 / "inline release notes still render raw markdown").

---

## What shipped

- A markdown→HTML converter inside `build-dmg.sh`, between the CHANGELOG extraction
  (`NOTES_MD`) and the appcast write. Conversions:
  - `### Heading` → `<h4>Heading</h4>`
  - consecutive `- item` lines → `<ul><li>item</li>…</ul>`
  - `_italic_` → `<em>italic</em>`
  - blank-line-separated prose → `<p>…</p>`
  - hard-wrapped CHANGELOG lines (~80 cols) are **rejoined** into their block
- HTML-escaping of `&`, `<`, `>` still happens **first**, on the text content,
  before any tags are introduced — so notes text can't inject markup.
- Dropped `white-space: pre-wrap` from the `<description>` div (the notes are now
  proper block-level HTML, so pre-wrap would only add stray vertical space).

---

## How it works (the useful part)

The escape-then-convert ordering is what keeps it both safe and simple:

1. `sed` escapes `& < >` on the raw CHANGELOG text. The markdown markers we care
   about (`#`, `-`, `_`) are ASCII and untouched by escaping, so converting
   *after* escaping is both safe and order-independent.
2. `awk` walks line by line with a tiny state machine: `flush_para()` /
   `flush_item()` / `close_list()` open and close blocks as it sees blank lines,
   `### `, `- `, indented continuations, or plain prose.
3. Inline italics use POSIX `match()` + `substr()` (looping over `/_[^_]+_/`) —
   **not** `gensub()`, which BSD/macOS awk doesn't have. This matters: the release
   build runs on macOS awk, not gawk.

Two deliberate non-goals, confirmed correct against the real CHANGELOG: backtick
inline code like `` `### ` `` stays literal (we only transform **line-start**
markers), and an `_italic_` span that wraps across two source lines still closes
correctly because we rejoin the block before running the inline pass.

---

## Verification

Because the dev environment was Linux (no Xcode), the markdown step was verified
by running the exact `sed | awk` pipeline from the built script against the live
CHANGELOG, then validating the output with an HTML parser:

- Every released version (0.1.0–0.6.1) converts to well-formed, tag-balanced HTML
  with no leftover `### ` / leading `- ` in the rendered text.
- The **published** appcast (fetched from the GitHub release) carried
  `<sparkle:version>0.6.1</sparkle:version>` and an HTML `<description>`.
- Final proof: the real Sparkle dialog on macOS showed a bold **Fixed** heading,
  a true bullet, and italicized *italics*. Bug dead.

---

## Process notes (honest)

- This was cut as a **patch release whose own notes demonstrate the fix** — the
  0.6.1 CHANGELOG entry deliberately contains a heading, a bullet, and `_italics_`,
  so the update dialog shows all three conversions at once.
- The dev session had **read-only** access to the repo (both the git proxy and the
  GitHub App integration returned 403 on writes). So every change reached `master`
  via locally-run commands / PRs on Ari's Mac (PR #1 for the converter, PR #2 for
  the version bump), and the release itself was built and published from the Mac
  with `./build-dmg.sh --release`. Worth remembering: in that environment, "open a
  PR" means *prepare the change + hand over the push*, not push directly.

---

## Decisions

- **No dependencies:** markdown rendering stays in bash/sed/awk, consistent with
  the project's deliberate no-deps stance — no Python markdown lib, no Ruby, etc.
- **Small markdown subset only:** headings/lists/italics/paragraphs — exactly what
  the CHANGELOG uses. Not a general markdown engine.
- **Escape before convert:** safety first; generated tags are the only un-escaped
  HTML in the output.

---

## Open questions / follow-ups

- **Wider markdown:** `**bold**`, links, and nested lists aren't handled yet. Add
  them only if the CHANGELOG starts using them — don't gold-plate.
- Still inherits the unresolved items from #003 (Developer ID would consolidate the
  Gatekeeper + Keychain frictions; build-from-source needs an ad-hoc fallback).

---

<sub>← Previous: [#003 Auto-Updates](./003-auto-updates.md) · Next: _TBD_ · [Journal index](./index.md)</sub>
