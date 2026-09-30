import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../incident_report/domain/incident_category_style.dart';
import '../../incident_report/domain/incident_provider.dart' show IncidentCategory;
import '../../incident_report/presentation/incident_labels.dart';
import '../../incident_report/presentation/widgets/quick_report_kit.dart';
import '../domain/sos_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../hotlines/presentation/hotlines_view.dart';

/// SOS confirmation screen — shown after the Resident taps the SOS button.
///
/// Built on the same shell as the category-tile quick-report screen
/// (QuickReportSectionLabel / QuickReportCard, a plain AppBar, the same
/// tinted category banner) rather than its own look — one resident-facing
/// report screen and one emergency-report screen should not read as two
/// different apps. What stays SOS-specific: no typed landmark or media fields
/// (see submit_sos's docstring — this path skips them for speed; the landmark
/// is found from the bundled map instead, see _LandmarkRow), the legal
/// warning + truthfulness checkbox, the cooldown banner, and the send
/// control itself, which holds instead of taps (see _SendButton).
///
/// On successful submission → navigates to [SosSuccessScreen] (/sos-success).
class SosConfirmScreen extends StatefulWidget {
  const SosConfirmScreen({super.key});

  @override
  State<SosConfirmScreen> createState() => _SosConfirmScreenState();
}

class _SosConfirmScreenState extends State<SosConfirmScreen> {
  bool _legalConfirmed = false;

  @override
  void initState() {
    super.initState();
    // Start GPS + load cooldown state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SosProvider>().initialize();
    });
  }

  Future<void> _submit() async {
    final provider = context.read<SosProvider>();
    final ok = await provider.submit();
    if (!mounted) return;
    if (ok) {
      context.go('/sos-success');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<SosProvider>();

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.sosAppBarTitle),
        leading:
            provider.isSubmitting
                ? const SizedBox.shrink()
                : BackButton(
                  onPressed: () {
                    provider.reset();
                    context.pop();
                  },
                ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space16,
          ),
          children: [
            // ── SOS / category banner ─────────────────────────
            _SosBanner(category: provider.category),
            const SizedBox(height: ZirenTokens.space20),

            // ── GPS / location status ─────────────────────────
            QuickReportSectionLabel(t.sosWhereSection),
            const SizedBox(height: ZirenTokens.space8),
            _LocationStatus(provider: provider),
            const SizedBox(height: ZirenTokens.space20),

            // ── Category (optional) ───────────────────────────
            _CategoryPicker(
              selected: provider.category,
              onSelect: provider.setCategory,
            ),

            // ── Cooldown warning ──────────────────────────────
            if (provider.isCoolingDown) ...[
              const SizedBox(height: ZirenTokens.space16),
              _CooldownBanner(minutesLeft: provider.cooldownMinutesLeft),
            ],

            const SizedBox(height: ZirenTokens.space20),

            // ── Legal warning + checkbox ──────────────────────
            _LegalWarning(
              confirmed: _legalConfirmed,
              onChanged: (v) => setState(() => _legalConfirmed = v ?? false),
            ),

            if (provider.errorMessage != null) ...[
              const SizedBox(height: ZirenTokens.space16),
              _ErrorBanner(message: provider.errorMessage!),
            ],
            // The SOS reached nobody. A phone call still works on signal alone.
            if (provider.failedOffline) ...[
              const SizedBox(height: ZirenTokens.space10),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZirenTokens.systemSuccess,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(LucideIcons.phone, size: 18),
                  label: Text(AppLocalizations.of(context).hotlinesCallInstead),
                  onPressed: () => showHotlinesSheet(context, offline: true),
                ),
              ),
            ],

            const SizedBox(height: ZirenTokens.space24),

            // ── Send SOS button ────────────────────────────────
            _SendButton(
              enabled:
                  provider.category != null &&
                  _legalConfirmed &&
                  !provider.isSubmitting &&
                  !provider.isCoolingDown,
              isSubmitting: provider.isSubmitting,
              // The cooldown has its own banner already explaining that
              // blocker — repeating a different reason here would just
              // contradict it. Otherwise show whichever requirement isn't
              // met yet, category first since it's the one listed first on
              // screen.
              disabledHint:
                  provider.isCoolingDown
                      ? null
                      : provider.category == null
                      ? 'Choose what kind of emergency above to continue'
                      : !_legalConfirmed
                      ? 'Confirm the checkbox above to continue'
                      : null,
              onPressed: _submit,
            ),

            const SizedBox(height: ZirenTokens.space12),
            const _FallbackReminder(),
          ],
        ),
      ),
    );
  }
}

