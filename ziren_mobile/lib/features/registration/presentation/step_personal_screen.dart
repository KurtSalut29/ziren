import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 2 — the name as it appears on the ID, plus date of birth and sex.
///
/// Why the name is split into parts
/// --------------------------------
/// The old form had one "Full name" box. An administrator is being asked to
/// compare what was typed against the name printed on a card, and a single
/// blob makes that comparison unreliable — "Juan Cruz dela Rosa" against
/// "DELA ROSA, JUAN C." is a judgement call rather than a check. Parts also
/// let the OCR step match on surname alone, which is the part that actually
/// discriminates.
///
/// `full_name` still exists and is composed from these by a database trigger,
/// so nothing downstream had to change.
class StepPersonalScreen extends StatefulWidget {
  const StepPersonalScreen({super.key});

  @override
  State<StepPersonalScreen> createState() => _StepPersonalScreenState();
}

class _StepPersonalScreenState extends State<StepPersonalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _middle;
  late final TextEditingController _last;
  late final TextEditingController _suffix;

  @override
  void initState() {
    super.initState();
    final d = context.read<RegistrationDraft>();
    _first = TextEditingController(text: d.firstName);
    _middle = TextEditingController(text: d.middleName);
    _last = TextEditingController(text: d.lastName);
    _suffix = TextEditingController(text: d.nameSuffix);
  }

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _suffix.dispose();
    super.dispose();
  }

  void _save(RegistrationDraft d) {
    d.firstName = _first.text.trim();
    d.middleName = _middle.text.trim();
    d.lastName = _last.text.trim();
    d.nameSuffix = _suffix.text.trim();
    d.commit();
  }

  Future<void> _pickDob(RegistrationDraft d) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: d.dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Date of birth',
      // Opens on the year grid. Scrolling a calendar back three decades a
      // month at a time is the classic way to make a date of birth painful.
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    d.dateOfBirth = picked;
    d.commit();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final dob = d.dateOfBirth;
    final complete =
        _last.text.trim().isNotEmpty && _first.text.trim().isNotEmpty;

    return RegistrationScaffold(
      step: RegStep.personal,
      title: t.regNameTitle,
      subtitle: t.regNameSubtitle,
      onContinue:
          complete
              ? () {
                if (!_formKey.currentState!.validate()) return;
                _save(d);
                context.go(d.next(RegStep.personal)!.path);
              }
              : null,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RegField(
              label: t.fieldFirstName,
              child: ZirenTextField(
                label: '',
                hint: t.hintFirstName,
                controller: _first,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator:
                    (v) => Validators.required(v, fieldName: 'First name'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldMiddleName,
              optional: true,
              child: ZirenTextField(
                label: '',
                hint: t.hintMiddleName,
                controller: _middle,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldLastName,
              child: ZirenTextField(
                label: '',
                hint: t.hintLastName,
                controller: _last,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator:
                    (v) => Validators.required(v, fieldName: 'Last name'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldSuffix,
              optional: true,
              child: ZirenTextField(
                label: '',
                hint: t.hintSuffix,
                controller: _suffix,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
              ),
            ),

            const SizedBox(height: ZirenTokens.space24),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            const SizedBox(height: ZirenTokens.space24),

            RegField(
              label: t.fieldDateOfBirth,
              optional: true,
              child: _PickerTile(
                icon: LucideIcons.cake,
                value:
                    dob == null
                        ? t.regChooseDob
                        : '${dob.day.toString().padLeft(2, '0')}/'
                            '${dob.month.toString().padLeft(2, '0')}/${dob.year}',
                isPlaceholder: dob == null,
                onTap: () => _pickDob(d),
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              t.regDobWhy,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ZirenTokens.textMuted,
              ),
            ),

            const SizedBox(height: ZirenTokens.space20),
            RegField(
              label: t.fieldSex,
              optional: true,
              child: Row(
                children: [
                  for (final option in [
                    (value: 'male', label: t.sexMale),
                    (value: 'female', label: t.sexFemale),
                    (value: 'prefer_not_to_say', label: t.sexPreferNotToSay),
                  ]) ...[
                    Expanded(
                      child: _Chip(
                        label: option.label,
                        selected: d.sex == option.value,
                        onTap: () {
                          // Tapping the selected option clears it — the field
                          // is optional, so there has to be a way back out.
                          d.sex = d.sex == option.value ? null : option.value;
                          d.commit();
                        },
                      ),
                    ),
                    if (option.value != 'prefer_not_to_say')
                      const SizedBox(width: ZirenTokens.space8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.value,
    required this.isPlaceholder,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final bool isPlaceholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZirenTokens.surfaceRaised,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: ZirenTokens.textMuted),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color:
                        isPlaceholder
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
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                border: Border.all(
                  color:
                      selected ? ZirenTokens.brandOrange : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
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
