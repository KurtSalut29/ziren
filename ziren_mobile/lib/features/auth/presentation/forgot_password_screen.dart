import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_card.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../domain/auth_provider.dart';
import 'widgets/auth_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitted = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    await auth.sendPasswordReset(_emailController.text.trim());

    if (!mounted) return;
    setState(() {
      _loading = false;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AuthShell(
      compact: true,
      onBack: () => context.pop(),
      title: _submitted ? t.forgotSentTitle : t.forgotTitle,
      subtitle: _submitted ? null : t.forgotSubtitle,
      child: _submitted ? _successView(t) : _formView(t),
    );
  }

  Widget _formView(AppLocalizations t) {
    return Form(
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              prefixIcon: const Icon(LucideIcons.mail),
              validator: Validators.email,
            ),
          ),
          const SizedBox(height: ZirenTokens.space24),
          ZirenButton(
            label: t.forgotSendLink,
            isLoading: _loading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _successView(AppLocalizations t) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZirenCard(
          padding: const EdgeInsets.all(ZirenTokens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: ZirenTokens.severityLowBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.mail_check,
                    size: 30,
                    color: ZirenTokens.systemSuccess,
                  ),
                ),
              ),
              const SizedBox(height: ZirenTokens.space20),
              Text(
                // Worded so it reveals nothing about whether the address is
                // registered — the provider swallows errors for the same
                // reason (email enumeration).
                t.forgotSentBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),
        ZirenButton(
          label: t.forgotBackToSignIn,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
