import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/registration/data/registration_repository.dart';
import 'package:ziren/features/registration/domain/registration_draft.dart';

/// The accessibility profile describes how a crew should assist the person
/// reporting. A responder must never be registered with one.
void main() {
  RegistrationDraft residentWithAccessibility() => RegistrationDraft()
    ..role = 'resident'
    ..isPwd = true
    ..pwdIdNumber = 'PWD-123'
    ..disabilities = {'mobility'}
    ..accessibilityNotes = 'Uses a wheelchair';

  test('a resident sends their accessibility profile', () {
    final f = RegistrationRepository.accessibilityFields(residentWithAccessibility());
    expect(f['is_pwd'], isTrue);
    expect(f['disability_types'], ['mobility']);
    expect(f['pwd_id_number'], 'PWD-123');
    expect(f['accessibility_notes'], 'Uses a wheelchair');
  });

  test('switching to responder after filling it in sends none of it', () {
    // Resident, tick PWD on the contact step, back to the role step, pick
    // Responder: the draft still holds the resident answers.
    final d = residentWithAccessibility()..role = 'responder';
    final f = RegistrationRepository.accessibilityFields(d);
    expect(f['is_pwd'], isFalse);
    expect(f['disability_types'], isEmpty);
    expect(f.containsKey('pwd_id_number'), isFalse);
    expect(f.containsKey('accessibility_notes'), isFalse);
  });

  test('a PWD ID number is only sent when the resident is marked PWD', () {
    final d = residentWithAccessibility()..isPwd = false;
    final f = RegistrationRepository.accessibilityFields(d);
    expect(f['is_pwd'], isFalse);
    expect(f.containsKey('pwd_id_number'), isFalse);
  });

  test('responders never reach the resident-only ID steps', () {
    final steps = RegistrationDraft.stepsFor('responder');
    expect(steps, isNot(contains(RegStep.idType)));
    expect(steps, isNot(contains(RegStep.idCapture)));
  });
}
