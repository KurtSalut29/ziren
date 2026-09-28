import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Inline error banner — used for auth/form errors.
/// Uses systemError (validation/form errors) not severityCritical.
/// These are different semantics: form error ≠ emergency severity.
class ZirenErrorBanner extends StatelessWidget {
  const ZirenErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space16,
        vertical: ZirenTokens.space12,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.circle_alert,
            size: 18,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: ZirenTokens.systemError,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
