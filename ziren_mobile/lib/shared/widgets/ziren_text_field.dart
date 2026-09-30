import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Standard text input following Ziren design system.
/// 48px+ touch target, Inter font, brand-orange focus ring.
///
/// Colour and decoration are driven by the ThemeData
/// InputDecorationTheme — do not hardcode colours here.
class ZirenTextField extends StatelessWidget {
  const ZirenTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onChanged,
    this.onFieldSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.helperText,
    this.autofocus = false,
    this.maxLines = 1,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? helperText;
  final bool autofocus;
  final int maxLines;
  final bool enabled;

  /// Names and addresses want [TextCapitalization.words]; email and ID
  /// numbers must stay [TextCapitalization.none] or the keyboard fights the
  /// user on every field they type.
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      autofocus: autofocus,
      maxLines: maxLines,
      enabled: enabled,
      textCapitalization: textCapitalization,
      style: TextStyle(fontSize: 16, color: ZirenTokens.textPrimary),
      decoration: InputDecoration(
        // An empty label means the caller is supplying its own caption above
        // the field (see AuthField). Passing '' through would reserve space
        // for a floating label that never appears.
        labelText: label.isEmpty ? null : label,
        hintText: hint,
        helperText: helperText,
        // The validators here say what to DO ("Put the number of someone
        // else - a relative, a friend"), which rarely fits one line; the
        // default of one line cut the instruction off mid-sentence.
        errorMaxLines: 3,
        helperMaxLines: 3,
        prefixIcon:
            prefixIcon != null
                ? IconTheme(
                  data: IconThemeData(color: ZirenTokens.textMuted, size: 20),
                  child: prefixIcon!,
                )
                : null,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
