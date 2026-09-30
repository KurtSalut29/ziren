import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../auth/domain/auth_provider.dart';
import '../../registration/presentation/password_requirements.dart';
import 'widgets/settings_form_kit.dart';

/// Signature of the call that actually changes the password; throws
/// [WrongPasswordFailure], [SamePasswordFailure] or another [Failure].
typedef ChangePasswordCall =
    Future<void> Function({
      required String currentPassword,
      required String newPassword,
    });

/// Change the signed-in account's password: current password, new password
/// (with the same live requirements panel registration uses), and the new one
/// again.
///
/// "Change password" in Settings used to open the forgot-password screen,
/// which made a signed-in person type their email, sent a reset link, and then
/// offered "Back to sign in" - to a login screen they were already past. This
/// changes the password in place and stays signed in.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.onSubmit});

  /// Injected by tests. Defaults to [AuthProvider.changePassword].
  final ChangePasswordCall? onSubmit;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _hideCurrent = true;
  bool _hideNext = true;
  bool _hideConfirm = true;
  bool _busy = false;

  /// A server-side refusal of the current password, shown under that field.
  String? _currentError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() => _currentError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final call = widget.onSubmit ?? context.read<AuthProvider>().changePassword;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call(currentPassword: _current.text, newPassword: _next.text);
      if (!mounted) return;
      ZirenToast.success(messenger, t.cpDone);
      Navigator.of(context).pop(true);
    } on WrongPasswordFailure {
      if (!mounted) return;
      setState(() => _currentError = t.cpWrongCurrent);
    } on SamePasswordFailure {
      if (!mounted) return;
      ZirenToast.error(messenger, t.cpSameAsOld);
    } catch (_) {
      if (!mounted) return;
      ZirenToast.error(messenger, t.cpFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _eye(bool hidden, VoidCallback toggle) => PasswordVisibilityButton(
    obscured: hidden,
    onTap: toggle,
    showIcon: LucideIcons.eye,
    hideIcon: LucideIcons.eye_off,
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.settingsChangePassword),
      ),
      bottomNavigationBar: SettingsSaveBar(
        label: t.settingsChangePassword,
        icon: LucideIcons.lock_keyhole,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space8,
            ZirenTokens.space16,
            ZirenTokens.space24,
          ),
          children: [
            _IntroCard(text: t.cpIntro),
            const SizedBox(height: ZirenTokens.space20),
            SettingsFormSection(
              title: t.cpCurrent,
              children: [
                SettingsField(
                  label: t.cpCurrent,
                  child: ZirenTextField(
                    key: const Key('cp-current'),
                    label: '',
                    controller: _current,
                    obscureText: _hideCurrent,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(LucideIcons.lock),
                    suffixIcon: _eye(
                      _hideCurrent,
                      () => setState(() => _hideCurrent = !_hideCurrent),
                    ),
                    onChanged: (_) {
                      if (_currentError != null) {
                        setState(() => _currentError = null);
                      }
                    },
                    validator:
                        (v) => (v ?? '').isEmpty ? t.cpEnterCurrent : null,
                  ),
                ),
                // Not a validator message: those stay on screen until the
                // form is validated again, so a refusal would still be shown
                // after the person had started retyping. This one goes the
                // moment they type.
                if (_currentError != null)
                  Row(
                    key: const Key('cp-current-error'),
                    children: [
                      const Icon(
                        LucideIcons.circle_alert,
                        size: 16,
                        color: ZirenTokens.systemError,
                      ),
                      const SizedBox(width: ZirenTokens.space6),
                      Expanded(
                        child: Text(
                          _currentError!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ZirenTokens.systemError,
                          ),
                        ),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    style: TextButton.styleFrom(
                      foregroundColor: ZirenTokens.brandOrange,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      t.cpForgot,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZirenTokens.space24),
            SettingsFormSection(
              title: t.cpNew,
              children: [
                SettingsField(
                  label: t.cpNew,
                  child: ZirenTextField(
                    key: const Key('cp-new'),
                    label: '',
                    controller: _next,
                    obscureText: _hideNext,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(LucideIcons.key_round),
                    suffixIcon: _eye(
                      _hideNext,
                      () => setState(() => _hideNext = !_hideNext),
                    ),
                    validator: (v) {
                      final weak = Validators.password(v);
                      if (weak != null) return weak;
                      if (v == _current.text) return t.cpSameAsOld;
                      return null;
                    },
                  ),
                ),
                PasswordRequirements(controller: _next),
                SettingsField(
                  label: t.cpConfirm,
                  child: ZirenTextField(
                    key: const Key('cp-confirm'),
                    label: '',
                    controller: _confirm,
                    obscureText: _hideConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    prefixIcon: const Icon(LucideIcons.key_round),
                    suffixIcon: _eye(
                      _hideConfirm,
                      () => setState(() => _hideConfirm = !_hideConfirm),
                    ),
                    validator: (v) => v != _next.text ? t.cpMismatch : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemInfoBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ZirenTokens.systemInfo.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ZirenTokens.systemInfo.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.shield_check,
              size: 20,
              color: ZirenTokens.systemInfo,
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