// ── SOS / category banner ───────────────────────────────────────

/// Same shape as the quick-report screen's category banner (icon badge +
/// bold title + subtitle on a tinted card) — with no category chosen it
/// falls back to the SOS-critical red instead of one of the six category
/// colours. Pick a category below and this banner adopts its icon and
/// colour too, the same visual confirmation the category-tile flow gives
/// for free by having the category pre-set.
class _SosBanner extends StatelessWidget {
  const _SosBanner({required this.category});
  final IncidentCategory? category;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color =
        category != null
            ? IncidentCategoryStyle.color(category!)
            : ZirenTokens.severityCritical;
    final bg =
        category != null
            ? IncidentCategoryStyle.background(category!)
            : ZirenTokens.severityCriticalBg;
    final icon =
        category != null ? IncidentCategoryStyle.icon(category!) : LucideIcons.siren;
    final title =
        category != null ? IncidentLabels.categoryShort(t, category!) : t.sosHeading;

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.sosIntro,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category (required) ─────────────────────────────────────────

/// What kind of emergency, so the server can prefer a station of the
/// matching agency instead of blind nearest-of-any-agency.
///
/// Required — the Send button stays disabled until one is picked. Deliberately
/// five choices, not Home's six: "Other" is excluded here on purpose. It has
/// no agency mapping (there is no honest agency to prefer for a report that
/// doesn't fit the other five) and SOS carries no free-text field to make up
/// the difference — the description box was removed for speed, and SOS never
/// had voice. Combined, an "Other" SOS would reach a station as an address
/// and the word "SOS" and nothing else, which is worse than asking the
/// resident to pick whichever of the five real categories comes closest.
/// Every choice on this screen now maps to a real agency and tells the
/// responding team something true before they arrive.
///
/// Sized and laid out like Home's category grid (same tile height, icon
/// size, three-across wrap) so a resident recognises these as the same
/// choices, minus the one Home offers that this screen deliberately doesn't.
/// The one thing Home's tiles don't need and this does: a selected state,
/// since tapping Home's tile navigates away immediately while this one
/// persists a choice on the same screen.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onSelect});
  final IncidentCategory? selected;
  final ValueChanged<IncidentCategory?> onSelect;

