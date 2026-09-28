import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_error_banner.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../registration/domain/registration_draft.dart';
import '../domain/auth_provider.dart';
import 'widgets/auth_legal_note.dart';
import 'widgets/auth_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.login(
      email: _emailController.text.trim(),
      password: _passController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();

    return AuthShell(
      title: t.loginTitle,
      subtitle: t.loginSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.errorMessage != null) ...[
            ZirenErrorBanner(message: auth.errorMessage!),
            const SizedBox(height: ZirenTokens.space16),
          ],

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  label: t.fieldEmail,
                  child: ZirenTextField(
                    label: '',
                    hint: t.hintEmail,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    prefixIcon: const Icon(LucideIcons.mail),
                    validator: Validators.email,
                    onChanged: (_) => auth.clearError(),
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),
                AuthField(
                  label: t.fieldPassword,
                  child: ZirenTextField(
                    label: '',
                    hint: t.hintPassword,
                    controller: _passController,
                    obscureText: _obscurePass,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    prefixIcon: const Icon(LucideIcons.lock),
                    suffixIcon: IconButton(
                      tooltip: _obscurePass ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePass
                            ? LucideIcons.eye
                            : LucideIcons.eye_off,
                        size: 20,
                        color: ZirenTokens.textMuted,
                        semanticLabel:
                            _obscurePass ? 'Show password' : 'Hide password',
                      ),
                      onPressed:
                          () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    validator:
                        (v) =>
                            v == null || v.isEmpty
                                ? t.validationPasswordRequired
                                : null,
                    onChanged: (_) => auth.clearError(),
                  ),
                ),

                // Sits tight under the password field it belongs to, in ink
                // rather than brand orange — it is a way out of a dead end,
                // not the action the screen is asking for.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    style: TextButton.styleFrom(
                      foregroundColor: ZirenTokens.textPrimary,
                      minimumSize: const Size(0, ZirenTokens.minTouchTarget),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZirenTokens.space8,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Text(t.loginForgotPassword),
                  ),
                ),

                const SizedBox(height: ZirenTokens.space8),
                ZirenButton(
                  label: t.loginButton,
                  isLoading: auth.isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),

          const SizedBox(height: ZirenTokens.space16),

          AuthFooterLink(
            question: t.loginNewToZiren,
            action: t.loginCreateAccount,
            onPressed: () {
              // So the back arrow on step one comes back here rather than to
              // the welcome screen, which would ask them to choose between
              // signing in and registering all over again.
              context.read<RegistrationDraft>().cameFromSignIn = true;
              context.push('/register');
            },
          ),

          // What they are agreeing to by signing in, with both documents one
          // tap away. Consent itself is taken during onboarding; this is the
          // reminder, on the screen they actually sit on.
          const SizedBox(height: ZirenTokens.space8),
          const AuthLegalNote(),
        ],
      ),
    );
  }
}
