import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../auth/data/id_upload_service.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

const _agencyTypes = ['BFP', 'PNP', 'MDRRMO'];

/// Step 5 (responders) — agency, badge, and the agency ID that backs them up.
///
/// The agency ID photo is new. Until now an Agency Admin approved a responder
/// on the strength of a typed badge number with no document attached to it,
/// because the registration screen passed `validIdImage: null` for the whole
/// responder branch. Approving an account that can see every incident in a
/// municipality deserves at least as much evidence as a resident account.
class StepResponderScreen extends StatefulWidget {
  const StepResponderScreen({super.key});

  @override
  State<StepResponderScreen> createState() => _StepResponderScreenState();
}

class _StepResponderScreenState extends State<StepResponderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uploads = IdUploadService();

  late final TextEditingController _badge;
  late final TextEditingController _rank;
  late final TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    final d = context.read<RegistrationDraft>();
    _badge = TextEditingController(text: d.badgeId);
    _rank = TextEditingController(text: d.rankOrPosition);
    _unit = TextEditingController(text: d.unitAssignment);
  }

  @override
  void dispose() {
    _badge.dispose();
    _rank.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _pickAgencyId(RegistrationDraft d) async {
    final file = await _uploads.pickIdPhoto(source: ImageSource.camera);
    if (file == null || !mounted) return;
    d.agencyIdImagePath = file.path;
    d.commit();
  }

  Future<void> _pickJoinDate(RegistrationDraft d) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: d.dateJoined ?? now,
      firstDate: DateTime(now.year - 50),
      lastDate: now,
      helpText: 'Date you joined',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    d.dateJoined = picked;
    d.commit();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final joined = d.dateJoined;
    final complete = d.agencyType != null && _badge.text.trim().isNotEmpty;

    return RegistrationScaffold(
      step: RegStep.responderDetails,
      title: t.regAgencyTitle,
      subtitle: t.regAgencySubtitle,
      onContinue:
          complete
              ? () {
                if (!_formKey.currentState!.validate()) return;
                d.badgeId = _badge.text.trim();
                d.rankOrPosition = _rank.text.trim();
                d.unitAssignment = _unit.text.trim();
                d.commit();
                context.go(d.next(RegStep.responderDetails)!.path);
              }
              : null,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RegField(
              label: t.fieldAgency,
              child: Row(
                children: [
                  for (final agency in _agencyTypes) ...[
                    Expanded(
                      child: _AgencyCard(
                        agency: agency,
                        selected: d.agencyType == agency,
                        onTap: () {
                          d.agencyType = agency;
                          d.commit();
                        },
                      ),
                    ),
                    if (agency != _agencyTypes.last)
                      const SizedBox(width: ZirenTokens.space8),
                  ],
                ],
              ),
            ),
            if (d.municipality != null) ...[
              const SizedBox(height: ZirenTokens.space8),
              Text(
                'You will be assigned to the ${d.agencyType ?? 'agency'} office '
                'in ${d.municipality}.',
                style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
              ),
            ],

            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldBadgeId,
              child: ZirenTextField(
                label: '',
                hint: t.hintBadgeId,
                controller: _badge,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(LucideIcons.badge),
                validator: (v) => Validators.required(v, fieldName: 'Badge ID'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldRank,
              optional: true,
              child: ZirenTextField(
                label: '',
                hint: t.hintRank,
                controller: _rank,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(LucideIcons.award),
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldUnit,
              optional: true,
              child: ZirenTextField(
                label: '',
                hint: t.hintUnit,
                controller: _unit,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                prefixIcon: const Icon(LucideIcons.landmark),
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldDateJoined,
              optional: true,
              child: Material(
                color: ZirenTokens.surfaceRaised,
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                child: InkWell(
                  onTap: () => _pickJoinDate(d),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZirenTokens.space16,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 20,
                          color: ZirenTokens.textMuted,
                        ),
                        const SizedBox(width: ZirenTokens.space12),
                        Expanded(
                          child: Text(
                            joined == null
                                ? t.regChooseDate
                                : '${joined.day.toString().padLeft(2, '0')}/'
                                    '${joined.month.toString().padLeft(2, '0')}/'
                                    '${joined.year}',
                            style: TextStyle(
                              fontSize: 15,
                              color:
                                  joined == null
                                      ? ZirenTokens.textMuted
                                      : ZirenTokens.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          LucideIcons.chevron_right,
                          size: 20,
                          color: ZirenTokens.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: ZirenTokens.space24),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            const SizedBox(height: ZirenTokens.space20),

            RegField(
              label: t.fieldAgencyIdPhoto,
              optional: true,
              child: _AgencyIdPhoto(
                path: d.agencyIdImagePath,
                onCapture: () => _pickAgencyId(d),
                onRemove: () {
                  d.agencyIdImagePath = null;
                  d.commit();
                },
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              t.regAgencyIdWhy,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ZirenTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({
    required this.agency,
    required this.selected,
    required this.onTap,
  });

  final String agency;
  final bool selected;
  final VoidCallback onTap;

  /// Agency identity colours are fixed by the design tokens and must not be
  /// repurposed — they mean the same thing on the dispatcher's map.
  (Color, Color) get _colours => switch (agency) {
    'BFP' => (ZirenTokens.agencyBFP, ZirenTokens.agencyBFPBg),
    'PNP' => (ZirenTokens.agencyPNP, ZirenTokens.agencyPNPBg),
    _ => (ZirenTokens.agencyMDRRMO, ZirenTokens.agencyMDRRMOBg),
  };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colours;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: agency,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? bg : ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                border: Border.all(
                  color: selected ? fg : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                agency,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? fg : ZirenTokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgencyIdPhoto extends StatelessWidget {
  const _AgencyIdPhoto({
    required this.path,
    required this.onCapture,
    required this.onRemove,
  });

  final String? path;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (path == null) {
      return OutlinedButton.icon(
        onPressed: onCapture,
        icon: const Icon(LucideIcons.camera, size: 18),
        label: Text(t.regTakeAgencyIdPhoto),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: Image.file(
            File(path!),
            height: 170,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: ZirenTokens.space8,
          right: ZirenTokens.space8,
          child: Material(
            color: Colors.black.withValues(alpha: 0.6),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Remove photo',
              iconSize: 18,
              icon: const Icon(LucideIcons.x, color: Colors.white),
              onPressed: onRemove,
            ),
          ),
        ),
      ],
    );
  }
}
