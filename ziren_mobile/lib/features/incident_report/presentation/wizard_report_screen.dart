import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import 'wizard_shared.dart';
import 'widgets/incident_location_section.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Combined report screen — Step 1 of 2.
///
/// Replaces the old 4-step wizard (category → questions → overlap → who).
/// No forced-choice questions are asked — text/voice is the only free-form
/// detail input. Layout:
///   1. Category grid (WHAT) — tapping a category reveals the rest inline
///   2. Where: the incident (here, or placed on the map) + landmark (required)
///   3. Optional catch-all free text / voice
class WizardReportScreen extends StatefulWidget {
  const WizardReportScreen({super.key});

  @override
  State<WizardReportScreen> createState() => _WizardReportScreenState();
}

class _WizardReportScreenState extends State<WizardReportScreen> {
  final _catchAllController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _scrollController = ScrollController();

  /// Set when the resident tried to continue without a landmark.
  bool _landmarkMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<IncidentProvider>();
      p.fetchLocation();
      p.initSpeech();
      final existing = p.wizardAnswers['catch_all'] as String?;
      if (existing != null) _catchAllController.text = existing;
      final note = p.landmarkNote;
      if (note != null) _landmarkController.text = note;
    });
  }

  @override
  void dispose() {
    _catchAllController.dispose();
    _landmarkController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCategoryTap(IncidentProvider provider, IncidentCategory cat) {
    provider.setCategory(cat);
    // Scroll down after frame so the revealed sections are visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: ZirenTokens.motionEntrance,
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _canProceed {
    final p = context.read<IncidentProvider>();
    return p.incidentCategory != null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    if (!provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/select-station'),
      );
      return const SizedBox.shrink();
    }

    final category = provider.incidentCategory;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.reportTitle),
        leading: BackButton(
          onPressed: () {
            provider.clearStation();
            context.go('/select-station');
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WizardProgress(step: 1, totalSteps: 2),
            WizardStationBanner(provider: provider),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── WHAT: category grid ───────────────────
                    _SectionHeader(
                      icon: LucideIcons.circle_question_mark,
                      label: t.reportSectionWhat,
                      badge: t.badgeRequired,
                      badgeColor: ZirenTokens.systemError,
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    _CategoryGrid(
                      selected: category,
                      onTap: (cat) => _onCategoryTap(provider, cat),
                    ),

                    // ── Rest revealed after category pick ──
                    if (category != null) ...[
                      const SizedBox(height: ZirenTokens.space24),
                      IncidentLocationSection(
                        landmarkController: _landmarkController,
                        showLandmarkError: _landmarkMissing,
                        header: (text) => _SectionHeader(
                          icon: LucideIcons.map_pin,
                          label: text,
                        ),
                        onLandmarkChanged: (v) {
                          provider.setLandmarkNote(v);
                          if (_landmarkMissing) {
                            setState(() => _landmarkMissing = false);
                          }
                        },
                      ),

                      const SizedBox(height: ZirenTokens.space24),
                      _SectionHeader(
                        icon: LucideIcons.square_pen,
                        label: t.reportExtraDetails,
                        badge: t.badgeOptional,
                        badgeColor: ZirenTokens.systemSuccess,
                      ),
                      const SizedBox(height: ZirenTokens.space8),
                      _CatchAllField(
                        controller: _catchAllController,
                        provider: provider,
                        onChanged:
                            (v) => provider.mergeWizardAnswer('catch_all', v),
                      ),
                    ],

                    const SizedBox(height: ZirenTokens.space32),
                  ],
                ),
              ),
            ),

            // ── Next button ───────────────────────────────────
            _NextBar(
              enabled: _canProceed,
              onNext: () {
                // Required — see IncidentLocationSection.
                if (_landmarkController.text.trim().isEmpty) {
                  setState(() => _landmarkMissing = true);
                  _scrollController.animateTo(
                    0,
                    duration: ZirenTokens.motionEntrance,
                    curve: Curves.easeOut,
                  );
                  return;
                }
                final text = _catchAllController.text.trim();
                if (text.isNotEmpty) {
                  provider.mergeWizardAnswer('catch_all', text);
                }
                provider.setLandmarkNote(_landmarkController.text);
                context.push('/report/review');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.badge,
    this.badgeColor,
  });
  final IconData icon;
  final String label;

  /// Short badge text shown after the label, e.g. "REQUIRED" or "OPTIONAL"
  final String? badge;

  /// Background color for the badge pill. Defaults to brandOrange.
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final effectiveBadgeColor = badgeColor ?? ZirenTokens.brandOrange;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: ZirenTokens.brandOrange),
        const SizedBox(width: ZirenTokens.space6),
        Flexible(child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textPrimary,
          ),
        )),
        if (badge != null) ...[
          const SizedBox(width: ZirenTokens.space8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZirenTokens.space6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: effectiveBadgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ZirenTokens.radius4),
              border: Border.all(
                color: effectiveBadgeColor.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: effectiveBadgeColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Category grid ──────────────────────────────────────────────

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selected, required this.onTap});
  final IncidentCategory? selected;
  final void Function(IncidentCategory) onTap;

  // Colour and icon come from IncidentCategoryStyle — the one place shared
  // with Home's quick-action ring, so the two screens cannot drift apart
  // again. Only the tinted background (unique to this grid's selected-state
  // treatment) stays local.
  (Color, Color, IconData) _style(IncidentCategory cat) {
    final color = IncidentCategoryStyle.color(cat);
    final bg = switch (cat) {
      IncidentCategory.fire => ZirenTokens.agencyBFPBg,
      IncidentCategory.medicalTrauma => ZirenTokens.severityHighBg,
      IncidentCategory.vehicular => ZirenTokens.severityMediumBg,
      IncidentCategory.floodLandslideCalamity => ZirenTokens.agencyMDRRMOBg,
      IncidentCategory.domesticDisputeCrime => ZirenTokens.agencyPNPBg,
      IncidentCategory.other => ZirenTokens.surfaceRaised,
    };
    return (color, bg, IncidentCategoryStyle.icon(cat));
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: ZirenTokens.space10,
      crossAxisSpacing: ZirenTokens.space10,
      childAspectRatio: 1.7,
      children:
          IncidentCategory.values.map((cat) {
            final isSelected = selected == cat;
            final (color, bg, icon) = _style(cat);
            return GestureDetector(
              onTap: () => onTap(cat),
              child: AnimatedContainer(
                duration: ZirenTokens.motionQuick,
                padding: const EdgeInsets.all(ZirenTokens.space12),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.12) : bg,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                  border: Border.all(
                    color: isSelected ? color : ZirenTokens.surfaceBorder,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? ZirenTokens.shadowSm : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 22, color: color),
                    const SizedBox(height: ZirenTokens.space6),
                    Text(
                      cat.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? color : ZirenTokens.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }
}

// ── Catch-all free text + voice ────────────────────────────────

class _CatchAllField extends StatelessWidget {
  const _CatchAllField({
    required this.controller,
    required this.provider,
    required this.onChanged,
  });
  final TextEditingController controller;
  final IncidentProvider provider;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          onChanged: onChanged,
          style: TextStyle(fontSize: 14, color: ZirenTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Anumang dagdag na detalye na hindi nasabing sa itaas…',
            hintStyle: TextStyle(
              color: ZirenTokens.textMuted,
              fontSize: 13,
            ),
            filled: true,
            fillColor: ZirenTokens.surfaceCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
            ),
          ),
        ),
        if (provider.speechAvailable) ...[
          const SizedBox(height: ZirenTokens.space8),
          OutlinedButton.icon(
            icon: Icon(
              provider.isListening ? LucideIcons.mic : LucideIcons.mic,
              size: 18,
              color:
                  provider.isListening
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.textMuted,
            ),
            label: Text(
              provider.isListening
                  ? 'Nakikinig… (pindutin para itigil)'
                  : 'Sabihin ang detalye',
              style: TextStyle(
                color:
                    provider.isListening
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.textMuted,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color:
                    provider.isListening
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.surfaceBorder,
              ),
            ),
            onPressed: () {
              if (provider.isListening) {
                provider.stopListening();
              } else {
                provider.startListening(
                  onResult: (text) {
                    controller.text = text;
                    onChanged(text);
                  },
                );
              }
            },
          ),
        ],
      ],
    );
  }
}

// ── Next / proceed bar ─────────────────────────────────────────

class _NextBar extends StatelessWidget {
  const _NextBar({required this.enabled, required this.onNext});
  final bool enabled;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          ),
        ),
        onPressed: enabled ? onNext : null,
        child: const Text(
          'I-review ang Ulat →',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
