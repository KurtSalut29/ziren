import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../domain/id_catalogue.dart';
import '../domain/registration_draft.dart';
import 'password_requirements.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 4 — how to reach this person, the password, and (residents only) the
/// accessibility profile.
///
/// The accessibility block sits here rather than in a settings screen nobody
/// visits, because it changes how a crew approaches the scene. A resident who
/// is deaf and whose account does not say so gets phoned by a crew standing
/// outside their door.
class StepContactScreen extends StatefulWidget {
  const StepContactScreen({super.key});

  @override
  State<StepContactScreen> createState() => _StepContactScreenState();
}

class _StepContactScreenState extends State<StepContactScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _password;
  late final TextEditingController _confirm;
  late final TextEditingController _ecName;
  late final TextEditingController _ecNumber;
  late final TextEditingController _pwdId;
  late final TextEditingController _notes;

  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _showAccessibility = false;

  @override
  void initState() {
    super.initState();
    final d = context.read<RegistrationDraft>();
    _email = TextEditingController(text: d.email);
    _phone = TextEditingController(text: d.phone);
    _password = TextEditingController(text: d.password);
    _confirm = TextEditingController(text: d.password);
    _ecName = TextEditingController(text: d.emergencyContactName);
    _ecNumber = TextEditingController(text: d.emergencyContactNumber);
    _pwdId = TextEditingController(text: d.pwdIdNumber);
    _notes = TextEditingController(text: d.accessibilityNotes);
    // Open the block if they already told us something, so a resumed draft
    // does not hide data behind a collapsed header.
    _showAccessibility = d.isPwd || d.disabilities.isNotEmpty;
  }

  @override
  void dispose() {
    for (final c in [
      _email,
      _phone,
      _password,
      _confirm,
      _ecName,
      _ecNumber,
      _pwdId,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit(RegistrationDraft d) {
    if (!_formKey.currentState!.validate()) return;
    d.email = _email.text.trim();
    d.phone = _phone.text.trim();
    d.password = _password.text;
    d.emergencyContactName = _ecName.text.trim();
    d.emergencyContactNumber = _ecNumber.text.trim();
    d.pwdIdNumber = _pwdId.text.trim();
    d.accessibilityNotes = _notes.text.trim();
    d.commit();
    context.go(d.next(RegStep.contact)!.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();

    return RegistrationScaffold(
      step: RegStep.contact,
      title: t.regContactTitle,
      subtitle: t.regContactSubtitle,
      onContinue: () => _submit(d),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RegField(
              label: 'Email address',
              child: ZirenTextField(
                label: '',
                hint: 'you@example.com',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(LucideIcons.mail),
                validator: Validators.email,
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldMobile,
              child: ZirenTextField(
                label: '',
                hint: t.hintMobile,
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(LucideIcons.phone),
                validator: Validators.phoneNumber,
              ),
            ),

            const SizedBox(height: ZirenTokens.space24),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            const SizedBox(height: ZirenTokens.space24),

            RegField(
              label: 'Password',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ZirenTextField(
                    label: '',
                    hint: t.hintCreatePassword,
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(LucideIcons.lock),
                    suffixIcon: _EyeButton(
                      obscured: _obscure,
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: Validators.password,
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  // The requirements, always on screen and ticked off live -
                  // not a line of grey helper text people never read.
                  PasswordRequirements(controller: _password),
                ],
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldConfirmPassword,
              child: ZirenTextField(
                label: '',
                hint: t.hintConfirmPassword,
                controller: _confirm,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                helperText: t.passwordConfirmHint,
                prefixIcon: const Icon(LucideIcons.lock),
                suffixIcon: _EyeButton(
                  obscured: _obscureConfirm,
                  onTap:
                      () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                validator:
                    (v) =>
                        v != _password.text ? 'Passwords do not match.' : null,
              ),
            ),

            const SizedBox(height: ZirenTokens.space24),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            const SizedBox(height: ZirenTokens.space24),

            // WHOSE contact this is, said outright. Testers read a bare
            // "Emergency contact" as "my own contact details" or as a list to
            // add friends to; it is ONE other person, and it is not them.
            RegField(
              label: t.regEmergencyWhoTitle,
              optional: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.regEmergencyWhoBody,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space12),
                  ZirenTextField(
                    label: '',
                    hint: t.hintEmergencyName,
                    controller: _ecName,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(LucideIcons.contact),
                    validator:
                        (v) =>
                            ((v ?? '').trim().isEmpty &&
                                    _ecNumber.text.trim().isNotEmpty)
                                ? t.regEmergencyNeedsName
                                : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZirenTokens.space12),
            ZirenTextField(
              label: '',
              hint: t.hintEmergencyNumber,
              controller: _ecNumber,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              prefixIcon: const Icon(LucideIcons.phone),
              validator: (v) {
                final number = (v ?? '').trim();
                if (number.isEmpty) {
                  return _ecName.text.trim().isEmpty
                      ? null
                      : t.regEmergencyNeedsNumber;
                }
                final invalid = Validators.phoneNumber(number);
                if (invalid != null) return invalid;
                // The commonest mix-up: typing their OWN number here.
                if (Validators.sameMobile(number, _phone.text)) {
                  return t.regEmergencySameAsYours;
                }
                return null;
              },
            ),

            if (!d.isResponder) ...[
              const SizedBox(height: ZirenTokens.space24),
              Divider(height: 1, color: ZirenTokens.surfaceBorder),
              const SizedBox(height: ZirenTokens.space16),
              _AccessibilityBlock(
                expanded: _showAccessibility,
                onToggle:
                    () => setState(
                      () => _showAccessibility = !_showAccessibility,
                    ),
                pwdIdController: _pwdId,
                notesController: _notes,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whether two typed mobile numbers are the same phone, however each was
/// written (09171234567, +63 917 123 4567, 639171234567).
///
/// Compared on the last ten digits, which is the subscriber number once the
/// leading 0 or the 63 country code is set aside.
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscured, required this.onTap});
  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = obscured ? 'Show password' : 'Hide password';
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(
        obscured ? LucideIcons.eye : LucideIcons.eye_off,
        size: 20,
        color: ZirenTokens.textMuted,
        semanticLabel: label,
      ),
    );
  }
}

class _AccessibilityBlock extends StatelessWidget {
  const _AccessibilityBlock({
    required this.expanded,
    required this.onToggle,
    required this.pwdIdController,
    required this.notesController,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController pwdIdController;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space8),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.accessibility,
                  size: 20,
                  color: ZirenTokens.brandOrange,
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.regAccessibility,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        t.regAccessibilityWhy,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? LucideIcons.chevron_up
                      : LucideIcons.chevron_down,
                  color: ZirenTokens.textMuted,
                ),
              ],
            ),
          ),
        ),

        if (expanded) ...[
          const SizedBox(height: ZirenTokens.space12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeColor: ZirenTokens.brandOrange,
            value: d.isPwd,
            onChanged: (v) {
              d.isPwd = v;
              d.commit();
            },
            title: Text(t.regIsPwd, style: TextStyle(fontSize: 14.5)),
          ),
          if (d.isPwd) ...[
            const SizedBox(height: ZirenTokens.space8),
            ZirenTextField(
              label: '',
              hint: t.hintPwdId,
              controller: pwdIdController,
              textInputAction: TextInputAction.next,
              helperText: t.pwdIdHelp,
              prefixIcon: const Icon(LucideIcons.badge),
            ),
          ],
          const SizedBox(height: ZirenTokens.space16),
          Text(
            t.regAccessibilityAsk,
            style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary),
          ),
          const SizedBox(height: ZirenTokens.space8),
          Wrap(
            spacing: ZirenTokens.space8,
            runSpacing: ZirenTokens.space8,
            children: [
              for (final option in disabilityOptions)
                _Toggle(
                  label: option.label,
                  selected: d.disabilities.contains(option.value),
                  onTap: () {
                    if (!d.disabilities.remove(option.value)) {
                      d.disabilities.add(option.value);
                    }
                    d.commit();
                  },
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          ZirenTextField(
            label: '',
            hint: t.hintAccessibilityNotes,
            controller: notesController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: ZirenTokens.space16),
          Text(
            t.regContactModeAsk,
            style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary),
          ),
          const SizedBox(height: ZirenTokens.space8),
          Wrap(
            spacing: ZirenTokens.space8,
            runSpacing: ZirenTokens.space8,
            children: [
              for (final mode in [
                (value: 'any', label: t.contactModeAny),
                (value: 'sms_only', label: t.contactModeSms),
                (value: 'app_only', label: t.contactModeApp),
                (value: 'voice_ok', label: t.contactModeVoice),
              ])
                _Toggle(
                  label: mode.label,
                  selected: d.contactMode == mode.value,
                  onTap: () {
                    d.contactMode = mode.value;
                    d.commit();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? ZirenTokens.brandSubtle : ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius32),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius32),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space16,
                vertical: ZirenTokens.space10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                border: Border.all(
                  color:
                      selected ? ZirenTokens.brandOrange : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected
                          ? ZirenTokens.brandActive
                          : ZirenTokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