  // Home's display order (resident_home_screen.dart's QuickActionGrid) minus
  // Other — see the class doc for why it's excluded here specifically.
  static const _order = [
    IncidentCategory.fire,
    IncidentCategory.medicalTrauma,
    IncidentCategory.vehicular,
    IncidentCategory.domesticDisputeCrime,
    IncidentCategory.floodLandslideCalamity,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: QuickReportSectionLabel('What kind of emergency?'),
            ),
            if (selected == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: ZirenTokens.severityCritical.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'REQUIRED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.severityCritical,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Helps send the right team to the right place.',
          style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
        ),
        const SizedBox(height: ZirenTokens.space8),
        LayoutBuilder(
          builder: (context, c) {
            const gap = ZirenTokens.space10;
            final w = (c.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              // Five tiles over three columns leaves a shorter last row —
              // centering it (rather than the default left-packed start)
              // reads as one deliberate 3-then-2 layout instead of a grid
              // that ran out of items.
              alignment: WrapAlignment.center,
              children: [
                for (final cat in _order)
                  SizedBox(
                    width: w,
                    child: _CategoryTile(
                      category: cat,
                      label: IncidentLabels.categoryShort(t, cat),
                      isSelected: selected == cat,
                      // Tapping the already-selected tile clears it — a
                      // resident who changes their mind should not need a
                      // separate "clear" control on a screen built to be
                      // fast.
                      onTap: () => onSelect(selected == cat ? null : cat),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final IncidentCategory category;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = IncidentCategoryStyle.color(category);
    return Material(
      color: isSelected ? color.withValues(alpha: 0.10) : ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: ZirenTokens.motionQuick,
          height: 104,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isSelected
                      ? color
                      : ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(IncidentCategoryStyle.icon(category), size: 34, color: color),
              const SizedBox(height: ZirenTokens.space10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? color : ZirenTokens.textPrimary,
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

// ── GPS / location status ───────────────────────────────────────

/// Same QuickReportCard shell the quick-report screen's location row uses,
/// now showing the same kind of thing it shows too — a real place name via
/// [LocationNaming], not raw coordinates. A small spinner replaces the
/// refresh icon while the network-enriched name is still in flight; the
/// on-device guess is already on screen by then, so nothing sits blank.
class _LocationStatus extends StatelessWidget {
  const _LocationStatus({required this.provider});
  final SosProvider provider;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    if (provider.isLocating) {
      icon = LucideIcons.locate;
      color = ZirenTokens.textMuted;
      title = t.sosLocating;
      subtitle = t.sosStationAuto;
    } else if (provider.locationDenied || !provider.hasLocation) {
      icon = LucideIcons.map_pin_off;
      color = ZirenTokens.systemWarning;
      title = t.sosLocationUnavailable;
      subtitle = t.sosNoGpsBody;
    } else {
      icon = LucideIcons.map_pin;
      color = ZirenTokens.systemSuccess;
      title = provider.locationAddress ?? t.sosLocationCaptured;
      subtitle = t.sosStationAuto;
    }

    final located = !provider.isLocating && provider.hasLocation;

    return QuickReportCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(ZirenTokens.space12),
            child: _locationRow(icon, color, title, subtitle),
          ),
          if (located) ...[
            Divider(height: 1, thickness: 1, color: ZirenTokens.surfaceBorder),
            _LandmarkRow(provider: provider),
          ],
        ],
      ),
    );
  }

  Widget _locationRow(
    IconData icon,
    Color color,
    String title,
    String subtitle,
  ) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
          if (provider.isLocating || provider.geocoding)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: () => provider.fetchLocation(),
              child: Icon(
                LucideIcons.refresh_cw,
                size: 20,
                color: ZirenTokens.textMuted,
              ),
            ),
        ],
      );
  }
}

/// The landmark the station will be told, found from the map bundled in the
/// app the moment the GPS fix arrives — no typing needed, which is the point
/// of this screen. Tapping it lets the resident say it in their own words.
class _LandmarkRow extends StatelessWidget {
  const _LandmarkRow({required this.provider});
  final SosProvider provider;

