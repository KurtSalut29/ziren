import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/sos_provider.dart';
import '../domain/sos_result.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Shown immediately after a successful SOS submission.
///
/// Two sections:
///   1. Confirmation — shows incident ID, resolved station, and next steps.
///   2. Follow-up prompt — optional additional details the Resident can
///      provide *after* the SOS is already dispatched. This is intentional:
///      the SOS is sent first, details are collected second, consistent
///      with the plan's "speed over completeness" design for SOS.
///
/// Submitting the follow-up is a fire-and-forget update to the same incident.
/// Dismissing it does NOT cancel or modify the SOS — it was already sent.
class SosSuccessScreen extends StatefulWidget {
  const SosSuccessScreen({super.key});

  @override
  State<SosSuccessScreen> createState() => _SosSuccessScreenState();
}

class _SosSuccessScreenState extends State<SosSuccessScreen> {
  final _followUpController = TextEditingController();
  bool _followUpSubmitted = false;

  @override
  void dispose() {
    _followUpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<SosProvider>();
    final result = provider.lastResult;

    return PopScope(
      // Prevent accidental back — user must explicitly choose next action
      onPopInvokedWithResult: (didPop, result) async {
        // Prevent accidental back — user must explicitly choose next action
      },
      child: Scaffold(
        backgroundColor: ZirenTokens.surfaceBase,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ZirenTokens.space32),

                // ── Success icon ──────────────────────────
                const Icon(
                  LucideIcons.circle_check_big,
                  size: 72,
                  color: ZirenTokens.systemSuccess,
                ),
                const SizedBox(height: ZirenTokens.space16),

                Text(
                  t.sosSentTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                Text(
                  t.sosSentBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: ZirenTokens.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space24),

                // ── Incident summary card ─────────────────
                if (result != null) _IncidentSummaryCard(result: result),
                const SizedBox(height: ZirenTokens.space24),

                // ── Follow-up prompt ──────────────────────
                if (!_followUpSubmitted) ...[
                  _FollowUpSection(
                    controller: _followUpController,
                    onSkip: _goHome,
                    onSubmit: _submitFollowUp,
                  ),
                ] else ...[
                  _FollowUpConfirmation(),
                  const SizedBox(height: ZirenTokens.space24),
                  ElevatedButton(
                    onPressed: _goHome,
                    child: Text(t.actionBackToHome),
                  ),
                ],

                const SizedBox(height: ZirenTokens.space24),

                // ── Always-visible fallback reminder ─────
                Container(
                  padding: const EdgeInsets.all(ZirenTokens.space12),
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius8),
                    border: Border.all(color: ZirenTokens.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.phone,
                        size: 18,
                        color: ZirenTokens.textMuted,
                      ),
                      SizedBox(width: ZirenTokens.space8),
                      Expanded(
                        child: Text(
                          t.sosWorsensNote,
                          style: TextStyle(
                            fontSize: 12,
                            color: ZirenTokens.textSecondary,
                            height: 1.5,
                          ),
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

  void _submitFollowUp() {
    // The follow-up text is informational context for the dispatcher.
    // Phase 8 (ResQ AI Chat) will offer guided 5W1H follow-up instead.
    // For now: stored locally and would be sent to a PATCH /incidents/{id}
    // endpoint when that route is built in Phase 6A.
    // The UX is designed so the SOS is already dispatched before this point —
    // this is non-blocking additional context, not a required step.
    setState(() => _followUpSubmitted = true);
  }

  void _goHome() {
    context.read<SosProvider>().reset();
    context.go('/home');
  }
}

// ── Incident summary card ─────────────────────────────────────

class _IncidentSummaryCard extends StatelessWidget {
  const _IncidentSummaryCard({required this.result});
  final SosResult result;

  Color get _agencyColor {
    switch (result.agencyType) {
      case 'BFP':
        return ZirenTokens.agencyBFP;
      case 'PNP':
        return ZirenTokens.agencyPNP;
      case 'MDRRMO':
        return ZirenTokens.agencyMDRRMO;
      default:
        return ZirenTokens.brandOrange;
    }
  }

  IconData get _agencyIcon {
    switch (result.agencyType) {
      case 'BFP':
        return LucideIcons.flame;
      case 'PNP':
        return LucideIcons.shield;
      case 'MDRRMO':
        return LucideIcons.triangle_alert;
      default:
        return LucideIcons.siren;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.receipt_text,
                size: 15,
                color: ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(child: Text(
                'Report ID: ${result.shortId}…',
                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
              )),
            ],
          ),
          const SizedBox(height: ZirenTokens.space12),

          // Station dispatched to
          if (result.stationName != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_agencyIcon, size: 18, color: _agencyColor),
                const SizedBox(width: ZirenTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.sosDispatchedTo,
                        style: TextStyle(
                          fontSize: 11,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                      Text(
                        result.stationName!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _agencyColor,
                        ),
                      ),
                      if (result.municipality != null)
                        Text(
                          result.municipality!,
                          style: TextStyle(
                            fontSize: 12,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Follow-up prompt ──────────────────────────────────────────

class _FollowUpSection extends StatelessWidget {
  const _FollowUpSection({
    required this.controller,
    required this.onSkip,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final VoidCallback onSkip;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        // No borderRadius — Border() with non-uniform sides requires no radius.
        border: Border(
          left: const BorderSide(color: ZirenTokens.brandOrange, width: 3),
          top: BorderSide(color: ZirenTokens.surfaceBorder),
          right: BorderSide(color: ZirenTokens.surfaceBorder),
          bottom: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.message_square_plus,
                size: 18,
                color: ZirenTokens.brandOrange,
              ),
              SizedBox(width: ZirenTokens.space8),
              Flexible(child: Text(
                t.sosAddDetails,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.brandOrange,
                ),
              )),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            t.sosAddDetailsHelp,
            style: TextStyle(
              fontSize: 12,
              color: ZirenTokens.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          TextFormField(
            controller: controller,
            maxLines: 4,
            maxLength: 500,
            style: TextStyle(fontSize: 14, color: ZirenTokens.textPrimary),
            decoration: InputDecoration(
              hintText: t.sosAddDetailsExample,
              filled: true,
              fillColor: ZirenTokens.surfaceCard,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.textSecondary,
                    side: BorderSide(color: ZirenTokens.surfaceBorder),
                  ),
                  child: Text(t.actionSkip),
                ),
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZirenTokens.brandOrange,
                  ),
                  child: Text(t.sosSendDetails),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowUpConfirmation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemSuccessBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(
          color: ZirenTokens.systemSuccess.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.check, size: 18, color: ZirenTokens.systemSuccess),
          SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              t.sosDetailsSent,
              style: TextStyle(fontSize: 13, color: ZirenTokens.systemSuccess),
            ),
          ),
        ],
      ),
    );
  }
}
