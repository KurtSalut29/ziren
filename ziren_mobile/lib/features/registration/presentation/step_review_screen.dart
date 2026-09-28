import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_error_banner.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/registration_repository.dart';
import '../domain/id_catalogue.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Final step — show everything back, then submit.
///
/// Every row jumps to the step that owns it. A review screen you cannot act on
/// is decoration: the point is to catch the transposed digit in a phone number
/// before an ambulance calls it.
class StepReviewScreen extends StatefulWidget {
  const StepReviewScreen({super.key});

  @override
  State<StepReviewScreen> createState() => _StepReviewScreenState();
}

class _StepReviewScreenState extends State<StepReviewScreen> {
  final _repo = RegistrationRepository();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(RegistrationDraft d, AuthProvider auth) async {
    // A draft resumed in a fresh process has no password — it is deliberately
    // never written to disk. Ask for it here rather than sending them back
    // through the whole flow.
    if (d.password.isEmpty) {
      if (_password.text.length < 8) {
        setState(() => _error = 'Please re-enter your password to continue.');
        return;
      }
      d.password = _password.text;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final outcome = await _repo.submit(d);
      if (!mounted) return;

      if (!outcome.evidenceUploaded) {
        // The account exists and works. Say so plainly rather than implying
        // the whole registration failed.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Account created, but your photos did not upload. '
              'You can add them from your profile.',
            ),
            backgroundColor: ZirenTokens.systemWarning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      } else if (d.isResponder) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created. Your Agency Admin will verify your badge '
              'before approving it.',
            ),
            backgroundColor: ZirenTokens.systemWarning,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 6),
          ),
        );
      }

      final role = d.role;
      d.reset();
      auth.adoptRegisteredSession(role: role);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Registration failed. $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final auth = context.read<AuthProvider>();
    final needsPassword = d.password.isEmpty;

    return RegistrationScaffold(
      step: RegStep.review,
      title: t.regReviewTitle,
      subtitle: t.regReviewSubtitle,
      continueLabel: d.isResponder ? 'Submit for approval' : 'Create account',
      isLoading: _submitting,
      onContinue: _submitting ? null : () => _submit(d, auth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ZirenErrorBanner(message: _error!),
            const SizedBox(height: ZirenTokens.space20),
          ],

          if (d.skippedVerification) _SkippedNotice(draft: d),

          _Group(
            title: t.regGroupAboutYou,
            step: RegStep.personal,
            rows: [
              (t.labelName, d.fullName.isEmpty ? null : d.fullName),
              (
                t.labelDateOfBirth,
                d.dateOfBirth == null
                    ? null
                    : '${d.dateOfBirth!.day.toString().padLeft(2, '0')}/'
                        '${d.dateOfBirth!.month.toString().padLeft(2, '0')}/'
                        '${d.dateOfBirth!.year}',
              ),
              (t.labelSex, _sexLabel(d.sex)),
            ],
          ),

          _Group(
            title: t.regGroupAddress,
            step: RegStep.address,
            rows: [
              (t.labelMunicipality, d.municipality),
              (t.labelBarangay, d.barangayName),
              (t.labelPurok, d.purokSitio.isEmpty ? null : d.purokSitio),
              (t.labelStreet, d.streetAddress.isEmpty ? null : d.streetAddress),
            ],
          ),

          _Group(
            title: t.regGroupContact,
            step: RegStep.contact,
            rows: [
              (t.labelEmail, d.email.isEmpty ? null : d.email),
              (t.labelMobile, d.phone.isEmpty ? null : d.phone),
              (
                t.labelEmergencyContact,
                d.emergencyContactName.isEmpty
                    ? null
                    : '${d.emergencyContactName} · ${d.emergencyContactNumber}',
              ),
              if (!d.isResponder)
                (
                  t.labelAccessibility,
                  d.isPwd || d.disabilities.isNotEmpty
                      ? '${d.disabilities.length} noted'
                      : null,
                ),
            ],
          ),

          if (d.isResponder)
            _Group(
              title: t.regGroupAgency,
              step: RegStep.responderDetails,
              rows: [
                ('Agency', d.agencyType),
                (t.labelBadgeId, d.badgeId.isEmpty ? null : d.badgeId),
                (
                  t.labelRank,
                  d.rankOrPosition.isEmpty ? null : d.rankOrPosition,
                ),
                (
                  t.labelUnit,
                  d.unitAssignment.isEmpty ? null : d.unitAssignment,
                ),
                (
                  t.labelAgencyIdPhoto,
                  d.agencyIdImagePath == null ? null : t.valueAttached,
                ),
              ],
            )
          else if (!d.skippedVerification)
            _Group(
              title: t.regGroupIdentity,
              step: RegStep.idType,
              rows: [
                (t.labelIdType, IdCatalogue.byValue(d.validIdType)?.label),
                (
                  t.labelIdNumber,
                  d.validIdNumber.isEmpty ? null : d.validIdNumber,
                ),
                (
                  t.labelIdPhoto,
                  d.idImagePath == null ? null : t.valueAttached,
                ),
              ],
            ),

          if (d.selfiePath != null) ...[
            const SizedBox(height: ZirenTokens.space8),
            Row(
              children: [
                ClipOval(
                  child: Image.file(
                    File(d.selfiePath!),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Text(
                    t.regSelfieAttached,
                    style: TextStyle(
                      fontSize: 13,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(RegStep.selfie.path),
                  child: Text(t.actionChange),
                ),
              ],
            ),
          ],

          if (needsPassword) ...[
            const SizedBox(height: ZirenTokens.space24),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.regReenterPassword,
              child: ZirenTextField(
                label: '',
                hint: t.hintYourPassword,
                controller: _password,
                obscureText: true,
                prefixIcon: const Icon(LucideIcons.lock),
                helperText:
                    'We never save your password to this device, so it has '
                    'to be typed again after a restart.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _sexLabel(String? value) => switch (value) {
    'male' => 'Male',
    'female' => 'Female',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => null,
  };
}

class _SkippedNotice extends StatelessWidget {
  const _SkippedNotice({required this.draft});
  final RegistrationDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space20),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.severityHighBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.hourglass,
                size: 18,
                color: ZirenTokens.systemWarning,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(child: Text(
                t.regVerificationSkipped,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textPrimary,
                ),
              )),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            t.regSkippedNotice,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space8),
          TextButton(
            onPressed: () {
              draft.skippedVerification = false;
              draft.commit();
              context.go(RegStep.idType.path);
            },
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(t.regVerifyNowInstead),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.step, required this.rows});

  final String title;
  final RegStep step;

  /// (label, value). A null value renders as "Not given" rather than being
  /// hidden — an omission the person did not intend is worth seeing here.
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: InkWell(
        onTap: () => context.go(step.path),
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.pencil,
                    size: 15,
                    color: ZirenTokens.brandOrange,
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: ZirenTokens.space8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value ?? t.valueNotGiven,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                value == null
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                            color:
                                value == null
                                    ? ZirenTokens.textMuted
                                    : ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