  Future<void> _edit(BuildContext context) async {
    final t = AppLocalizations.of(context);
    var text = provider.typedLandmark ?? provider.detectedLandmark ?? '';
    final save = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.landmark,
      tone: ZirenTone.brand,
      title: t.sosLandmarkEditTitle,
      message: t.sosLandmarkEditBody,
      body: _LandmarkField(
        initial: text,
        hint: t.sosLandmarkEditHint,
        onChanged: (v) => text = v,
        // The dialog sits on the root navigator (showGeneralDialog's
        // default); the screen's own navigator would pop the SOS screen.
        onSubmitted: () => Navigator.of(context, rootNavigator: true).pop(true),
      ),
      horizontalActions: true,
      actions: [
        ZirenDialogAction(
          label: t.sosLandmarkEditCancel,
          value: false,
          kind: ZirenActionKind.secondary,
        ),
        ZirenDialogAction(
          label: t.sosLandmarkEditSave,
          value: true,
          kind: ZirenActionKind.primary,
        ),
      ],
    );
    if (save == true) {
      final trimmed = text.trim();
      // Saving the detected name unchanged is not "typing one": keep it as
      // the detected landmark so the note still reads "Near …".
      provider.setTypedLandmark(
        trimmed == provider.detectedLandmark ? null : trimmed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final typed = provider.typedLandmark;
    final found = provider.detectedLandmark;
    final finding = provider.findingLandmark && typed == null && found == null;

    final String title;
    final String caption;
    final Color accent;
    if (finding) {
      title = t.sosLandmarkFinding;
      caption = t.sosLandmarkAuto;
      accent = ZirenTokens.textMuted;
    } else if (typed != null) {
      title = typed;
      caption = t.sosLandmarkTyped;
      accent = ZirenTokens.brandOrange;
    } else if (found != null) {
      title = t.sosLandmarkNear(found);
      caption = t.sosLandmarkAuto;
      accent = ZirenTokens.brandOrange;
    } else {
      title = t.sosLandmarkNone;
      caption = t.sosLandmarkNoneHint;
      accent = ZirenTokens.textMuted;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('sos-landmark-row'),
        onTap: finding ? null : () => _edit(context),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(ZirenTokens.radius12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.landmark, size: 17, color: accent),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color:
                            finding
                                ? ZirenTokens.textSecondary
                                : ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 12,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZirenTokens.space8),
              if (finding)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  typed == null && found == null
                      ? LucideIcons.plus
                      : LucideIcons.pencil,
                  size: 18,
                  color: ZirenTokens.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The text field in the landmark dialog. It owns its controller so the
/// controller outlives the dialog's closing animation: disposing it as soon
/// as the dialog's future resolved crashed the field mid-fade ("used after
/// being disposed").
class _LandmarkField extends StatefulWidget {
  const _LandmarkField({
    required this.initial,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_LandmarkField> createState() => _LandmarkFieldState();
}

class _LandmarkFieldState extends State<_LandmarkField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('sos-landmark-field'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted(),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(LucideIcons.landmark, size: 20),
      ),
    );
  }
}

// ── Cooldown banner ───────────────────────────────────────────

class _CooldownBanner extends StatelessWidget {
  const _CooldownBanner({required this.minutesLeft});
  final int minutesLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.timer,
            size: 18,
            color: ZirenTokens.systemWarning,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).sosCooldownWarning(minutesLeft),
              style: const TextStyle(fontSize: 13, color: ZirenTokens.systemWarning),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legal warning ─────────────────────────────────────────────

class _LegalWarning extends StatelessWidget {
  const _LegalWarning({required this.confirmed, required this.onChanged});
  final bool confirmed;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: ZirenTokens.systemError.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.gavel,
                  size: 14,
                  color: ZirenTokens.systemError,
                ),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Flexible(child: Text(
                t.sosLegalWarning,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ZirenTokens.systemError,
                ),
              )),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          Text(
            t.sosLegalBody,
            style: TextStyle(
              fontSize: 12.5,
              color: ZirenTokens.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Divider(
            height: 1,
            thickness: 1,
            color: ZirenTokens.systemError.withValues(alpha: 0.18),
          ),
          const SizedBox(height: ZirenTokens.space12),
          _ConfirmRow(
            confirmed: confirmed,
            label: t.sosTruthConfirm,
            onTap: () => onChanged(!confirmed),
          ),
        ],
      ),
    );
  }
}

