# Ziren — live demo script

Six reports to type in during the defense. Each one lands on a **different
severity rule**, so the sequence walks the panel through the whole triage
story: a clear critical, a clear high, what happens when the model disagrees
with the resident, and what happens when it cannot read the report at all.

Every expected result below was produced by running the exact text through
`triage_service` on the machine that will serve the demo — engine
**v2.1.5**, `FLAG_THRESHOLD = 0.60`. They are recorded outputs, not
predictions. If what you see on screen differs from this table, something
changed and it is worth stopping to find out what.

**Before you start**

1. Backend running: `uvicorn app.main:app --reload --host 0.0.0.0`
2. `GET /health` shows `"model_loaded": true, "version": "2.1.5"`
3. Dashboard on the projector, **Live Queue** open
4. Phone on the same wifi, logged in as a Resident

---

## At a glance

| # | Language | Category tapped | Expected rule | Severity |
|---|---|---|---|---|
| 1 | Waray | Sunog / Fire | `SR002` someone is trapped | **CRITICAL** |
| 2 | Tagalog | Aksidente sa Daan | `SR006` injury reported | **HIGH** |
| 3 | Tagalog | Sunog / Fire *(deliberately wrong)* | `SR006` + **mismatch flag** | **HIGH** |
| 4 | Waray | Iba pa | `SR010` fail-safe | **MEDIUM** |
| 5 | Waray *(same text as #4)* | Medical / Trauma | `SR005B` medical floor | **HIGH** |
| 6 | Tagalog | Baha / Landslide / Kalamidad | `SR005D` hazard reached homes | **HIGH** |

Reports 4 and 5 are the same sentence. Run them back to back — the contrast
is the point.

---

## 1 · CRITICAL on entrapment (Waray)

**Type this:**

```
may sunog ha amon balay didi ha Barangay Atipolo, may naipit nga bata ha sulod
```

**Category:** Sunog / Fire
**Wizard answers:** Ano ang nasusunog? → **Bahay** · Kumakalat pa ba? → **Oo, kumakalat** · May nasugatan o nakulong? → **Oo**

**Expect:**

| | |
|---|---|
| Severity | **CRITICAL** |
| Rule | `SR002` — someone is trapped |
| Model read | FIRE @ **0.968** |
| Verification | AGREE |
| Agencies | BFP, MDRRMO |
| Signals | injured, entrapment, hazard spreading, structure involved, location: Atipolo |

**What to say:** Four signals were read, but only one decided the severity.
`SR002` sits second in the priority list — above structural fire, above injury
— because entrapment is time-critical in a way the others are not. The card
names that rule, so a dispatcher who disagrees knows exactly what to argue
with. Note that MDRRMO was added to BFP automatically: someone is trapped and
someone is hurt.

---

## 2 · HIGH on injury (Tagalog)

**Type this:**

```
may aksidente dito sa daan, nabangga ang motor, may sugatan
```

**Category:** Aksidente sa Daan
**Wizard answers:** Anong sasakyan? → **Motor** · May nasugatan? → **Oo**

**Expect:**

| | |
|---|---|
| Severity | **HIGH** |
| Rule | `SR006` — injury reported |
| Model read | VEHICULAR_ACCIDENT @ **0.996** |
| Verification | AGREE |
| Agencies | PNP, MDRRMO |
| Signals | injured |

**What to say:** The model was trained on Waray and Tagalog together, so this
scores at 0.996 without anyone switching a language setting. HIGH rather than
CRITICAL because one injury is not the same as three, or a fatality, or
someone trapped — `SR003`, `SR001` and `SR002` are the rules that escalate
past this one.

---

## 3 · The model disagrees — mismatch flag (Tagalog)

This is the one the panel will ask about. Tap the **wrong** category on
purpose.

**Type this:**

```
may nanaksak dito sa plaza, may dalang sundang, duguan ang tao
```

**Category:** Sunog / Fire ← *deliberately wrong*
**Wizard answers:** skip

**Expect:**

| | |
|---|---|
| Severity | **HIGH** |
| Rule | `SR006` — injury reported |
| Model read | CRIME @ **0.78** |
| Verification | **MISMATCH_FLAGGED** |
| Agencies | BFP, MDRRMO |
| Signals | injured, weapon mentioned |

On the dashboard the **WHY THIS SEVERITY** card shows:

> ⚠ **Category mismatch** — The text reads as a different category than the
> resident chose. Confirm before dispatch.

**What to say:** The model is 78% sure this is a crime, which is above the
0.60 flag threshold — and it still does not overrule the resident. Routing
stayed on the resident's Fire selection: BFP, not PNP. The resident is at the
scene and the model is not. What the system does instead is refuse to hide the
disagreement: it raises it, and a dispatcher decides.

**If asked "so the AI can be wrong and still route wrongly?"** — Yes, and that
is deliberate. Silently switching the category on a resident who can see the
fire would be worse. The incident is also marked `nlp_review_needed`, so it
carries the eye icon in the queue.

---

## 4 · Unreadable report — the fail-safe (Waray)

**Type this:**

```
waray ako maaram kun ano ini nga nahitabo didi
```

*("I don't know what happened here.")*

**Category:** Iba pa
**Wizard answers:** none

**Expect:**

| | |
|---|---|
| Severity | **MEDIUM** |
| Rule | `SR010` — no signals readable, fail-safe, route to a human |
| Model read | CRIME @ **0.323** |
| Verification | NO_SELECTION |
| Agencies | PNP — flagged `model_uncertain` |
| Agency basis | **needs manual agency** |
| Signals | *(none)* |

On the dashboard the **WHY THIS SEVERITY** card carries a second boxed
warning below the model reading:

> 👤 **Choose the responder manually**
> Agency suggested from a low-confidence model reading (0.32). Choose the
> responder manually. Suggested: **PNP** — treat this as a starting point,
> not a recommendation.

The queue card shows a compact **"pick agency"** marker for the same reason,
so it is visible before anyone opens the incident.

**What to say:** The model guessed CRIME, but only at 32% — well under the
0.60 threshold. Nothing in the text produced a usable signal, so `SR010`
fires and the report is parked at MEDIUM for a human. The system is saying
"I cannot read this", which is a better answer than a confident wrong one.

Then point at the second box. **Severity and agency are scored separately,
because they fail separately.** `SR010` can park the severity somewhere safe
while the agency beside it still rests on a coin-flip reading. Release 2.1.5
made that explicit: `agency_basis` is one of `user_selected`,
`model_confident`, or `model_uncertain`, and only the last one raises this
warning. The agencies are still returned — an emergency report must reach
someone — but the dispatcher is told to choose rather than handed a
suggestion dressed up as a recommendation.

**If asked "why suggest PNP at all if you don't trust it?"** — Because a
starting point beats a blank field at 2am. What changes is how it is
presented, not whether it exists.

---

## 5 · Same sentence, resident picks a category (Waray)

Run this immediately after #4, same text.

**Type this:**

```
waray ako maaram kun ano ini nga nahitabo didi
```

**Category:** Medical / Trauma
**Wizard answers:** none

**Expect:**

| | |
|---|---|
| Severity | **HIGH** |
| Rule | `SR005B` — medical category floor, a person is in distress |
| Model read | CRIME @ **0.323** *(unchanged)* |
| Verification | UNCERTAIN |
| Agencies | MDRRMO |
| Signals | *(none)* |

**What to say:** Identical text, identical model reading — different severity,
because the resident asserted something. Tapping "Medical" is a claim that a
person is in distress, and `SR005B` honours that claim even when the text is
unreadable.

This pairing is the fix in dataset release **2.1.4**. Before it, `SR005B`
fired on the model's *guess* too, so an unreadable report the model happened
to score as MEDICAL jumped to HIGH on a 25% hunch and skipped the `SR010`
fail-safe entirely. The rule now takes a `category_from_user` argument: a
resident's assertion always counts, a model guess only counts above the
threshold.

---

## 6 · Hazard reaching homes (Tagalog)

**Type this:**

```
baha na po dito sa amin, umaabot na sa loob ng mga bahay
```

**Category:** Baha / Landslide / Kalamidad
**Wizard answers:** Uri ng kalamidad? → **Baha** · Ilang pamilya ang apektado? → **6–20** · Kailangan ng evacuation? → **Oo, urgent**

**Expect:**

| | |
|---|---|
| Severity | **HIGH** |
| Rule | `SR005D` — hazard has reached homes |
| Model read | NATURAL_HAZARD @ **0.835** |
| Verification | AGREE |
| Agencies | MDRRMO |
| Signals | structure involved, people involved: 20 |

**What to say:** A flood in a field and a flood in a living room are not the
same call. `SR005D` is what separates them. Point at the **SIGNALS READ** row:
"structure involved" carries a dot, meaning the resident answered it in the
wizard rather than the model inferring it from the text. "people involved: 20"
came from the 6–20 band, read at its upper bound — in triage, over-estimating
a headcount is recoverable and under-estimating is not.

---

## The queue, after all six

Six incidents, ordered CRITICAL → HIGH → MEDIUM, and **every card names the
rule that put it there**. That is the sentence worth landing:

> Ziren does not say "the AI thinks this is HIGH." It says `SR006`, injury
> reported — a numbered rule, with the signals it fired on, and the confidence
> the model had. A dispatcher can disagree with a rule. Nobody can disagree
> with a black box.

---

## If something goes wrong live

| Symptom | Cause | What to say / do |
|---|---|---|
| Severity blank, card reads *"Not triaged · needs manual review"* | Model did not load | Check `/health`. The report still saved — that is the fail-safe working, and it is a fine thing to point at. |
| Phone: "Could not reach the server" | Backend not on `--host 0.0.0.0`, or `API_BASE_URL` is a stale LAN IP | `ipconfig`, then relaunch the app with the current IP. Config is compile-time; hot reload will not pick it up. |
| Severity appears but no rule text | `signals` missing from the response | Backend older than the Phase 4 wiring. |
| Rule id differs from this table | Different engine version | Check `/health` — this script is pinned to **v2.1.5**. |
