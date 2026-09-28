---
name: weekly-report
description: Build or update Ziren's SE2 weekly progress report (WEEKLY-N-PROGRESS-REPORT.docx) and its companion ZIREN-PROBLEM-EXPLANATIONS.docx — the three "Problems Solved This Week" entries, root-cause analysis, SE2 concept citations, evidence code blocks, and the reflection sections. Use this whenever the user mentions the weekly report, the progress report, "problems solved this week", the explanations doc, SE2 concepts for a problem, or asks to write up defects found during the week's work — even if they only say "gawin mo na yung report" or name a week number.
---

# Ziren SE2 Weekly Progress Report

Two `.docx` deliverables in the repo root move together every week:

- `WEEKLY-N-PROGRESS-REPORT.docx` — the graded submission.
- `ZIREN-PROBLEM-EXPLANATIONS.docx` — prose the user reads aloud when the instructor probes a problem.

Both are edited **in place** with `python-docx`. Never rebuild them from scratch — see [Why in-place](#why-in-place).

## The one rule that matters

The three problems must be **real defects found while actually working on Ziren**, with live evidence (a test output, an HTTP status, a DB error code, a log file). Fabricated problems collapse the moment the instructor asks a follow-up question, and the whole grade rests on that conversation.

If fewer than three genuinely hard problems surfaced this week, **say so and stop**. Do not pad with trivia like a typo fix or a missing import. Ask the user whether to dig through the week's git history and test runs for more, or to submit with fewer. Padding is worse than a short report.

What makes a good problem: silent failures, action-at-a-distance, defects a passing test suite actively hides, errors that name the wrong subsystem. The Week 2 set is the bar to clear — a shared Supabase singleton being mutated by a user sign-in, a DB trigger racing the provisioning endpoint, 500s losing their CORS headers so the frontend blamed a dead backend.

## Workflow

### 1. Find the problems

Before writing anything, gather the week's real material:

```
git -C c:\Dev\Ziren log --since="<week start>" --oneline
```

`ziren_backend` may still be untracked — check the conversation history, the migration files' comment headers (they are written as post-mortems, e.g. `017_grants_for_new_tables.sql`), and any `hs_err_pid*.log` / test output in the repo root. Those comment headers are often the single best source: root cause, failure mode, and fix already articulated.

For each candidate, you need: the symptom the user saw, the actual root cause, why the symptom pointed somewhere else, the fix, and a verbatim error string as evidence.

### 2. Read the existing document's structure first

Do not assume the section lettering or table count from a previous week — it drifts.

```
python .claude/skills/weekly-report/scripts/inspect_docx.py WEEKLY-2-PROGRESS-REPORT.docx
```

This prints every body paragraph with its index and style, plus every table as a grid. Use it to locate things **by their label text**, never by a remembered index.

Typical shape (Week 2): body paragraphs carry the headers and the summary sections; `table 0` is GROUP MEMBERS; `table 1` is the Project Status box; `tables 2..4` are the three problems, each **8 rows × 2 columns**:

| Row | Left cell | Right cell |
|-----|-----------|------------|
| 0 | `Field` | `Group's Response` |
| 1 | `N.1 Problem Statement` | what broke, from the user's point of view |
| 2 | `N.2 Root Cause Analysis` | the actual mechanism, naming files |
| 3 | `N.3 SE2 Concept Applied` | 4 paragraphs: concept, explanation, concept, explanation |
| 4 | `N.4 Solution Applied` | ☑-prefixed bullets |
| 5 | `N.5 Evidence` | `ERROR` label, code block, `SOLUTION` label, code block |
| 6 | `N.6 Assigned To` | name |
| 7 | `N.7 Status` | e.g. Resolved |

### 3. Cite the SE2 concept from the guide, in the guide's own words

Read `references/se2-concepts.md` — it is the full content of `SE2-CONCEPT-GUIDE.docx` extracted into text, so you do not have to parse the .docx every week. Quote the guide's definition, then explain how Ziren's specific code matches it.

Two concepts per problem works well: usually one design/structural concept (Singleton, Repository, Separation of Concerns, Test Double…) plus one maintenance classification (Corrective / Adaptive / Perfective / Preventive). The "Quick reference" table at the end of that file maps "if you did this → the concept is" and is the fastest way to pick honestly rather than picking whatever sounds impressive.

The instructor's likely question is *"why that concept and not another one?"* — so choose a concept the code genuinely demonstrates. A stretched citation is as fragile as a fabricated problem.

### 4. Edit in place

```python
import sys; sys.path.insert(0, r".claude/skills/weekly-report/scripts")
from docx_edit import (backup_docx, load, find_table_by_label, row_by_label,
                       set_paragraph_text, set_paragraph_lines, clone_paragraph_after)
```

Always `backup_docx(path)` first. Then locate by label, replace run text, save.

The helpers exist because the naive approach — `paragraph.text = "..."` — deletes every run and takes the formatting with it. `set_paragraph_text` keeps the first run and its font, colour, and size, then drops the rest.

### 5. Write the companion explanations

`ZIREN-PROBLEM-EXPLANATIONS.docx` has, per problem: a heading, then three bold question labels each followed by **exactly two body paragraphs**:

1. *Why is this a problem?*
2. *How did we fix it?*
3. *Why did we use that SE2 concept?*

This is spoken-defense prose, not report prose: plain sentences, no bullet lists, no code. The user should be able to read a paragraph out loud and sound like they understand the system — because they do.

### 6. Sanity check

Re-run `inspect_docx.py` on both files and confirm: three problem tables, every row filled, no `TODO` left, the evidence strings match the real errors, and the summary sections mention the same three problems the tables do.

## Gotchas that will bite

**The file is open in Word.** A `PermissionError` on save means exactly that. Ask the user to close it — do not work around it by writing to a new filename, because the next edit would then target the stale original.

**Console encoding.** Printing ☑ or — through PowerShell's cp1252 raises `UnicodeEncodeError` and kills the script mid-run. Every script here calls `sys.stdout.reconfigure(encoding="utf-8")`; keep that in any new one.

**`d.paragraphs` excludes paragraphs inside tables.** Body-level indices therefore do not line up with what you see in Word. This is the single most common way to edit the wrong thing. Locate by label text.

**Code blocks need real `<w:br/>` elements** between lines — a `\n` inside run text renders as one long line. `set_paragraph_lines` handles this via `run.add_break()`.

<a id="why-in-place"></a>
**Why in-place:** the dark `1E1E1E` Consolas code blocks, table borders, ☑ glyphs, heading numbering, and the List Paragraph styles are formatting a rebuild silently loses. The document then looks wrong to the instructor before a single word is read.

## Files

- `references/se2-concepts.md` — full SE2 concept guide, extracted. Read before citing a concept.
- `scripts/inspect_docx.py` — dump a .docx's paragraphs and tables with indices. Run first, run last.
- `scripts/docx_edit.py` — formatting-preserving edit helpers. Import, don't reimplement.
