# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

**Residents of Biliran province, Philippines** — the primary audience. They open Ziren
in two distinct situations, and the product serves both:

1. **In an emergency**, often one-handed, possibly at night, possibly in a storm, in a
   province where a "nearest station" can be a long way off.
2. **Routinely**, to check the status of a report they filed, to see alerts for their
   barangay, and to find the nearest BFP / PNP / MDRRMO station on a map.

They are not assumed to be confident smartphone users. Many are Filipino- or
Waray-speaking rather than English-speaking, on inexpensive Android hardware, on
intermittent mobile data.

**Responders** (BFP, PNP, MDRRMO field personnel) use the same app under a different
role: a duty switch and an assignment queue. **Dispatchers** work in the separate
Next.js dashboard, not this app.

## Product Purpose

Get a resident's emergency to the right agency, with a usable location, faster and
more reliably than a phone call to a station whose number they may not have.

Success is that a report reaches a dispatcher with enough structure to be triaged —
category, location, severity signals — and that the resident can tell it arrived.

## Positioning

Two mechanisms a neighbouring product could not truthfully copy:

- **It never lies about whether a report went through.** Connectivity is checked
  against the real backend, not just the phone's radio bars, and a report that could
  not be sent says so plainly — with a direct instruction to call 911 — rather than
  showing a success screen for something that never left the phone.
- **Severity is decided by an auditable rubric**, not a black box. Per-agency JSON rule
  configs produce a severity with provenance and an audit trail, so a dispatcher can
  see why an incident was rated as it was.

## Operating Context

- **Coverage is Biliran province**: 8 municipalities, 132 barangays. Location naming
  goes down to sitio level and the app deliberately declines to assert a barangay from
  a weak GPS fix.
- **Three agencies with fixed identities**: BFP (fire), PNP (police), MDRRMO (disaster).
  Routing to the correct one is the core dispatch decision.
- **Two shipped locales**: `en` and `fil`, chosen in Settings and mirrored to the
  resident's profile. Waray is the language of Biliran and is deliberately *not*
  shipped until a native speaker reviews the strings.
- **Connectivity is a first-class state**, checked and shown before a report is
  sent, not assumed: online means the backend actually answered, and offline means
  a report cannot be sent right now, not a hidden retry.

## Capabilities and Constraints

Confirmed and shipping:

- One-tap category reporting, a guided report wizard, and an SOS with a client-side
  cooldown.
- GPS capture that reports its own accuracy honestly and says when a fix is too loose
  to trust.
- Identity verification during registration using **on-device** ML Kit face detection
  and text recognition — no face or ID image leaves the handset.
- Media attachment, station map (MapLibre, self-hosted OSM tiles, no API key),
  notifications, and my-reports tracking.

Constraints:

- **Flutter, Material 3, phone-first, portrait**, shipping to inexpensive Android
  hardware. Performance budget is real.
- **The wizard's answer strings are a wire contract** with the backend triage service
  (`_AFFIRMATIVE_CHIPS`, `_STRUCTURE_MATERIALS`, `_COUNT_ANSWERS`). They cannot be
  localised until display label and submitted value are decoupled. Untested today.
- The bottom tab structure (`StatefulShellRoute`: Home / Map / Reports / Settings) is
  **fixed** and out of scope for redesign.

## Brand Commitments

- Name: **Ziren**.
- **Colour semantics are operational safety constraints, not style**, and are binding
  on any redesign. Documented in `lib/shared/theme/app_tokens.dart`:
  - brand orange `#FC5A05` = CTAs and active nav only; never severity, never errors.
  - red is reserved strictly for critical severity; the SOS control is the one
    deliberate extension, because it *means* critical emergency.
  - severity is a 4-tier scale always paired with icon + label, never colour alone.
  - agency hues are fixed: BFP red-coral, PNP sky-blue, MDRRMO emerald.
  - purple marks machine output only, never decoration.
- Tokens are kept in sync with `ziren_dashboard/app/globals.css`.
- Mobile uses the system font stack; no web font is loaded on Flutter.

## Evidence on Hand

- Real Biliran station data and place naming (`biliran_places.dart`, station
  repository), 132 barangays.
- A working rubric engine with per-agency configs and traceability.
- A golden design preview (`test/goldens/`) that renders the home kit without a
  Supabase session.
- **Absent, and not to be fabricated**: response-time statistics, adoption or user
  numbers, agency endorsements, uptime claims, testimonials. None exist. This is an
  unreleased capstone project, and no screen may imply otherwise.

## Product Principles

1. **The SOS is never demoted.** No state of the app — an open report, an error, a
   nudge — may come between a person and the emergency control.
2. **State the path before the commit.** Whether the phone can currently reach the
   server, and how good the location fix is, are shown before sending, not after.
3. **Never assert what is not known.** A weak GPS fix says so; an unknown barangay says
   so. Silence beats a confident wrong answer in dispatch.
4. **Colour carries operational meaning.** It is read under time pressure by people
   triaging incidents, and is never spent on decoration.
5. **Chores yield to emergencies.** Verification nudges and similar asks sit below the
   SOS and stay dismissable.

## Accessibility & Inclusion

- **Two languages shipped (`en`, `fil`)**; a screen that mixes them is a defect, not a
  cosmetic issue. Filipino is the primary language of the audience.
- **Reduced motion is honoured**: `MediaQuery.disableAnimations` gates the dial
  entrance and the SOS pulse.
- Severity and status are never colour-only; icon and label always accompany them.
- Minimum touch target 48dp; text contrast checked at ≥4.5:1 on the app background.
- Screen-reader labels are localised, and the SOS carries a spoken label plus haptic
  confirmation for use without looking at the screen.
- The audience includes people on cheap handsets and intermittent data; weight and
  offline behaviour are inclusion concerns here, not just performance.
