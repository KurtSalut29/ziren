import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/home_kit.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Ziren AI — placeholder for the guided-reporting assistant.
///
/// The tab exists because the design calls for it and the backend already
/// reserves configuration for it (CLAUDE_API_KEY, "ResQ Chat", Phase 8).
/// The screen says so plainly instead of pretending: an assistant that
/// silently does nothing in an emergency app is worse than one that is
/// honestly labelled as not ready, and the SOS route out of here is on
/// the screen for anyone who opened this tab needing help now.
class ZirenAiScreen extends StatelessWidget {
  const ZirenAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: SafeArea(
        bottom: false,
        // Centered, not top-aligned: this is a "not ready yet" state, not a
        // page of content that happens to be short. Left top-aligned inside
        // a ListView, the short block read as accidentally truncated —
        // roughly two-thirds of the screen sat empty below it. Centering
        // reads as a deliberate composition instead, the same way any empty
        // state does.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                kHomeGutter,
                ZirenTokens.space24,
                kHomeGutter,
                ZirenTokens.space24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight -
                      ZirenTokens.space24 -
                      ZirenTokens.space24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: ZirenTokens.aiSuggestedBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                size: 30,
                color: ZirenTokens.aiSuggested,
              ),
            ),
            const SizedBox(height: ZirenTokens.space16),
            Text(
              'Ziren AI',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              t.aiScreenBody,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space24),
            Container(
              padding: const EdgeInsets.all(ZirenTokens.space16),
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                borderRadius: BorderRadius.circular(kCardRadius),
                border: Border.all(
                  color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.construction,
                        size: 18,
                        color: ZirenTokens.systemWarning,
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      Flexible(child: Text(
                        t.aiNotAvailable,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  Text(
                    t.aiNotAvailableBody,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: ZirenTokens.severityCritical,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => context.push('/sos-confirm'),
                          icon: const Icon(LucideIcons.siren, size: 18),
                          label: const Text('SOS'),
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: ZirenTokens.textPrimary,
                          ),
                          onPressed: () => context.push('/report'),
                          icon: const Icon(LucideIcons.square_pen, size: 18),
                          label: Text(t.quickReport),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
