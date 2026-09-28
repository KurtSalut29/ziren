# Responder-Side Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the responder Home, Reports, and Profile screens in line with `docs/specs/2026-09-11-responder-redesign-design.md` — drop redundant Home controls, add the free-but-unused "oldest waiting" stat, split Reports into List/Record views, add a shift summary to Profile, and consolidate the responder-only shared widgets into one pattern-library file.

**Architecture:** Pure Flutter UI changes inside `ziren_mobile`. No backend changes (the spec's vehicle-type and certifications proposals are explicitly deferred, not part of this plan). Content/behavior changes land first per screen, each verified live on device; the `responder_kit.dart` extraction is a separate, final, behavior-preserving refactor so it can be verified purely by "nothing changed."

**Tech Stack:** Flutter (Dart), `provider` state management, existing `ZirenTokens`/`ResponderProvider`/`ResponderVocabulary`/`ResponderTrends` — no new packages.

**Spec:** `docs/specs/2026-09-11-responder-redesign-design.md`

## Global Constraints

- `flutter analyze` (run from `ziren_mobile/`) must report the same 3 pre-existing infos it does today (BuildContext-across-async-gap, deprecated MaplibreMap, package-name-casing) and nothing new, after every task.
- Every screen touched must be verified live on the connected device (id `1480270594007084`) via `adb exec-out screencap -p`, logged in as the responder test account (`markanthonyreyes@gmail.com` / `TestPass123`), before its task is considered done. The backend must be reachable at `http://192.168.100.9:8000` (confirm with `curl -s -o /dev/null -w '%{http_code}' http://192.168.100.9:8000/health` before starting — if it's not 200, start it per the `ziren-dev` skill before continuing).
- `dart_defines.json` already points `API_BASE_URL` at `http://192.168.100.9:8000` — do not change it as part of this work.
- Run `dart format <file>` on every file touched, before the task's final `flutter analyze` check.
- New/changed user-facing strings that live in a file where every other label already goes through `AppLocalizations` (this applies to `responder_profile_screen.dart`) must be added to both `lib/l10n/app_en.arb` and `lib/l10n/app_fil.arb`, followed by `flutter gen-l10n`. Strings added to `responder_home_screen.dart` or `responder_reports_screen.dart` may stay as plain Dart string literals — every existing user-facing string in those two files today is already a plain literal (`'Currently On-Duty'`, `'My reports'`, etc.), so a new literal matches the file's own established convention rather than introducing a one-off translated string next to untranslated ones.
- No task deletes the `ClosedPerDayChart`/`SeverityMixRing`/`ResponderTrends` code — it is proven-working and gets rewired, not rebuilt.

---

### Task 1: Add the two new Profile localization keys

**Files:**
- Modify: `ziren_mobile/lib/l10n/app_en.arb`
- Modify: `ziren_mobile/lib/l10n/app_fil.arb`

**Interfaces:**
- Produces: `AppLocalizations.respProfileResolvedPeriod` (`String`), `AppLocalizations.respProfileTypicalResponse` (`String`) — consumed by Task 4.

- [ ] **Step 1: Add the English keys**

Open `ziren_mobile/lib/l10n/app_en.arb`. Find the existing `respProfileWaitingToSend` entry (currently the last key inside the Profile-shift group, around line 1219) and add two new keys immediately after its `@respProfileWaitingToSend` metadata block:

```json
  "respProfileWaitingToSend": "Waiting to send",
  "@respProfileWaitingToSend": {
    "description": "Responder app: Waiting to send"
  },
  "respProfileResolvedPeriod": "Resolved this period",
  "@respProfileResolvedPeriod": {
    "description": "Responder app: Profile shift summary — incidents resolved in the current 30-day dashboard window"
  },
  "respProfileTypicalResponse": "Typical response time",
  "@respProfileTypicalResponse": {
    "description": "Responder app: Profile shift summary — median minutes from dispatch to close"
  },
```

(Only the two new keys are additions — `respProfileWaitingToSend` and its metadata block already exist; find-and-replace the existing block with itself plus the two new entries appended.)

- [ ] **Step 2: Add the Filipino keys**

Open `ziren_mobile/lib/l10n/app_fil.arb`. Find the existing `"respProfileWaitingToSend": "Naka-antabay na ipadala",` line and add two new keys immediately after it (this file has no `@key` metadata blocks — match that):

```json
  "respProfileWaitingToSend": "Naka-antabay na ipadala",
  "respProfileResolvedPeriod": "Naresolba ngayong panahon",
  "respProfileTypicalResponse": "Karaniwang oras ng pagtugon",
```

- [ ] **Step 3: Validate both arb files are well-formed JSON**

Run: `cd ziren_mobile && node -e "JSON.parse(require('fs').readFileSync('lib/l10n/app_en.arb','utf8')); JSON.parse(require('fs').readFileSync('lib/l10n/app_fil.arb','utf8')); console.log('OK')"`
Expected: `OK` printed, no exception.

- [ ] **Step 4: Regenerate the localization Dart files**

Run: `cd ziren_mobile && flutter gen-l10n`
Expected: exits 0, no errors. Confirm the two new getters exist:
Run: `grep -n "respProfileResolvedPeriod\|respProfileTypicalResponse" ziren_mobile/lib/l10n/app_localizations_en.dart`
Expected: both names appear.

- [ ] **Step 5: Analyze**

Run: `cd ziren_mobile && flutter analyze`
Expected: same 3 pre-existing infos, nothing new (the new getters aren't consumed until Task 4, so this just confirms generation didn't break anything).

- [ ] **Step 6: Commit**

```bash
cd ziren_mobile
git add lib/l10n/app_en.arb lib/l10n/app_fil.arb lib/l10n/app_localizations*.dart
git commit -m "$(cat <<'EOF'
feat(responder): add profile shift-summary l10n keys

Adds respProfileResolvedPeriod and respProfileTypicalResponse,
consumed by the Profile shift-summary rows added in a later task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Home — drop redundant quick-action tiles, swap the stat cell, add the duty-switch a11y label

**Files:**
- Modify: `ziren_mobile/lib/features/responder/presentation/responder_home_screen.dart`

**Interfaces:**
- Consumes: `ResponderProvider.oldestWaitingMinutes` (`int?`, already exists), `ResponderVocabulary.waiting(int?)` (`String`, already exists).
- No new public interfaces produced.

- [ ] **Step 1: Swap the stat band's third cell from "Typical" to "Oldest waiting"**

In `responder_home_screen.dart`, find the `ResponderStatBand` call (currently around line 207-232). Replace the third `ResponderStat` entry:

```dart
                  ResponderStat(
                    icon: Icons.timer_rounded,
                    // Median, not mean, and null until a first incident has
                    // closed. "0m" on a new account would be a flattering lie.
                    value: ResponderVocabulary.minutes(
                      provider.medianResponseMinutes,
                    ),
                    label: t.respStatTypical,
                    color: ZirenTokens.statusProcessing,
                  ),
```

with:

```dart
                  ResponderStat(
                    icon: Icons.hourglass_bottom_rounded,
                    // Oldest waiting, not median response time — this row is
                    // about what needs attention right now, and a
                    // retrospective "how am I doing" number belongs on
                    // Reports/Profile instead. Null (nothing open) reads as
                    // "—" via ResponderVocabulary.waiting, same as every
                    // other empty figure in this app.
                    value: ResponderVocabulary.waiting(
                      provider.oldestWaitingMinutes,
                    ),
                    label: t.respStatOldest,
                    color: ZirenTokens.severityHigh,
                  ),
```

Also update the doc comment directly above the `ResponderStatBand(` call (currently explaining why there are 3 cells not 4) — replace its last two sentences:

```dart
              // Three cells, not the prototype's four — "Duty
              // Schedule" in the reference design has no backing data (shift
              // scheduling is not a feature of this product yet), and a
              // placeholder that never reads anything but "—" is a worse use
              // of the slot than a number that is real every time: Critical
              // is the one figure on this screen with actual safety weight.
```

with:

```dart
              // Three cells, not the prototype's four — "Duty
              // Schedule" in the reference design has no backing data (shift
              // scheduling is not a feature of this product yet), and a
              // placeholder that never reads anything but "—" is a worse use
              // of the slot than a number that is real every time. Oldest
              // waiting replaces the median-response-time cell that used to
              // sit here: that number answers "how am I doing generally",
              // which belongs on Reports/Profile, not on the one screen built
              // for "what needs me right now" — see
              // docs/specs/2026-09-11-responder-redesign-design.md §4.
```

- [ ] **Step 2: Drop the "View My Tasks" and "Report Unit Status" tiles**

Find the Quick actions `Padding`/`Row` block (currently around lines 234-294). Replace the whole block, including its doc comment, with:

```dart
              // ── Quick action ───────────────────────────────
              //
              // One shortcut, not three. "View My Tasks" used to open the
              // Reports tab — a bottom-nav icon directly below this — and
              // "Report Unit Status" used to toggle duty, which is the card
              // directly above this. Both were shortcuts to something already
              // one tap away or already on screen; under an alert-glance
              // read, three saturated colour tiles that mostly duplicate
              // visible controls cost scan time for no real gain. Only
              // "Awaiting Dispatch" survives: it is a genuine shortcut,
              // jumping straight into the worst-ranked open assignment
              // without a scroll — the same job the deleted
              // PendingResponseCard used to do. See
              // docs/specs/2026-09-11-responder-redesign-design.md §4.
              if (sorted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space16,
                    kHomeGutter,
                    0,
                  ),
                  child: _QuickActionTile(
                    icon: Icons.notifications_active_rounded,
                    label: 'Awaiting Dispatch',
                    color: ZirenTokens.brandOrange,
                    badgeCount: queue.length,
                    onTap:
                        () => context.push(
                          '/responder/incident/${sorted.first.id}',
                        ),
                  ),
                ),
```

Note the tile is now full-width (no `Row`/`Expanded` siblings) and only renders when there's something to jump to — an empty state with a still-tappable "Awaiting Dispatch" tile that goes nowhere would be worse than not showing it.

- [ ] **Step 3: Update `_QuickActionTile` for full-width, single-line label**

The tile's `label` used to be two lines (`'Awaiting\nDispatch'`) to fit a third of the row; now it's the only tile, so it should read as one line, left-aligned with the icon beside it rather than stacked above it (a full-width tile stacking icon-over-single-word-per-line reads oddly wide). Find the `_QuickActionTile` class (currently around line 1085-1164) and replace its `build` method's `Padding`/`Column` body:

```dart
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space12,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  if (badgeCount != null && badgeCount! > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
```

Also update the class doc comment above it (currently "Three colour-coded shortcuts, matching the reference design's dashboard tiles...") to:

```dart
// ── Quick action tile ───────────────────────────────────────────
//
// One shortcut into the app's real "what's most urgent" feature — see the
// call site for why the other two tiles from the reference design were
// dropped.
```

- [ ] **Step 4: Add the duty-switch accessibility label**

Find `DutyStatusCard`'s `build` method (currently around line 707-855). Locate the `Switch.adaptive(...)` (currently around lines 774-781) and wrap it:

```dart
                  else
                    Semantics(
                      toggled: onDuty,
                      label: onDuty ? 'Go off duty' : 'Go on duty',
                      child: ExcludeSemantics(
                        child: Switch.adaptive(
                          value: onDuty,
                          onChanged: onChanged,
                          activeTrackColor: Colors.white.withValues(
                            alpha: 0.35,
                          ),
                          activeColor: Colors.white,
                          thumbColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
```

(`ExcludeSemantics` stops the switch's own generic "on/off" announcement from doubling up with the descriptive outer label. Hardcoded English literal, matching this widget's existing `'Currently On-Duty'`/`'Off Duty'` strings, which are also not yet localized — see Global Constraints.)

- [ ] **Step 5: Format and analyze**

Run: `cd ziren_mobile && dart format lib/features/responder/presentation/responder_home_screen.dart`
Run: `cd ziren_mobile && flutter analyze lib/features/responder/presentation/responder_home_screen.dart`
Expected: no issues.

- [ ] **Step 6: Rebuild and verify live — stat cell and single tile**

```bash
cd ziren_mobile
flutter run --dart-define-from-file=dart_defines.json -d 1480270594007084 > /tmp/rh_task2.log 2>&1 &
```

Wait for `Syncing files to device` in the log (poll every few seconds, don't sleep-loop blindly), then:

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/task2_home.png
```

Read `/tmp/task2_home.png`. Confirm: the 3rd stat cell now reads "Longest waiting" with an hourglass icon (not "Typical"), and there is exactly one full-width orange "Awaiting Dispatch" tile below the stat row (not three tiles).

- [ ] **Step 7: Verify the empty-queue case doesn't show a dead tile**

If the test account currently has an open assignment (it does, per this session's earlier verification — incident `INC-03D497`), temporarily confirm the guard by reading the code path rather than manufacturing an empty account: re-check Step 2's `if (sorted.isNotEmpty)` guard is present around the tile in the file (`grep -n "if (sorted.isNotEmpty)" lib/features/responder/presentation/responder_home_screen.dart` should show it directly above the tile's `Padding`). This confirms the tile cannot render with a broken `onTap` when the queue is empty, without needing to fabricate an empty test account.

- [ ] **Step 8: Verify the duty-switch semantic label with a manual toggle**

```bash
adb -s 1480270594007084 shell uiautomator dump //sdcard/ui_task2.xml
adb -s 1480270594007084 pull //sdcard/ui_task2.xml /tmp/ui_task2.xml
grep -o 'class="android.widget.Switch"[^>]*bounds="\[[0-9,]*\]\[[0-9,]*\]"' /tmp/ui_task2.xml
```

Tap the switch's bounds center with `adb -s 1480270594007084 shell input tap <x> <y>`, then screenshot again and confirm the duty card flips to green "Currently On-Duty". Tap it again to leave the account back in its original off-duty state. (This confirms the toggle still functions after being wrapped in `Semantics`/`ExcludeSemantics` — a common way to accidentally eat touch events. If the tap doesn't register, the wrapping broke hit-testing and needs to be a `Semantics` sibling that still passes the child through directly — re-check `ExcludeSemantics` didn't get placed with `excluding: false` or similar by mistake.)

- [ ] **Step 9: Commit**

```bash
cd ziren_mobile
git add lib/features/responder/presentation/responder_home_screen.dart
git commit -m "$(cat <<'EOF'
feat(responder): trim Home to one quick action, add oldest-waiting stat

Drops the "View My Tasks" and "Report Unit Status" tiles (both
duplicated a control already one tap away or already on screen),
keeping only "Awaiting Dispatch". Swaps the stat band's third cell
from median response time (a retrospective figure) to oldest-waiting
(an urgent one), using a dashboard field that was already fetched and
unused. Adds a descriptive accessibility label to the duty switch.

Spec: docs/specs/2026-09-11-responder-redesign-design.md §4
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Home — highlight the top queue card when a new item arrives

**Files:**
- Modify: `ziren_mobile/lib/features/responder/presentation/responder_home_screen.dart`

**Interfaces:**
- Consumes: `ResponderQueueCard` (existing, this task adds a `highlighted` field to it), `sorted` (`List<ResponderIncidentModel>`, already computed in `build()`).
- Produces: `ResponderQueueCard.highlighted` (`bool`, default `false`) — no other task consumes this.

- [ ] **Step 1: Add highlight-tracking state to `_ResponderHomeScreenState`**

Add `import 'dart:async';` to the top of the file (needed for `Timer`) — check it's not already imported first: `grep -n "^import 'dart:async'" lib/features/responder/presentation/responder_home_screen.dart`. If absent, add it as the first import line.

In `_ResponderHomeScreenState` (currently starting around line 50), add two fields right after the class's existing comment about the breathing pulse:

```dart
class _ResponderHomeScreenState extends State<ResponderHomeScreen> {
  // The breathing pulse went with the dial. A switch that throbs is a switch
  // that looks broken, and nothing else on this screen is a live indicator.

  /// The top-ranked queue item's id as of the last frame, so a NEW top item
  /// can be told apart from the screen simply rebuilding with the same one.
  String? _lastTopId;

  /// The id currently being highlighted, or null. Compared by id rather than
  /// tracking "the top card" by position, so the highlight follows the
  /// specific new incident even if the rest of the queue reorders under it.
  String? _highlightedId;
  Timer? _highlightTimer;
```

- [ ] **Step 2: Dispose the timer**

Add a `dispose()` override (this class doesn't have one yet — add it after `initState()`, which currently ends around line 73):

```dart
  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }
```

- [ ] **Step 3: Add the detection method**

Add this method anywhere in the class body, e.g. directly after `_refresh`:

```dart
  /// Briefly highlights a newly-arrived top-of-queue item.
  ///
  /// Runs from a post-frame callback in build(), never from inside build()
  /// itself — comparing and possibly calling setState synchronously during
  /// build is the standard way to trigger "setState called during build".
  /// A responder looking at Home when a dispatch lands should see something
  /// move, not just a silently incremented number.
  void _maybeHighlightNewTop(String? topId) {
    if (topId == null) {
      _lastTopId = null;
      return;
    }
    if (_lastTopId != null && _lastTopId != topId && mounted) {
      _highlightTimer?.cancel();
      setState(() => _highlightedId = topId);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedId = null);
      });
    }
    _lastTopId = topId;
  }
```

- [ ] **Step 4: Call it from `build()` and wire `highlighted` into the queue cards**

In `build()`, immediately after the `sorted` list is computed (currently `final sorted = ResponderVocabulary.sorted(queue);` around line 137), add:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHighlightNewTop(sorted.isEmpty ? null : sorted.first.id);
    });
```

Then find the `ResponderQueueCard(` call inside the queue-rendering `for` loop (currently around lines 375-391) and add one field to it:

```dart
                        ResponderQueueCard(
                          // 1-based, and assigned over the SORTED list, so the
                          // number means place in the working order rather
                          // than position in whatever order the API returned.
                          rank: i + 1,
                          incident: sorted[i],
                          color: ResponderVocabulary.color(sorted[i].severity),
                          icon: ResponderVocabulary.icon(sorted[i].severity),
                          elapsed: ResponderVocabulary.elapsed(
                            sorted[i].createdAt,
                          ),
                          highlighted: sorted[i].id == _highlightedId,
                          onTap:
                              () => context.push(
                                '/responder/incident/${sorted[i].id}',
                              ),
                        ),
```

- [ ] **Step 5: Add the `highlighted` field and animated styling to `ResponderQueueCard`**

Find the `ResponderQueueCard` class (currently around line 414). Add the field to its constructor:

```dart
class ResponderQueueCard extends StatelessWidget {
  const ResponderQueueCard({
    super.key,
    required this.rank,
    required this.incident,
    required this.color,
    required this.icon,
    required this.elapsed,
    required this.onTap,
    this.highlighted = false,
  });

  /// Place in the working order, 1-based. The prototype puts it first on the
  /// card and so does this: it is the only thing on the row that answers
  /// "which of these do I take", and every other field answers "what is it".
  final int rank;
  final ResponderIncidentModel incident;
  final Color color;
  final IconData icon;
  final String elapsed;
  final VoidCallback onTap;

  /// True for ~2s right after this incident became the new top of the queue
  /// while Home was open. Purely visual — never affects ordering or data.
  final bool highlighted;
```

Then in `build()`, find the outer `Material`/`InkWell`/`Container` (currently starting `return Material(` around line 458). Change the innermost `Container`'s `decoration` from a plain `BoxDecoration` to one that reacts to `highlighted`, and wrap it in `AnimatedContainer` instead of `Container` so the change animates:

```dart
    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: AnimatedContainer(
          duration: ZirenTokens.motionBase,
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(ZirenTokens.space10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            color:
                highlighted ? color.withValues(alpha: 0.08) : Colors.transparent,
            border: Border.all(
              color:
                  highlighted
                      ? color
                      : ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
            ),
          ),
```

The closing tag for this widget (currently `),\n      ),\n    );\n  }\n}` a few hundred lines down at the end of `ResponderQueueCard.build`) does not need to change — `AnimatedContainer` and `Container` both close the same way. Only the opening tag and its `decoration`/`color` changed.

- [ ] **Step 6: Format and analyze**

Run: `cd ziren_mobile && dart format lib/features/responder/presentation/responder_home_screen.dart`
Run: `cd ziren_mobile && flutter analyze lib/features/responder/presentation/responder_home_screen.dart`
Expected: no issues.

- [ ] **Step 7: Verify live — the highlight actually fires**

This needs a real change in top-of-queue, which requires either a second, more urgent incident to arrive, or accepting that this is hard to trigger from a live device without dispatcher access. Verify what's practical:

```bash
cd ziren_mobile
flutter run --dart-define-from-file=dart_defines.json -d 1480270594007084 > /tmp/rh_task3.log 2>&1 &
```

Wait for launch, screenshot Home, and at minimum confirm via `flutter analyze` plus a code read that `_lastTopId` starts `null` on first build (so the *very first* load — which always looks like "a new top arrived" from a fresh state — does NOT highlight, matching Step 3's `_lastTopId != null` guard). Read the file once more after formatting to confirm that guard is intact: `grep -n "_lastTopId != null && _lastTopId != topId" lib/features/responder/presentation/responder_home_screen.dart` should show exactly the line from Step 3. If genuinely triggering a live second-incident arrival is impractical in this session, this is acceptable to verify by code-reading plus the screenshot confirming the *steady-state* screen (no incident mid-arrival) renders identically to Task 2's screenshot — i.e., confirm the feature is inert with no visual regression when nothing new has arrived, since that is the common case and the one most likely to break something if the guard logic were wrong.

- [ ] **Step 8: Commit**

```bash
cd ziren_mobile
git add lib/features/responder/presentation/responder_home_screen.dart
git commit -m "$(cat <<'EOF'
feat(responder): highlight Home's top queue card on new arrival

A ~2s tinted-border pulse on whichever incident becomes the new
top-of-queue while Home is open, so a responder looking at the screen
when a dispatch lands sees something change rather than a silently
incremented number. Tracked by incident id via a post-frame callback,
not during build, to avoid setState-during-build.

Spec: docs/specs/2026-09-11-responder-redesign-design.md §4
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Reports — add the List / Record segmented control

**Files:**
- Modify: `ziren_mobile/lib/features/responder/presentation/responder_reports_screen.dart`

**Interfaces:**
- Consumes: `ClosedPerDayChart`, `SeverityMixRing` (from `widgets/responder_charts.dart`, unchanged), `ResponderTrends.closedPerDay`/`.windowIsTruncated`/`.severityMix`/`.medianMinutes` (from `domain/responder_trends.dart`, unchanged), `ResponderProvider.history` (already consumed by this file today).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add the new imports**

At the top of `responder_reports_screen.dart`, add two imports (the file currently imports `home_kit.dart`, `responder_incident_model.dart`, `responder_provider.dart`, `responder_vocabulary.dart` — add these alongside them):

```dart
import '../domain/responder_trends.dart';
import 'widgets/responder_charts.dart';
```

- [ ] **Step 2: Add a view-mode enum and state field**

Find the existing `enum _Filter { all, active, closed }` (currently line 44). Add a second enum right after it:

```dart
enum _Filter { all, active, closed }

enum _View { list, record }
```

In `_ResponderReportsScreenState`, add a field next to `_filter` (currently line 47):

```dart
  _Filter _filter = _Filter.all;
  _View _view = _View.list;
```

- [ ] **Step 3: Add the segmented control, between the subtitle and the filter row**

Find the subtitle `Padding` (currently lines 138-147, the `'Everything a dispatcher has sent you.'` text) and the filter-row `Padding` right after it (currently starting line 150). Insert a new `Padding` between them:

```dart
              const Padding(
                padding: EdgeInsets.fromLTRB(kHomeGutter, 4, kHomeGutter, 0),
                child: Text(
                  'Everything a dispatcher has sent you.',
                  style: TextStyle(
                    fontSize: 13,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),

              // ── List / Record ───────────────────────────────
              //
              // Two different questions, not one long scroll: "where is that
              // report" (List) and "how has my shift/record been" (Record).
              // Stacking a chart section below a potentially-long list is the
              // same "too much on one screen" mistake Home just had — this
              // avoids repeating it by making it a choice instead of a scroll.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space16,
                  kHomeGutter,
                  0,
                ),
                child: _ViewToggle(
                  view: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),

              // ── Filters ───────────────────────────────────
```

(The `// ── Filters ───────────────────────────────────` comment line already exists right before the filter-row `Padding` — leave it in place; this step only inserts new content above it.)

- [ ] **Step 4: Gate the filter row and list on `_view == _View.list`, add the Record view**

Find the filter-row `Padding` (the one starting `Padding(\n  padding: const EdgeInsets.fromLTRB(\n    kHomeGutter,\n    ZirenTokens.space16,` that contains the three `_FilterChip`s, currently lines 150-181) through the end of the list-rendering block and the 50-cap footnote (currently ending around line 246, just before the closing `],` of the `ListView`'s `children`). Wrap that entire span — filter row, error note, the list-or-empty-state block, and the 50-cap footnote — in a single `if (_view == _View.list) ...[` / `],` and add the Record view as the `else` branch. Concretely, change:

```dart
              // ── Filters ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space16,
                  kHomeGutter,
                  0,
                ),
                child: Row(
                  children: [
                    _FilterChip(
```

to:

```dart
              // ── Filters ───────────────────────────────────
              if (_view == _View.list) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space16,
                  kHomeGutter,
                  0,
                ),
                child: Row(
                  children: [
                    _FilterChip(
```

and find the end of that span — the 50-cap footnote block currently reads:

```dart
              if (_filter != _Filter.active && p.history.length >= 50)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space12,
                    kHomeGutter,
                    0,
                  ),
                  child: Text(
                    'Showing your 50 most recent closed incidents.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Change it to close the new `if` and add the `else` branch, keeping the outer `ListView`'s `children` list closing exactly as it already does:

```dart
              if (_filter != _Filter.active && p.history.length >= 50)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space12,
                    kHomeGutter,
                    0,
                  ),
                  child: Text(
                    'Showing your 50 most recent closed incidents.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space16,
                    kHomeGutter,
                    0,
                  ),
                  child: _RecordView(history: p.history),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

(Do not touch anything between those two edits — the filter chips, error note, and list/empty-state rendering in between stay byte-for-byte as they are today, just now inside the `if` block.)

- [ ] **Step 5: Add the `_ViewToggle` and `_RecordView` widgets**

Add these two new classes at the end of the file, after the existing `_ErrorNote` class (currently the last class, ending around line 577):

```dart
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _View view;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleSegment(
              label: 'List',
              selected: view == _View.list,
              onTap: () => onChanged(_View.list),
            ),
          ),
          Expanded(
            child: _ViewToggleSegment(
              label: 'Record',
              selected: view == _View.record,
              onTap: () => onChanged(_View.record),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleSegment extends StatelessWidget {
  const _ViewToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: ZirenTokens.motionBase,
        curve: Curves.easeOut,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ZirenTokens.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          boxShadow: selected ? ZirenTokens.shadowSm : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color:
                selected ? ZirenTokens.textPrimary : ZirenTokens.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Shift analytics — the charts that used to live on Home, moved here so
/// "how is my shift/record looking" has one home separate from Home's "what
/// do I do right now". Every figure traces back to `history`/`dashboard`
/// data the app already fetches; see ResponderTrends for why these are
/// derived on the device rather than a backend series endpoint.
class _RecordView extends StatelessWidget {
  const _RecordView({required this.history});

  final List<ResponderIncidentModel> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const _EmptyRecordNote();
    }

    final closedWeek = ResponderTrends.closedPerDay(history);
    final weekTruncated = ResponderTrends.windowIsTruncated(history);
    final closedMix = ResponderTrends.severityMix(history);
    final median = ResponderTrends.medianMinutes(history);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClosedPerDayChart(days: closedWeek, truncated: weekTruncated),
        const SizedBox(height: ZirenTokens.space12),
        SeverityMixRing(
          mix: closedMix,
          title: 'What you have closed',
          emptyNote:
              'Nothing closed yet. Once you finish an incident, the mix of '
              'what you handle shows up here.',
        ),
        const SizedBox(height: ZirenTokens.space12),
        _TypicalResponseCard(median: median),
      ],
    );
  }
}

class _TypicalResponseCard extends StatelessWidget {
  const _TypicalResponseCard({required this.median});

  final double? median;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ZirenTokens.statusProcessing.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.timer_rounded,
              size: 18,
              color: ZirenTokens.statusProcessing,
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          const Expanded(
            child: Text(
              'Typical response time',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          Text(
            ResponderVocabulary.minutes(median),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ZirenTokens.statusProcessing,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordNote extends StatelessWidget {
  const _EmptyRecordNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: ZirenTokens.space32),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: 34,
            color: ZirenTokens.textDisabled,
          ),
          SizedBox(height: ZirenTokens.space12),
          Text(
            'Nothing to show yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textSecondary,
            ),
          ),
          SizedBox(height: ZirenTokens.space4),
          Text(
            'Close your first incident and your shift record will show up '
            'here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Format and analyze**

Run: `cd ziren_mobile && dart format lib/features/responder/presentation/responder_reports_screen.dart`
Run: `cd ziren_mobile && flutter analyze lib/features/responder/presentation/responder_reports_screen.dart`
Expected: no issues. If `dart format` complains about the `if (_view == _View.list) ...[` block's indentation not matching its siblings, that's expected — `dart format` will re-indent everything inside the new `if` block automatically; just make sure the file still parses (the analyze step catches this).

- [ ] **Step 7: Verify live — both views**

```bash
cd ziren_mobile
flutter run --dart-define-from-file=dart_defines.json -d 1480270594007084 > /tmp/rh_task4.log 2>&1 &
```

Wait for launch, navigate to the Reports tab (bottom nav, second icon), screenshot:

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/task4_reports_list.png
```

Read it — confirm the List/Record toggle appears above the filter chips, "List" selected by default, and the existing report list renders unchanged below it.

Tap "Record" (use `adb shell uiautomator dump` + bounds parsing for the exact tap coordinates, same technique as elsewhere in this project), screenshot again:

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/task4_reports_record.png
```

Read it. This test account has zero closed incidents (confirmed earlier this session — "Closed · 0"), so expect the `_EmptyRecordNote` empty state ("Nothing to show yet"), not the charts — that's correct given the data, and it's the honest-empty-state behavior the spec requires (no fake zeros drawn as if populated).

- [ ] **Step 8: Commit**

```bash
cd ziren_mobile
git add lib/features/responder/presentation/responder_reports_screen.dart
git commit -m "$(cat <<'EOF'
feat(responder): add List/Record toggle to Reports

Record view rewires the ClosedPerDayChart/SeverityMixRing widgets
(built for Home, then removed from it) plus a new typical-response-
time card, all driven by already-fetched history/dashboard data.
Avoids stacking a chart section below a potentially-long list — the
same "too much on one screen" failure mode Home had — by making it a
choice instead of a scroll.

Spec: docs/specs/2026-09-11-responder-redesign-design.md §5
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Profile — add the shift-record summary rows

**Files:**
- Modify: `ziren_mobile/lib/features/responder/presentation/responder_profile_screen.dart`

**Interfaces:**
- Consumes: `AppLocalizations.respProfileResolvedPeriod`/`.respProfileTypicalResponse` (from Task 1), `ResponderProvider.resolvedPeriod` (`int`, already exists), `ResponderProvider.statsPeriodDays` (`int`, already exists), `ResponderProvider.medianResponseMinutes` (`double?`, already exists), `ResponderVocabulary.minutes` (already exists), `ProfileRow` (from `shared/widgets/profile_kit.dart`, already imported/used in this file).

- [ ] **Step 1: Add the import**

Add to the top of `responder_profile_screen.dart` (alongside the existing `responder_provider.dart` import):

```dart
import '../domain/responder_vocabulary.dart';
```

- [ ] **Step 2: Add the two rows to the existing "This shift" `ProfileSection`**

Find the "This shift" `ProfileSection` (currently lines 400-419):

```dart
                // ── This shift ───────────────────────────────────
                //
                // Two numbers only, both about work still on them. The full figures
                // are the Stats tab's job, and repeating them here would make the
                // two screens argue every time one polled before the other.
                ProfileSection(
                  title: t.respProfileShift,
                  items: [
                    ProfileRow(
                      icon: Icons.assignment_rounded,
                      label: t.respProfileAssignedNow,
                      value: '${responder.queue.length}',
                    ),
                    ProfileRow(
                      icon: Icons.cloud_off_rounded,
                      label: t.respProfileWaitingToSend,
                      value: '${responder.pendingSyncCount}',
                      valueColor:
                          responder.hasPendingSync
                              ? ZirenTokens.systemWarning
                              : ZirenTokens.textPrimary,
                      last: true,
                    ),
                  ],
                ),
```

Replace with:

```dart
                // ── This shift ───────────────────────────────────
                //
                // Assigned-now and waiting-to-send are about work still on
                // them; resolved-this-period and typical response time are
                // the compact version of Reports' Record view, so Profile
                // answers "who is this and how is their shift going" without
                // repeating the full charts — see
                // docs/specs/2026-09-11-responder-redesign-design.md §7.
                ProfileSection(
                  title: t.respProfileShift,
                  items: [
                    ProfileRow(
                      icon: Icons.assignment_rounded,
                      label: t.respProfileAssignedNow,
                      value: '${responder.queue.length}',
                    ),
                    ProfileRow(
                      icon: Icons.cloud_off_rounded,
                      label: t.respProfileWaitingToSend,
                      value: '${responder.pendingSyncCount}',
                      valueColor:
                          responder.hasPendingSync
                              ? ZirenTokens.systemWarning
                              : ZirenTokens.textPrimary,
                    ),
                    ProfileRow(
                      icon: Icons.task_alt_rounded,
                      label:
                          '${t.respProfileResolvedPeriod} (${responder.statsPeriodDays}d)',
                      value: '${responder.resolvedPeriod}',
                    ),
                    ProfileRow(
                      icon: Icons.timer_rounded,
                      label: t.respProfileTypicalResponse,
                      value: ResponderVocabulary.minutes(
                        responder.medianResponseMinutes,
                      ),
                      last: true,
                    ),
                  ],
                ),
```

(`last: true` moved from the "Waiting to send" row to the new final "Typical response time" row — `ProfileRow`'s `last` flag drops the hairline under the final row of a section, so it must stay on whichever row is now actually last.)

- [ ] **Step 3: Format and analyze**

Run: `cd ziren_mobile && dart format lib/features/responder/presentation/responder_profile_screen.dart`
Run: `cd ziren_mobile && flutter analyze lib/features/responder/presentation/responder_profile_screen.dart`
Expected: no issues.

- [ ] **Step 4: Verify live**

```bash
cd ziren_mobile
flutter run --dart-define-from-file=dart_defines.json -d 1480270594007084 > /tmp/rh_task5.log 2>&1 &
```

Wait for launch, navigate to the Profile tab, screenshot:

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/task5_profile.png
```

Read it. Confirm "This shift" now shows 4 rows: Assigned right now, Waiting to send, Resolved this period (30d), Typical response time. Given this test account has 0 resolved incidents and no closed history, expect "Resolved this period (30d)" = 0 and "Typical response time" = "—" — both honest, not fake data.

- [ ] **Step 5: Commit**

```bash
cd ziren_mobile
git add lib/features/responder/presentation/responder_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(responder): add shift-record summary to Profile

Two more rows in the existing "This shift" section — resolved this
period and typical response time — using the same real dashboard
fields as Reports' Record view, condensed. Profile now answers "how
is their shift going", not just "what is their badge number".

Spec: docs/specs/2026-09-11-responder-redesign-design.md §7
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Extract `responder_kit.dart` (behavior-preserving refactor)

**Files:**
- Create: `ziren_mobile/lib/features/responder/presentation/widgets/responder_kit.dart`
- Modify: `ziren_mobile/lib/features/responder/presentation/responder_home_screen.dart`
- Modify: `ziren_mobile/test/home_design_preview_test.dart`

**Interfaces:**
- Produces (all in the new file, all public): `ResponderSectionHeading` (new widget, matches `HomeSectionHeading`'s look), `DutyStatusCard`, `ResponderStat`, `ResponderStatCell`, `ResponderStatBand`, `ResponderQuickActionTile` (renamed from the private `_QuickActionTile`).
- Consumes nothing new — this task moves existing, already-working code; it must not change any widget's behavior or visual output.

This task must run **after** Tasks 2 and 3, since those tasks edit `DutyStatusCard`/`_QuickActionTile`/`ResponderStatBand` in place — moving the file first would mean re-locating those edits. It runs before nothing else depends on it; it is the last content-adjacent task.

- [ ] **Step 1: Read the current file to get exact, post-Task-2/3 line ranges**

Run: `grep -n "^class \|^// ──" ziren_mobile/lib/features/responder/presentation/responder_home_screen.dart`

This prints every top-level class and section-comment with its current line number. Use this output to find the exact current boundaries of: `DutyStatusCard` (and its "── Duty status ──" comment header), `ResponderStat`/`ResponderStatBand`/`ResponderStatCell` (and its "── Figure band ──" header), and `_QuickActionTile` (and its "── Quick action tile ──" header) — their line numbers will have shifted from what's quoted in this plan because Tasks 2 and 3 edited the file above them.

- [ ] **Step 2: Create `responder_kit.dart` with the moved widgets**

Create `ziren_mobile/lib/features/responder/presentation/widgets/responder_kit.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/home_kit.dart' show kCardRadius, kHomeGutter;

/// The shared building blocks of the Responder screens — Home, Reports, and
/// Profile all draw section headers, the duty card, figure cells, and the
/// quick-action tile from here, instead of each screen defining its own.
///
/// This is the direct fix for "the pages are not consistent because we have
/// other design in each page" — see
/// docs/specs/2026-09-11-responder-redesign-design.md §2 and §8. Nothing
/// here is new design work: every widget in this file was lifted, unchanged
/// in behavior, from responder_home_screen.dart, where it used to be
/// available only to that one screen.

// ── Section heading ─────────────────────────────────────────────

/// A titled section with an optional trailing action — matches
/// HomeSectionHeading's look exactly, so the resident and responder sides
/// read as the same product even though the pages around this heading
/// differ. Kept as a separate widget rather than importing
/// HomeSectionHeading directly so the responder side does not depend on a
/// resident-named type; the two are visually identical on purpose.
class ResponderSectionHeading extends StatelessWidget {
  const ResponderSectionHeading(
    this.title, {
    super.key,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space20,
        kHomeGutter,
        ZirenTokens.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.brandOrange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Duty status ─────────────────────────────────────────────────

/// The duty switch, as a row rather than a dial.
///
/// From the prototype. It states the state in words — "Aktibo — handa
/// tumugon" — beside the switch, because a switch alone is a shape a tired
/// person reads wrong: on and off look alike at a glance, and the cost of
/// misreading it is an assignment that never arrives.
class DutyStatusCard extends StatelessWidget {
  const DutyStatusCard({
    super.key,
    required this.onDuty,
    required this.busy,
    required this.onChanged,
    required this.displayName,
    required this.onTap,
    this.rank,
    this.agencyLabel,
  });

  final bool onDuty;
  final bool busy;
  final ValueChanged<bool> onChanged;

  /// The responder's own name, shown under the duty banner — the reference
  /// design puts "who" directly beneath "what state", since both answer the
  /// same question a dispatcher radioing this phone would ask first.
  final String displayName;
  final String? rank;
  final String? agencyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = onDuty ? ZirenTokens.systemSuccess : ZirenTokens.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          children: [
            // ── The state, stated plainly ──────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ZirenTokens.space16),
              decoration: BoxDecoration(
                color: tone,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kCardRadius),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          busy
                              ? 'Sandali lang...'
                              : onDuty
                              ? 'Currently On-Duty'
                              : 'Off Duty',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (agencyLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '(Station: $agencyLabel)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  else
                    Semantics(
                      toggled: onDuty,
                      label: onDuty ? 'Go off duty' : 'Go on duty',
                      child: ExcludeSemantics(
                        child: Switch.adaptive(
                          value: onDuty,
                          onChanged: onChanged,
                          activeTrackColor: Colors.white.withValues(
                            alpha: 0.35,
                          ),
                          activeColor: Colors.white,
                          thumbColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Who ─────────────────────────────────────────
            InkWell(
              onTap: onTap,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(kCardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: ZirenTokens.brandOrange,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        displayName.trim().isNotEmpty
                            ? displayName.trim()[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          if (rank != null)
                            Text(
                              rank!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ZirenTokens.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: ZirenTokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Figure band ─────────────────────────────────────────────────

/// One figure in the band. Public so the design-preview test can render the
/// band without a Supabase session — see test/home_design_preview_test.dart.
class ResponderStat {
  const ResponderStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
}

/// Figures in a row, equal-width.
///
/// Equal-width cells rather than a scrolling strip: three or four is few
/// enough to fit any phone this app targets, and a figure that has to be
/// scrolled to is a figure nobody reads.
class ResponderStatBand extends StatelessWidget {
  const ResponderStatBand({super.key, required this.cells});

  final List<ResponderStat> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space10,
        kHomeGutter,
        0,
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: ZirenTokens.space8),
            Expanded(child: ResponderStatCell(stat: cells[i])),
          ],
        ],
      ),
    );
  }
}

class ResponderStatCell extends StatelessWidget {
  const ResponderStatCell({super.key, required this.stat});

  final ResponderStat stat;

  @override
  Widget build(BuildContext context) {
    // A zero recedes. On a quiet shift most cells read "0", and rendered in
    // severity red at figure size those zeros become the loudest marks on the
    // screen while carrying the least information - the eye pulled to the
    // absence of an emergency. Same rule the dispatcher console's tiles use.
    final quiet = stat.value == '0' || stat.value == '—';
    final tone = quiet ? ZirenTokens.textMuted : stat.color;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: ZirenTokens.space12,
        horizontal: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        children: [
          // Icon-in-a-tinted-circle, the same treatment HomeRow and the
          // queue card's type tile use elsewhere in this app — a bare glyph
          // read as a smaller, plainer version of everything around it.
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color:
                  quiet
                      ? ZirenTokens.surfaceRaised
                      : tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(stat.icon, size: 16, color: tone),
          ),
          const SizedBox(height: ZirenTokens.space8),
          FittedBox(
            child: Text(
              stat.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1,
                color: tone,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action tile ───────────────────────────────────────────
//
// One shortcut into the app's real "what's most urgent" feature — see
// responder_home_screen.dart's call site for why the reference design's
// other two tiles were dropped. Public (renamed from the former private
// `_QuickActionTile`) so Reports/Profile can reuse the same shape for any
// future single-shortcut affordance without re-implementing it.
class ResponderQuickActionTile extends StatelessWidget {
  const ResponderQuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Material(
      color: disabled ? color.withValues(alpha: 0.4) : color,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space12,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  if (badgeCount != null && badgeCount! > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Note: the accessibility wrapping from Task 2 Step 4 is included directly in this moved `DutyStatusCard` above — do not lose it in the move.

- [ ] **Step 2: Delete the moved code from `responder_home_screen.dart`, add the import, update references**

Using the line numbers found in Step 1: delete the `DutyStatusCard` class and its `// ── Duty status ──` header comment, delete `ResponderStat`/`ResponderStatBand`/`ResponderStatCell` and their `// ── Figure band ──` header comment, and delete `_QuickActionTile` and its `// ── Quick action tile ──` header comment — all three are now defined in `responder_kit.dart`.

Add the import near the top of `responder_home_screen.dart` (alongside the existing `responder_reports_screen.dart show ReportRow` import):

```dart
import 'widgets/responder_kit.dart';
```

Update every call site in this file that constructed `_QuickActionTile(...)` (from Task 2 Step 2, there is exactly one) to `ResponderQuickActionTile(...)` instead — same named arguments, no other change.

Also replace the two `HomeSectionHeading(` call sites in this file (Recent Activity and the queue heading) with `ResponderSectionHeading(` — same constructor shape (positional title, named `action`/`onAction`), so this is a name-only substitution at each call site. Remove the `import '../../../shared/widgets/home_kit.dart';` line's `HomeSectionHeading`-only need is now gone, but the file still needs `kHomeGutter`, `kCardRadius`, `HomeActivityCard`, and `kHomeCanvas` from that same import — do **not** remove the `home_kit.dart` import, only stop referencing `HomeSectionHeading` from it.

- [ ] **Step 3: Update `test/home_design_preview_test.dart`**

This test currently imports `DutyStatusCard`/`ResponderStatBand`/`ResponderStat` via `package:Ziren/features/responder/presentation/responder_home_screen.dart` (confirm with `grep -n "^import" ziren_mobile/test/home_design_preview_test.dart`). Add the new import:

```dart
import 'package:Ziren/features/responder/presentation/widgets/responder_kit.dart';
```

The existing `DutyStatusCard(...)` and `ResponderStatBand(...)`/`ResponderStat(...)` calls in that test do not need to change syntactically (same class names, same constructors) — only the import needs adding, since those types now live in a different file. Keep the existing `responder_home_screen.dart` import too (the test likely still uses other things from it, or may need `ResponderQueueCard` if it references that — check with `grep -n "ResponderQueueCard\|DutyStatusCard\|ResponderStatBand\|ResponderStat(" ziren_mobile/test/home_design_preview_test.dart` and keep whichever import each type actually needs).

- [ ] **Step 4: Format and analyze the whole project**

```bash
cd ziren_mobile
dart format lib/features/responder/presentation/responder_home_screen.dart lib/features/responder/presentation/widgets/responder_kit.dart test/home_design_preview_test.dart
flutter analyze
```

Expected: same 3 pre-existing infos, nothing new. If anything is undefined, it's almost certainly a missed reference to `_QuickActionTile` or `HomeSectionHeading` still in `responder_home_screen.dart` that Step 2 should have changed — grep for both names in that file and fix any remaining occurrence.

- [ ] **Step 5: Verify live — Home renders identically to Task 3's screenshot**

```bash
cd ziren_mobile
flutter run --dart-define-from-file=dart_defines.json -d 1480270594007084 > /tmp/rh_task6.log 2>&1 &
```

Wait for launch, screenshot Home:

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/task6_home.png
```

Read it and compare against `/tmp/task2_home.png`/`/tmp/task3` screenshots — this is a pure refactor, so the screen must look pixel-identical (same duty card, same 3 stats with "Longest waiting" as the third, same single "Awaiting Dispatch" tile). Any visual difference means something was lost in the move — go back to Step 2 and re-check the deleted/moved code matches this plan's `responder_kit.dart` content exactly.

- [ ] **Step 6: Run the design-preview test**

Run: `cd ziren_mobile && flutter test test/home_design_preview_test.dart`
Expected: passes (it's a golden-preview harness, not an assertion suite — "passes" means it renders without throwing; see the file's own doc comment).

- [ ] **Step 7: Commit**

```bash
cd ziren_mobile
git add lib/features/responder/presentation/widgets/responder_kit.dart lib/features/responder/presentation/responder_home_screen.dart test/home_design_preview_test.dart
git commit -m "$(cat <<'EOF'
refactor(responder): extract responder_kit.dart

Moves DutyStatusCard, ResponderStat/StatCell/StatBand, and the
quick-action tile (now public as ResponderQuickActionTile) out of
responder_home_screen.dart into a shared widgets/responder_kit.dart,
alongside a new ResponderSectionHeading matching HomeSectionHeading's
look. Pure refactor — no behavior or visual change; verified against
the prior task's live screenshot.

Spec: docs/specs/2026-09-11-responder-redesign-design.md §8
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Final regression pass across all four responder tabs

**Files:** none modified — verification only.

- [ ] **Step 1: Full-project analyze**

Run: `cd ziren_mobile && flutter analyze`
Expected: same 3 pre-existing infos (BuildContext-across-async-gap in `responder_incident_detail_screen.dart`, deprecated `MaplibreMap`, package-name casing in `pubspec.yaml`), nothing new.

- [ ] **Step 2: Live screenshots of all four tabs, app already running from Task 6**

```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/final_home.png
```
Tap the Reports tab, screenshot:
```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/final_reports.png
```
Tap the Map tab, screenshot (this tab has no code changes — confirm-only, per spec §6):
```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/final_map.png
```
Tap the Profile tab, screenshot:
```bash
adb -s 1480270594007084 exec-out screencap -p > /tmp/final_profile.png
```

Read all four. Confirm: Home shows the trimmed layout with "Longest waiting" and one tile; Reports shows the List/Record toggle; Map is unchanged from its last-known-good state (satellite view, agency pins, no crash); Profile shows the 4-row shift section.

- [ ] **Step 3: Confirm no regression on the duty toggle's real effect**

Since Task 2 Step 8 already toggled duty on/off once and left the account off-duty, do a final check that the account is genuinely back to its starting state — `Off Duty` shown on Home — so this session doesn't leave the test account in an unexpected state for whoever uses it next.

- [ ] **Step 4: Stop the running Flutter process cleanly**

Find and stop the background `flutter run` process started for this task (check running background tasks/processes for the one launched in Task 6 Step 5 if still alive, or Task 7's own if a fresh one was started) rather than leaving it orphaned.

- [ ] **Step 5: Final summary commit (docs only, if anything is left uncommitted)**

```bash
cd ziren_mobile
git status --short
```

If clean (all six prior commits already cover every change), nothing to do. If anything is unexpectedly uncommitted, investigate before committing — do not blindly `git add -A`.
