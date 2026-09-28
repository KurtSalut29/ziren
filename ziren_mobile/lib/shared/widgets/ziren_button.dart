import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Primary action button — full width, 52px tall, brand orange.
///
/// Delegates to the ThemeData ElevatedButton style for colour.
/// Pass [icon] for an icon+label variant.
class ZirenButton extends StatelessWidget {
  const ZirenButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child:
            isLoading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ZirenTokens.textPrimary,
                    ),
                  ),
                )
                : icon != null
                ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: ZirenTokens.space8),
                    Flexible(child: Text(label)),
                  ],
                )
                : Text(label),
      ),
    );
  }
}
