import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/responder_ack.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The three modal forms a responder fills in on a call: refusing it, asking
/// for another agency, and closing it with what was found.
///
/// Grouped in one file because they share a shape — a bottom sheet with a
/// constrained list of reasons and one optional free-text field — and because
/// each is under two hundred lines. Three files of near-identical scaffolding
/// would be harder to keep consistent, and consistency between them is the
/// point: a crew learns one interaction and uses it three times.
///
/// A NOTE ON THE STRINGS
///
/// Every `key` on DeclineReason and IncidentOutcome is a wire contract with
/// the backend's CHECK constraints. The LABELS are Taglish and may be
/// rewritten freely; the KEYS must not be touched. This is the same trap the
/// wizard answers carry — localise the value instead of the label and
/// validation starts failing with a 422 nobody can act on.

// =============================================================================
// Shared scaffolding
// =============================================================================

/// Bottom sheet chrome: grabber, title, subtitle, and a scrollable body that
/// gets out of the keyboard's way.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.accent = ZirenTokens.brandOrange,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The keyboard, not a fixed inset. The notes field on the close sheet is
      // the last thing filled in, and without this it sits underneath.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        expand: false,
        builder:
            (context, scrollController) => DecoratedBox(
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceOverlay,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ZirenTokens.radius24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: ZirenTokens.space12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZirenTokens.surfaceBorder,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ZirenTokens.space24,
                      ZirenTokens.space20,
                      ZirenTokens.space24,
                      ZirenTokens.space8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: ZirenTokens.space4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        ZirenTokens.space24,
                        ZirenTokens.space8,
                        ZirenTokens.space24,
                        ZirenTokens.space32,
                      ),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

