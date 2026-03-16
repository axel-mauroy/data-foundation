---
name: Code Review (Human-Centric)
description: How to conduct effective, humane code reviews that improve code quality without damaging team relationships. Based on mtlynch.io/human-code-reviews-1 and /human-code-reviews-2.
---

# Code Review Best Practices — Dealinka

> The goal of a code review is to improve the code **and** to preserve the relationship with the author. If your review achieves one and destroys the other, it has failed.

---

## 🧠 Chain-of-Thought: How to Structure a Review

When you receive a changelist, reason through it **in this order**:

1. **Let automation run first.** Has CI passed? Has `dbt build` / `pre-commit` / `sqlfluff` flagged anything? Do not reproduce machine work in human comments.
2. **Is the scope acceptable?** More than ~400 lines → request a split before reviewing. More than 1,000 lines → refuse and request a split.
3. **Start high-level.** What is the overall design? Does this changelist introduce a layer violation (Silver read in ZenML), a missing schema contract, or a missing GX gate? Address these first. Do not nitpick variable names until design issues are resolved.
4. **Work your way down.** Once macro issues are addressed in a later round, focus on readability, naming, and test coverage.
5. **Is the code at D level or better?** Aim to bring it to C or B — not A+. Chasing perfection over 8+ rounds destroys the relationship. An F (functionally incorrect or non-idempotent) is the only hard blocker.
6. **Grant approval early when possible.** If remaining notes are trivial fixes or optional suggestions, add LGTM + mark them optional. Don't hold up a merge over a typo.

---

## ✅ / ❌ Few-Shot Examples

### Framing feedback

❌ **WRONG — accusatory, uses "you", sounds like a command:**
> "You forgot to add the `PARTITION BY` clause. Fix it."

✅ **CORRECT — frames as request, ties to principle, omits "you":**
> "Consider adding `PARTITION BY DATE(declared_at)` here — without it, every BQML training query will do a full table scan, bypassing our cost controls."

---

### Responding to a style disagreement

❌ **WRONG — personal opinion with no anchor:**
> "I prefer snake_case for CTEs. Please rename them all."

✅ **CORRECT — defers to the shared style guide:**
> "Our dbt style guide (Section 9.5) uses snake_case for CTEs. Would it be possible to align with that here?"

---

### Handling a repeated pattern

❌ **WRONG — flags every single instance (25 comments):**
> Comments on lines 12, 45, 78, 110, … all saying "missing `not_null` constraint."

✅ **CORRECT — call out 2 examples, then ask for a global fix:**
> "Noticed `declaration_id` (line 12) and `company_id` (line 45) are missing `not_null` constraints. Could we do a pass to add them to all primary and foreign key columns per our schema contract rule?"

---

### Code examples in feedback

❌ **WRONG — vague suggestion, forces author to research:**
> "Can we make this more Pythonic?"

✅ **CORRECT — provide the refactored version directly (limit to 2–3 examples per round):**
> "Consider the Polars expression chain instead — it's immutable and avoids the `inplace` footgun:
> ```python
> df.with_columns(pl.col("quantity_kg").fill_null(0.0))
> ```"

---

## 🔧 The 12 Techniques Quick Reference

### Part One — Communication
| # | Technique | Dealinka application |
| :--- | :--- | :--- |
| 1 | **Let computers do boring parts** | `pre-commit` runs `sqlfluff`, `black`, `isort` before review; CI runs `dbt build`. **Never** write a human comment about indentation or import order. |
| 2 | **Settle style with a style guide** | Hard disputes → defer to `dbt_project.yml` conventions, Section 9.5 of dbt SKILL.md, or Google SQL style guide. Don't debate, link. |
| 3 | **Start reviewing immediately** | Max **1 business day** turnaround on any round, regardless of size. Blocked teammate = wasted sprint capacity. |
| 4 | **Start high-level, work down** | Round 1: architecture / layer violations / idempotency. Round 2+: naming, comments, edge cases. |
| 5 | **Be generous with code examples** | Provide a corrected SQL/Python snippet when the fix is non-obvious. Limit to **2–3 per round** to avoid rewriting the whole PR for them. |
| 6 | **Never say "you"** | Replace "you forgot…" → "consider adding…" or "this could be…" |
| 7 | **Frame as requests, not commands** | "Move this to a separate model." → "Would it make sense to extract this into an intermediate model?" |
| 8 | **Tie notes to principles** | "This violates idempotency" > "I don't like this." Link to the relevant rule in `DataEngineering.md` or the dbt skill. |

### Part Two — Process
| # | Technique | Dealinka application |
| :--- | :--- | :--- |
| 9 | **Aim for B, not A+** | D → C is a successful review. Don't block a merge for 8 rounds chasing purity. |
| 10 | **Limit feedback on repeated patterns** | Flag 2 examples, then say "let's apply this pattern globally." |
| 11 | **Respect the scope** | If a line isn't in the diff, it's out of scope. File a separate issue instead. |
| 12 | **Split large PRs** | >400 lines → request a split. >1,000 lines → refuse to review until split. Identify logical split points when proposing this. |
| 13 | **Offer sincere praise** | Call out smart implementations explicitly: "Using `SAFE_DIVIDE` here is exactly right — prevents silent division errors in the acceptance rate." |
| 14 | **Grant early approval** | Trivial outstanding fixes (typos, minor naming) → add LGTM and mark them optional. Don't block on punctuation. |
| 15 | **Handle stalemates proactively** | Tone getting tense? → Meet synchronously. Design disagreement? → Escalate to a design review with the full team. Don't let it rot in async text. |

---

## 🎯 Dealinka-Specific Review Checklist

When reviewing a **dbt PR**, check these in order:

**Round 1 — Architecture (block if violated):**
- [ ] Does the model reference the correct layer? (`stg_` reads only from `source()`, marts only from `ref()`)
- [ ] Is the contract enforced on every Silver model? (`contract: enforced: true`)
- [ ] Is the Gold model idempotent? (`CREATE OR REPLACE` / partition overwrite)
- [ ] Is PII stripped before the Gold layer? (no `contact_email`, `vat_number` in `mart_*`)
- [ ] Is a GX expectation suite referenced for this model?

**Round 2 — Quality (suggest if missing):**
- [ ] Is there at least `unique` + `not_null` on the primary key?
- [ ] Does every column have a `description` in `schema.yml`?
- [ ] Is the materialization appropriate? (`view` for staging, `ephemeral` for intermediate, `table` for marts)

**Round 1 — Architecture (block if violated) for ZenML PRs:**
- [ ] Does the step read from `gold.mart_*` only?
- [ ] Is every step return type explicitly typed (`pl.DataFrame`, `bytes`)?
- [ ] Is `enable_cache=False` set only on ingestion steps?
- [ ] Is the pipeline linked to the Model Control Plane?

---

## 🛑 Hard Blockers (withhold approval until fixed)

These are the only reasons to withhold final approval outright:

| Blocker | Why |
| :--- | :--- |
| ZenML step reads from Bronze or Silver | Violates Gold-only gate — could train on uncleaned data |
| Missing `contract: enforced: true` on Silver model | Schema drift will propagate silently to Gold |
| `WRITE_APPEND` without deduplication | Non-idempotent — reruns will duplicate data |
| PII column present in Gold mart | RGPD violation |
| `dbt build` or CI fails | Functionally broken code |

---

**Senior MLOps Architect Summary:**
A good code review transfers knowledge, improves the code by one letter grade, and leaves the author wanting to send you more PRs. The only objective hard blocker is functionally broken or RGPD-violating code — everything else is negotiable.
