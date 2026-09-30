import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/profile_kit.dart';

// The pieces the Settings forms share (Edit personal information, Change
// password), in the same card language as the Profile screens: a small
// upper-case title outside a white card, captions above the fields rather than
// floating labels, and the one action pinned to the bottom of the screen.

/// A titled card of form fields.
class SettingsFormSection extends StatelessWidget {
  const SettingsFormSection({
    super.key,
    required this.title,
    required this.children,
    this.caption,
  });

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: ZirenTokens.space4,
            bottom: ZirenTokens.space8,
          ),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space4,
              0,
              ZirenTokens.space4,
              ZirenTokens.space10,
            ),
            child: Text(
              caption!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          decoration: profileCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: ZirenTokens.space16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A caption above a field. A floating label inside the box shrinks into the
/// border the moment the field has text, which is exactly when a person
/// checking the form wants to read it.
class SettingsField extends StatelessWidget {
  const SettingsField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: ZirenTokens.space6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The screen's one action, pinned above the keyboard / system bar.
class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space12,
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: busy ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZirenTokens.brandOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: ZirenTokens.brandOrange.withValues(
                  alpha: 0.55,
                ),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child:
                  busy
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                      : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18),
                            const SizedBox(width: ZirenTokens.space8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An eye button for a password field.
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.obscured,
    required this.onTap,
    required this.showIcon,
    required this.hideIcon,
  });

  final bool obscured;
  final VoidCallback onTap;
  final IconData showIcon;
  final IconData hideIcon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? showIcon : hideIcon,
        size: 20,
        color: ZirenTokens.textMuted,
      ),
    );
  }
}