/// One selectable reason or outcome. Big enough to hit with a gloved thumb.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZirenTokens.space8),
      child: Material(
        color:
            selected
                ? accent.withValues(alpha: 0.08)
                : ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          child: Container(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              border: Border.all(
                color: selected ? accent : ZirenTokens.surfaceBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? LucideIcons.circle_dot : LucideIcons.circle,
                  color: selected ? accent : ZirenTokens.textMuted,
                  size: 22,
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected ? accent : ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _submitButton({
  required String label,
  required IconData icon,
  required Color color,
  required VoidCallback? onPressed,
  required bool busy,
}) {
  return ElevatedButton.icon(
    onPressed: busy ? null : onPressed,
    icon:
        busy
            ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
            : Icon(icon, size: 18),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(54),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

// =============================================================================
// 1. Decline
// =============================================================================

/// Ask why the crew cannot take the call.
///
/// Returns `(reason, note)` or null if dismissed. The reason is mandatory: the
/// entire value of a refusal to the dispatcher is knowing WHICH refusal it is
/// — "vehicle down" sends a different unit, "out of area" sends the same unit
/// somewhere else, and a bare "declined" sends nobody anywhere.
class DeclineSheet extends StatefulWidget {
  const DeclineSheet({super.key});

  static Future<(String, String?)?> show(BuildContext context) {
    return showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DeclineSheet(),
    );
  }

  @override
  State<DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<DeclineSheet> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SheetScaffold(
      title: t.respDeclineTitle,
      subtitle: t.respDeclineSubtitle,
      accent: ZirenTokens.systemError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in DeclineReason.all)
            _ChoiceTile(
              label: r.label(t),
              hint: r.hint(t),
              selected: _reason == r.key,
              accent: ZirenTokens.systemError,
              onTap: () => setState(() => _reason = r.key),
            ),
          const SizedBox(height: ZirenTokens.space8),
          TextField(
            controller: _note,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.respDeclineNote,
              hintText: t.respDeclineNoteHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ZirenTokens.space20),
          _submitButton(
            label: t.respDeclineSubmit,
            icon: LucideIcons.undo,
            color: ZirenTokens.systemError,
            busy: false,
            onPressed:
                _reason == null
                    ? null
                    : () => Navigator.of(context).pop((
                      _reason!,
                      _note.text.trim().isEmpty ? null : _note.text.trim(),
                    )),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 2. After-action
// =============================================================================

/// What the crew found. Returned as a record the provider passes straight on.
///
/// THIS IS THE MOST IMPORTANT FORM IN THE RESPONDER APP, and not because of
/// anything the responder gets from it. Until it existed, closing a call wrote
/// a status and a timestamp, so the archive recorded what was REPORTED and
/// what the rubric GUESSED and nothing about what was TRUE. An incident scored
/// `critical` that closes `false_alarm` is a measurable rubric miss — and that
/// comparison could not be made at all before this screen.
class AfterActionSheet extends StatefulWidget {
  const AfterActionSheet({super.key, required this.categoryLabel});

  final String categoryLabel;

  static Future<AfterActionResult?> show(
    BuildContext context, {
    required String categoryLabel,
  }) {
    return showModalBottomSheet<AfterActionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Not dismissible by tapping away. Everything else in this app closes on
      // a stray tap; this one holds the only record of what happened, and a
      // crew packing up one-handed should not be able to lose it by accident.
      isDismissible: false,
      builder: (_) => AfterActionSheet(categoryLabel: categoryLabel),
    );
  }

  @override
  State<AfterActionSheet> createState() => _AfterActionSheetState();
}

class AfterActionResult {
  const AfterActionResult({
    required this.outcome,
    this.notes,
    this.injured,
    this.fatal,
    this.transported,
  });

  final String outcome;
  final String? notes;
  final int? injured;
  final int? fatal;
  final int? transported;
}

class _AfterActionSheetState extends State<AfterActionSheet> {
  String? _outcome;
  final _notes = TextEditingController();

  // Null until the crew touches the counter, and that distinction is kept all
  // the way to the database. NULL means "not recorded"; 0 means "we counted,
  // nobody was hurt". Defaulting these to 0 would turn every unfilled form
  // into a clean scene.
  int? _injured;
  int? _fatal;
  int? _transported;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Casualty counters are only shown for outcomes where a count is meaningful.
  /// Asking how many were injured in a false alarm is how a form teaches
  /// people to answer it without reading it.
  bool get _showCasualties =>
      _outcome == 'handled_on_scene' ||
      _outcome == 'transported' ||
      _outcome == 'turned_over' ||
      _outcome == 'other';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SheetScaffold(
      title: t.respCloseTitle,
      subtitle: widget.categoryLabel,
      accent: ZirenTokens.systemSuccess,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in IncidentOutcome.all)
            _ChoiceTile(
              label: o.label(t),
              hint: o.hint(t),
              selected: _outcome == o.key,
              accent: ZirenTokens.systemSuccess,
              onTap: () => setState(() => _outcome = o.key),
            ),

          // AnimatedSize, not a bare conditional insert: picking an outcome
          // used to splice this whole block straight into the Column in one
          // frame, changing the scrollable's content height instantly. A
          // drag landing on the sheet in that same frame could have its
          // ballistic fling computed against the old extent and then
          // hit-test into geometry from the new one — the render tree the
          // crash log's "hit test a render box that has never been laid
          // out" pointed at. Growing the section over a few frames instead
          // keeps the scrollable's extent consistent with whatever the
          // gesture system is currently tracking.
          AnimatedSize(
            duration: ZirenTokens.motionBase,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            // Both branches are wrapped in the SAME SizedBox(width:
            // double.infinity) on purpose — that was true of the empty
            // placeholder branch but not of the counters Column, and that
            // asymmetry is what crashed: AnimatedSize measures the incoming
            // and outgoing child to interpolate between their sizes, and an
            // unconstrained-width child swapped in beside a fully-width-bound
            // one is exactly the shape of thing that produces "BoxConstraints
            // forces an infinite width" partway through the transition — it
            // showed up on the OutlinedButton in the first _Counter row,
            // which is the first widget in the newly-appearing branch to
            // actually need a resolved width. Found 2026-09-15 via live
            // device logs while testing an unrelated dispatch-delivery bug.
            child: SizedBox(
              width: double.infinity,
              child:
                  !_showCasualties
                      ? null
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: ZirenTokens.space16),
                          Text(
                            t.respCloseCasualties,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: ZirenTokens.space4),
                          Text(
                            t.respCloseCasualtiesHint,
                            style: TextStyle(
                              fontSize: 12,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: ZirenTokens.space12),
                          _Counter(
                            label: t.respCloseInjured,
                            value: _injured,
                            color: ZirenTokens.severityHigh,
                            onChanged: (v) => setState(() => _injured = v),
                          ),
                          _Counter(
                            label: t.respCloseFatal,
                            value: _fatal,
                            color: ZirenTokens.severityCritical,
                            onChanged: (v) => setState(() => _fatal = v),
                          ),
                          _Counter(
                            label: t.respCloseTransported,
                            value: _transported,
                            color: ZirenTokens.systemInfo,
                            onChanged: (v) => setState(() => _transported = v),
                          ),
                        ],
                      ),
            ),
          ),

          const SizedBox(height: ZirenTokens.space16),
          TextField(
            controller: _notes,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.respCloseNarrative,
              hintText: t.respCloseNarrativeHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ZirenTokens.space20),
          _submitButton(
            label: t.respCloseSubmit,
            icon: LucideIcons.circle_check_big,
            color: ZirenTokens.systemSuccess,
            busy: false,
            onPressed:
                _outcome == null
                    ? null
                    : () => Navigator.of(context).pop(
                      AfterActionResult(
                        outcome: _outcome!,
                        notes:
                            _notes.text.trim().isEmpty
                                ? null
                                : _notes.text.trim(),
                        injured: _injured,
                        fatal: _fatal,
                        transported: _transported,
                      ),
                    ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.respCloseLater),
            ),
          ),
        ],
      ),
    );
  }
}