/// Replaces a bare CheckboxListTile — the default checkbox is a 18px square
/// easy to miss on the one screen where missing it should be impossible. A
/// full-width tappable tile that visibly fills when confirmed, plus a
/// REQUIRED badge that disappears the moment it no longer applies, makes the
/// gate itself as legible as the paragraph above it explaining why it exists.
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.confirmed,
    required this.label,
    required this.onTap,
  });
  final bool confirmed;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: confirmed,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: ZirenTokens.motionQuick,
          padding: const EdgeInsets.all(ZirenTokens.space10),
          decoration: BoxDecoration(
            // NOT Colors.white. The label below is ZirenTokens.textPrimary, which
            // is near-white in dark mode - so a hard-coded white fill here made
            // "I understand this is a real emergency..." white text on a white
            // box, unreadable, on the one screen where it has to be read. The
            // card token flips with the theme and the text token was written to
            // sit on it.
            color:
                confirmed
                    ? ZirenTokens.systemError.withValues(alpha: 0.10)
                    : ZirenTokens.surfaceCard,
            borderRadius: BorderRadius.circular(ZirenTokens.radius8),
            border: Border.all(
              color: confirmed ? ZirenTokens.systemError : ZirenTokens.surfaceBorder,
              width: confirmed ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: ZirenTokens.motionQuick,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: confirmed ? ZirenTokens.systemError : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        confirmed ? ZirenTokens.systemError : ZirenTokens.textMuted,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child:
                    confirmed
                        ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                        : null,
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        confirmed
                            ? ZirenTokens.systemError
                            : ZirenTokens.textPrimary,
                  ),
                ),
              ),
              if (!confirmed) ...[
                const SizedBox(width: ZirenTokens.space8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: ZirenTokens.systemError.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'REQUIRED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: ZirenTokens.systemError,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Send SOS button ───────────────────────────────────────────

/// Press-and-hold instead of a single tap — chosen over a PIN or fingerprint
/// gate for the same job (stop one stray tap from dispatching a crew).
///
/// A PIN relies on recall, which acute stress measurably degrades. A
/// fingerprint needs hardware every phone in the field may not have, and
/// fails on exactly the wet, muddy or injured fingers a real disaster
/// produces. A hold needs neither — just sustained deliberate contact — and
/// it is the pattern the rest of the industry already uses for "confirm a
/// high-consequence action without adding a screen": iPhone's own Emergency
/// SOS, "swipe to power off", a fire alarm's pull handle.
///
/// Releasing early cancels — the fill reverses and nothing is sent. Size and
/// radius match the app's global ElevatedButton exactly (see app_theme.dart)
/// — the colour is the one deliberate difference, kept critical-red because
/// that is what the app's own colour rules reserve red for.
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.enabled,
    required this.isSubmitting,
    required this.onPressed,
    this.disabledHint,
  });
  final bool enabled;
  final bool isSubmitting;
  final VoidCallback onPressed;

  /// Shown under the button only while disabled for a reason nothing else
  /// on screen already explains (see the call site — the cooldown banner
  /// covers its own case).
  final String? disabledHint;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _holdDuration,
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed) {
      HapticFeedback.heavyImpact();
      widget.onPressed();
    }
  });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startHold() {
    if (!widget.enabled) return;
    HapticFeedback.mediumImpact();
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    if (_controller.status != AnimationStatus.completed) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSubmitting) {
      return Column(
        children: [
          const LoadingIndicator(size: 36),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            'Sending SOS…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary),
          ),
        ],
      );
    }

    final t = AppLocalizations.of(context);
    final baseColor =
        widget.enabled ? ZirenTokens.severityCritical : ZirenTokens.surfaceRaised;

    // A caption always sits under the button once it's settled (not
    // submitting): what to do when enabled, why not otherwise. A control
    // this consequential should never leave the resident guessing whether
    // a tap or a hold is what sends it.
    final caption =
        widget.enabled
            ? 'Press and hold to send'
            : widget.disabledHint;

    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => _startHold(),
          onTapUp: (_) => _cancelHold(),
          onTapCancel: _cancelHold,
          child: Container(
            height: ZirenTokens.minTouchTarget + 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              // A lifted, coloured glow only once it can actually be sent —
              // the one moment on this screen where the button should read
              // as "the thing to press now" rather than blend into the rest
              // of the card stack above it.
              boxShadow:
                  widget.enabled
                      ? [
                        BoxShadow(
                          color: ZirenTokens.severityCritical.withValues(
                            alpha: 0.35,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                      : null,
            ),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The hold-progress fill. A lighter tint of the same
                  // colour sweeping left-to-right, not a separate progress
                  // bar — the whole button IS the control being filled.
                  AnimatedBuilder(
                    animation: _controller,
                    builder:
                        (_, __) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _controller.value,
                          child: Container(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.siren,
                        color: widget.enabled ? Colors.white : ZirenTokens.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      Flexible(child: Text(
                        t.sosSendNow,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color:
                              widget.enabled ? Colors.white : ZirenTokens.textMuted,
                        ),
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: ZirenTokens.space8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: widget.enabled ? FontWeight.w600 : FontWeight.w500,
              color:
                  widget.enabled
                      ? ZirenTokens.severityCritical
                      : ZirenTokens.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Fallback reminder ─────────────────────────────────────────

class _FallbackReminder extends StatelessWidget {
  const _FallbackReminder();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.phone_call, size: 15, color: ZirenTokens.textMuted),
        const SizedBox(width: ZirenTokens.space8),
        Expanded(
          child: Text(
            'For life-threatening emergencies, also call 911 directly. This '
            'report is reviewed by a human dispatcher — not AI.',
            style: TextStyle(fontSize: 12, height: 1.4, color: ZirenTokens.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Error banner ──────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.circle_alert,
            size: 18,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: ZirenTokens.systemError),
            ),
          ),
        ],
      ),
    );
  }
}
