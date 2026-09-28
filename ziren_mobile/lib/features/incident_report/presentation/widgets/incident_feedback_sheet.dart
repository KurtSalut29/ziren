import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/incident_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Post-resolution feedback (spec Section 26).
///
/// Shown only from a resolved report, and only once — the caller checks
/// [IncidentProvider.fetchMyFeedback] first and never opens this a second
/// time for the same incident. Rating alone is enough to submit; the
/// comment is optional, matching the spec's own mockup.
Future<void> showIncidentFeedbackSheet(
  BuildContext context,
  String incidentId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FeedbackSheet(incidentId: incidentId),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.incidentId});
  final String incidentId;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await context.read<IncidentProvider>().submitIncidentFeedback(
      widget.incidentId,
      rating: _rating,
      comment: _commentController.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    setState(() {
      _submitting = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZirenTokens.radius24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space24,
          ZirenTokens.space12,
          ZirenTokens.space24,
          ZirenTokens.space24,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceBorder,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                ),
              ),
              const SizedBox(height: ZirenTokens.space20),
              if (_done) ...[
                const Icon(
                  LucideIcons.circle_check_big,
                  size: 48,
                  color: ZirenTokens.systemSuccess,
                ),
                const SizedBox(height: ZirenTokens.space12),
                Text(
                  t.feedbackThanks,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t.feedbackClose),
                  ),
                ),
              ] else ...[
                Text(
                  t.feedbackHowWasIt,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  t.feedbackNoImpact,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZirenTokens.textMuted,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      GestureDetector(
                        onTap: () => setState(() => _rating = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            i <= _rating
                                ? LucideIcons.star
                                : LucideIcons.star,
                            size: 40,
                            color:
                                i <= _rating
                                    ? ZirenTokens.severityMedium
                                    : ZirenTokens.surfaceBorder,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space20),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  maxLength: 1000,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: t.feedbackCommentHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZirenTokens.systemError,
                    ),
                  ),
                ],
                const SizedBox(height: ZirenTokens.space8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_rating == 0 || _submitting) ? null : _submit,
                    child:
                        _submitting
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(t.feedbackSubmit),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t.feedbackMaybeLater),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