/// A count that starts at "not recorded" rather than at zero.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final Color color;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final recorded = value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: ZirenTokens.space8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (!recorded)
            OutlinedButton(
              onPressed: () => onChanged(0),
              child: Text(t.respCount),
            )
          else ...[
            IconButton(
              onPressed: value! > 0 ? () => onChanged(value! - 1) : null,
              icon: const Icon(LucideIcons.circle_minus),
              color: color,
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onChanged(value! + 1),
              icon: const Icon(LucideIcons.circle_plus),
              color: color,
            ),
            IconButton(
              tooltip: t.respNotCounted,
              onPressed: () => onChanged(null),
              icon: const Icon(LucideIcons.delete, size: 18),
              color: ZirenTokens.textMuted,
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 3. Mutual aid
// =============================================================================

/// Ask a second agency to attend the same emergency.
///
/// Returns `(agencyType, reason)`. The agency colours are the fixed ones from
/// the design tokens — BFP red-coral, PNP sky-blue, MDRRMO emerald — because a
/// crew picking one under pressure recognises the colour before the word.
class BackupSheet extends StatefulWidget {
  const BackupSheet({super.key, this.excludeAgencyType});

  /// The agency already attending. Offering a crew the option to call
  /// themselves is noise on a screen that must be read in seconds.
  final String? excludeAgencyType;

  static Future<(String, String)?> show(
    BuildContext context, {
    String? excludeAgencyType,
  }) {
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BackupSheet(excludeAgencyType: excludeAgencyType),
    );
  }

  @override
  State<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<BackupSheet> {
  String? _agency;
  final _reason = TextEditingController();

  static const _agencies = <(String, String, Color, IconData)>[
    ('BFP', 'Bureau of Fire Protection', Color(0xFFEF4444), LucideIcons.flame),
    (
      'PNP',
      'Philippine National Police',
      Color(0xFF0EA5E9),
      LucideIcons.shield,
    ),
    (
      'MDRRMO',
      'Disaster Risk Reduction',
      Color(0xFF10B981),
      LucideIcons.stethoscope,
    ),
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options =
        _agencies.where((a) => a.$1 != widget.excludeAgencyType).toList();

    final t = AppLocalizations.of(context);
    return _SheetScaffold(
      title: t.respBackupTitle,
      subtitle: t.respBackupSubtitle,
      accent: ZirenTokens.systemInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (code, name, color, icon) in options)
            Padding(
              padding: const EdgeInsets.only(bottom: ZirenTokens.space8),
              child: Material(
                color:
                    _agency == code
                        ? color.withValues(alpha: 0.10)
                        : ZirenTokens.surfaceRaised,
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                child: InkWell(
                  onTap: () => setState(() => _agency = code),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  child: Container(
                    padding: const EdgeInsets.all(ZirenTokens.space16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                      border: Border.all(
                        color:
                            _agency == code ? color : ZirenTokens.surfaceBorder,
                        width: _agency == code ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 26),
                        const SizedBox(width: ZirenTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                code,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ZirenTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_agency == code)
                          Icon(LucideIcons.circle_check_big, color: color),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: ZirenTokens.space12),
          TextField(
            controller: _reason,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.respBackupNeed,
              hintText: t.respBackupNeedHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ZirenTokens.space20),
          _submitButton(
            label: t.respBackupSubmit,
            icon: LucideIcons.megaphone,
            color: ZirenTokens.systemInfo,
            busy: false,
            onPressed:
                (_agency == null || _reason.text.trim().isEmpty)
                    ? null
                    : () => Navigator.of(
                      context,
                    ).pop((_agency!, _reason.text.trim())),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. Escalate
// =============================================================================

/// "The situation is worse than assessed" — Section 14.
///
/// Deliberately the plainest sheet of the four: one field, no picker. This
/// notifies the Agency Admin so THEY can reassess; it never changes the
/// incident's own severity, which is why there is nothing here to select
/// between — only what changed is worth recording.
class EscalateSheet extends StatefulWidget {
  const EscalateSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EscalateSheet(),
    );
  }

  @override
  State<EscalateSheet> createState() => _EscalateSheetState();
}

class _EscalateSheetState extends State<EscalateSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Escalate Incident',
      subtitle:
          'Tell the Agency Admin what changed. This notifies them to '
          'reassess — it does not change the official severity yourself.',
      accent: ZirenTokens.severityHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _reason,
            maxLines: 4,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What changed?',
              hintText:
                  'e.g. Fire spreading rapidly, multiple casualties, '
                  'additional agency required…',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ZirenTokens.space20),
          _submitButton(
            label: 'Send Escalation',
            icon: LucideIcons.triangle_alert,
            color: ZirenTokens.severityHigh,
            busy: false,
            onPressed:
                _reason.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_reason.text.trim()),
          ),
        ],
      ),
    );
  }
}
