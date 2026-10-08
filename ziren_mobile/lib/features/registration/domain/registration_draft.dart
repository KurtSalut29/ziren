import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The steps of registration, in order.
///
/// Responders skip [idType] and [idCapture] — their evidence is an agency ID
/// captured on [responderDetails] instead — and residents skip
/// [responderDetails]. [stepsFor] is the only place that branching lives.
enum RegStep {
  role,
  personal,
  address,
  contact,
  responderDetails,
  idType,
  idCapture,
  selfie,
  portrait,
  review,
}

extension RegStepRoute on RegStep {
  String get path => switch (this) {
    RegStep.role => '/register/role',
    RegStep.personal => '/register/personal',
    RegStep.address => '/register/address',
    RegStep.contact => '/register/contact',
    RegStep.responderDetails => '/register/responder',
    RegStep.idType => '/register/id-type',
    RegStep.idCapture => '/register/id-capture',
    RegStep.selfie => '/register/selfie',
    RegStep.portrait => '/register/portrait',
    RegStep.review => '/register/review',
  };
}

/// Everything the registration flow collects, held across screens and mirrored
/// to disk after every change.
///
/// Why this is persisted
/// ---------------------
/// The old flow was one screen with three internal steps and no persistence.
/// Backgrounding the app, an incoming call, or Android reclaiming memory threw
/// away everything typed. Spread across nine screens that would be
/// considerably worse, and the people most likely to lose the draft are the
/// ones on the weakest handsets.
///
/// So every setter writes through to SharedPreferences, and [restore] brings it
/// back. Captured images are kept as file paths rather than bytes — the files
/// live in the app's cache directory and survive a restart.
///
/// What is deliberately NOT persisted
/// ----------------------------------
/// The password. It is held in memory for the lifetime of the flow and never
/// written to disk. SharedPreferences is plain XML on Android, readable by
/// anything with access to the app sandbox, and a saved draft is not worth a
/// stored credential. If the draft is resumed in a new process the password
/// field is simply empty and the review screen asks for it again.
class RegistrationDraft extends ChangeNotifier {
  static const _prefsKey = 'registration_draft_v1';

  /// Which screen sent them here, so back on step one returns to it.
  ///
  /// Deliberately NOT persisted, and not part of the profile: it describes
  /// this trip through the flow, not the person. A resumed draft defaults to
  /// false, which lands on the welcome screen — the neutral screen for someone
  /// with no session, and it offers sign-in anyway.
  ///
  /// The step screens navigate with `go`, which discards the pushed login page
  /// underneath them, so by step two there is no stack left to pop back to.
  /// That is why this is remembered rather than inferred.
  bool cameFromSignIn = false;

  /// The step to go back to after correcting the name, when an ID step sent
  /// the person to fix it (the name has to match the ID). In memory only.
  RegStep? returnTo;

  // ── Role ────────────────────────────────────────────────────
  String role = 'resident';
  bool get isResponder => role == 'responder';

  // ── Personal ────────────────────────────────────────────────
  String firstName = '';
  String middleName = '';
  String lastName = '';
  String nameSuffix = '';
  DateTime? dateOfBirth;
  String? sex;

  String get fullName =>
      [
        firstName,
        middleName,
        lastName,
        nameSuffix,
      ].where((p) => p.trim().isNotEmpty).join(' ').trim();

  // ── Contact + credentials ───────────────────────────────────
  String email = '';
  String phone = '';

  /// In memory only. See the class comment.
  String password = '';

  String emergencyContactName = '';
  String emergencyContactNumber = '';

  // ── Address ─────────────────────────────────────────────────
  String? municipality;
  String? barangayId;
  String? barangayName; // for the review screen, so it need not refetch
  String purokSitio = '';
  String streetAddress = '';

  // ── Responder ───────────────────────────────────────────────
  String? agencyType;
  String badgeId = '';
  String rankOrPosition = '';
  String unitAssignment = '';
  DateTime? dateJoined;
  String? agencyIdImagePath;

  /// Whether the typed name was found on the agency ID photo. Required.
  bool? agencyIdNameMatched;

  // ── Accessibility ───────────────────────────────────────────
  bool isPwd = false;
  String pwdIdNumber = '';
  Set<String> disabilities = {};
  String accessibilityNotes = '';
  String contactMode = 'any';

  // ── Identity evidence ───────────────────────────────────────
  String? validIdType;
  String validIdNumber = '';
  String? idImagePath;
  String? residencyProofType;

  String? selfiePath;
  String? livenessMethod;
  DateTime? livenessAssertedAt;

  /// A resident who chose "Verify later" (user request 2026-10-08): the
  /// account is created without identity evidence and may report for its
  /// first 7 days (backend app/core/resident_trust.py), then only once an
  /// administrator has verified it from the Profile > Verify screen. Nothing
  /// half-collected is sent: it is all of the evidence or none of it.
  ///
  /// (2026-10-07 removed skipping outright; a draft saved then has it false.)
  bool skippedVerification = false;

  /// The 2x2 ID photo - the picture on the Ziren ID card - and what checking
  /// it found (domain/portrait_check.dart): stored under
  /// users.id_checks.portrait. Null checks mean "not checked against the
  /// current selfie", which is not a pass.
  String? portraitPath;
  Map<String, dynamic>? portraitChecks;

  /// Text ML Kit read off the ID, kept so the review screen can show what was
  /// matched and what was not. Never trusted over what the person typed.
  String? ocrRawText;
  bool? ocrNameMatched;

  /// Where valid_id_number came from: 'typed', 'ocr', or 'ocr_edited'.
  ///
  /// Set to 'ocr' when OCR filled the field, and promoted to 'ocr_edited' the
  /// moment the person changes it. A reviewing admin chasing a duplicate-ID
  /// flag needs to know whether the number was checked against the card by a
  /// machine or typed from memory — see migration 023.
  String? idNumberSource;

  /// What the on-device checks found on the ID photo. Stored as
  /// users.id_checks. Client-computed, therefore advisory.
  Map<String, dynamic>? idChecks;

  /// The result of comparing the ID portrait against the selfie.
  ///
  /// A SIGNAL, never a gate. `faceMatchVerdict == 'no_match'` does not stop
  /// anybody registering — an ID photograph fifteen years old scores badly and
  /// an admin approves it in four seconds. See migration 023 and
  /// face_match_service.py, both of which say the same thing at more length.
  String? faceMatchVerdict;
  double? faceMatchScore;
  String? faceMatchModel;
  DateTime? faceMatchCheckedAt;

  /// The aligned 112x112 RGB crop of the face on the ID, base64.
  ///
  /// Held only in memory and deliberately NOT persisted with the rest of the
  /// draft: it is biometric data, it is 50 KB of base64, and SharedPreferences
  /// is plaintext on disk. Its only job is to survive from the ID step to the
  /// selfie step so the two crops can be compared in one call. Losing it to a
  /// process death costs a re-read of a photo the app still has.
  String? idFaceCropB64;

  // ── Step sequencing ─────────────────────────────────────────

  List<RegStep> get steps => stepsFor(role);

  static List<RegStep> stepsFor(String role) {
    if (role == 'responder') {
      return const [
        RegStep.role,
        RegStep.personal,
        RegStep.address,
        RegStep.contact,
        RegStep.responderDetails,
        RegStep.selfie,
        RegStep.review,
      ];
    }
    return const [
      RegStep.role,
      RegStep.personal,
      RegStep.address,
      RegStep.contact,
      RegStep.idType,
      RegStep.idCapture,
      RegStep.selfie,
      RegStep.portrait,
      RegStep.review,
    ];
  }

  /// Where "Verify later" lands: the review, past every identity step.
  RegStep get afterSkip => RegStep.review;

  /// The identity steps, where "Verify later" is offered (residents only).
  static const identitySteps = {
    RegStep.idType,
    RegStep.idCapture,
    RegStep.selfie,
    RegStep.portrait,
  };

  int indexOf(RegStep step) {
    final i = steps.indexOf(step);
    // A step not in this role's list (e.g. idType while registering as a
    // responder) must not return -1 into a progress bar.
    return i < 0 ? 0 : i;
  }

  RegStep? next(RegStep from) {
    final i = steps.indexOf(from);
    if (i < 0 || i >= steps.length - 1) return null;
    return steps[i + 1];
  }

  RegStep? previous(RegStep from) {
    var i = steps.indexOf(from);
    if (i <= 0) return null;
    // After "Verify later" the identity steps were passed over, so Back from
    // the review passes over them too. Walking back into one with the flag
    // still set would let them fill it in and then send none of it; the
    // review's "Verify now instead" is the way back in.
    while (i > 0) {
      final step = steps[--i];
      if (!(skippedVerification &&
          !isResponder &&
          identitySteps.contains(step))) {
        return step;
      }
    }
    return null;
  }

  /// The first step whose evidence is missing, or null when the account can
  /// be submitted: the ID (photo, type, a name that matches it), the selfie
  /// and a checked 2x2 ID photo for a resident; the agency ID (with a
  /// matching name) and a selfie for a responder. A resident who chose
  /// "Verify later" sends none of it, so nothing is missing.
  RegStep? get missingEvidence {
    if (isResponder) {
      if (agencyIdImagePath == null || agencyIdNameMatched != true) {
        return RegStep.responderDetails;
      }
      if (selfiePath == null) return RegStep.selfie;
      return null;
    }
    if (skippedVerification) return null;
    if (validIdType == null) return RegStep.idType;
    if (idImagePath == null || ocrNameMatched != true) {
      return RegStep.idCapture;
    }
    if (selfiePath == null) return RegStep.selfie;
    if (portraitPath == null || portraitChecks == null) {
      return RegStep.portrait;
    }
    return null;
  }

  /// Whether identity evidence goes with the account: a responder's always,
  /// a resident's unless they chose "Verify later".
  bool get sendsIdentityEvidence => isResponder || !skippedVerification;

  // ── Mutation ────────────────────────────────────────────────

  /// Every screen changes fields directly and then calls this once, rather
  /// than each field having its own setter. Nine screens of setters would be
  /// several hundred lines of boilerplate for no added safety.
  void commit() {
    notifyListeners();
    // Fire and forget: the UI must never wait on a disk write, and a failed
    // write only costs the draft, which is already the fallback case.
    _persist();
  }

  void reset() {
    cameFromSignIn = false;
    returnTo = null;
    role = 'resident';
    firstName = middleName = lastName = nameSuffix = '';
    dateOfBirth = null;
    sex = null;
    email = phone = password = '';
    emergencyContactName = emergencyContactNumber = '';
    municipality = barangayId = barangayName = null;
    purokSitio = streetAddress = '';
    agencyType = null;
    badgeId = rankOrPosition = unitAssignment = '';
    dateJoined = null;
    agencyIdImagePath = null;
    agencyIdNameMatched = null;
    isPwd = false;
    pwdIdNumber = '';
    disabilities = {};
    accessibilityNotes = '';
    contactMode = 'any';
    validIdType = null;
    validIdNumber = '';
    idImagePath = null;
    residencyProofType = null;
    selfiePath = null;
    livenessMethod = null;
    livenessAssertedAt = null;
    skippedVerification = false;
    portraitPath = null;
    portraitChecks = null;
    ocrRawText = null;
    ocrNameMatched = null;
    idNumberSource = null;
    idChecks = null;
    faceMatchVerdict = null;
    faceMatchScore = null;
    faceMatchModel = null;
    faceMatchCheckedAt = null;
    idFaceCropB64 = null;
    notifyListeners();
    _clear();
  }

  // ── Persistence ─────────────────────────────────────────────

  Map<String, dynamic> _toMap() => {
    'role': role,
    'firstName': firstName,
    'middleName': middleName,
    'lastName': lastName,
    'nameSuffix': nameSuffix,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'sex': sex,
    'email': email,
    'phone': phone,
    // password intentionally absent
    'emergencyContactName': emergencyContactName,
    'emergencyContactNumber': emergencyContactNumber,
    'municipality': municipality,
    'barangayId': barangayId,
    'barangayName': barangayName,
    'purokSitio': purokSitio,
    'streetAddress': streetAddress,
    'agencyType': agencyType,
    'badgeId': badgeId,
    'rankOrPosition': rankOrPosition,
    'unitAssignment': unitAssignment,
    'dateJoined': dateJoined?.toIso8601String(),
    'agencyIdImagePath': agencyIdImagePath,
    'agencyIdNameMatched': agencyIdNameMatched,
    'isPwd': isPwd,
    'pwdIdNumber': pwdIdNumber,
    'disabilities': disabilities.toList(),
    'accessibilityNotes': accessibilityNotes,
    'contactMode': contactMode,
    'validIdType': validIdType,
    'validIdNumber': validIdNumber,
    'idImagePath': idImagePath,
    'residencyProofType': residencyProofType,
    'selfiePath': selfiePath,
    'livenessMethod': livenessMethod,
    'livenessAssertedAt': livenessAssertedAt?.toIso8601String(),
    'skippedVerification': skippedVerification,
    'portraitPath': portraitPath,
    'portraitChecks': portraitChecks,
    'ocrNameMatched': ocrNameMatched,
    'idNumberSource': idNumberSource,
    'idChecks': idChecks,
    'faceMatchVerdict': faceMatchVerdict,
    'faceMatchScore': faceMatchScore,
    'faceMatchModel': faceMatchModel,
    'faceMatchCheckedAt': faceMatchCheckedAt?.toIso8601String(),
    // idFaceCropB64 is absent on purpose — see its declaration.
  };

  void _fromMap(Map<String, dynamic> m) {
    role = m['role'] as String? ?? 'resident';
    firstName = m['firstName'] as String? ?? '';
    middleName = m['middleName'] as String? ?? '';
    lastName = m['lastName'] as String? ?? '';
    nameSuffix = m['nameSuffix'] as String? ?? '';
    dateOfBirth = DateTime.tryParse(m['dateOfBirth'] as String? ?? '');
    sex = m['sex'] as String?;
    email = m['email'] as String? ?? '';
    phone = m['phone'] as String? ?? '';
    emergencyContactName = m['emergencyContactName'] as String? ?? '';
    emergencyContactNumber = m['emergencyContactNumber'] as String? ?? '';
    municipality = m['municipality'] as String?;
    barangayId = m['barangayId'] as String?;
    barangayName = m['barangayName'] as String?;
    purokSitio = m['purokSitio'] as String? ?? '';
    streetAddress = m['streetAddress'] as String? ?? '';
    agencyType = m['agencyType'] as String?;
    badgeId = m['badgeId'] as String? ?? '';
    rankOrPosition = m['rankOrPosition'] as String? ?? '';
    unitAssignment = m['unitAssignment'] as String? ?? '';
    dateJoined = DateTime.tryParse(m['dateJoined'] as String? ?? '');
    agencyIdImagePath = m['agencyIdImagePath'] as String?;
    agencyIdNameMatched = m['agencyIdNameMatched'] as bool?;
    isPwd = m['isPwd'] as bool? ?? false;
    pwdIdNumber = m['pwdIdNumber'] as String? ?? '';
    disabilities =
        (m['disabilities'] as List?)?.map((e) => e as String).toSet() ?? {};
    accessibilityNotes = m['accessibilityNotes'] as String? ?? '';
    contactMode = m['contactMode'] as String? ?? 'any';
    validIdType = m['validIdType'] as String?;
    validIdNumber = m['validIdNumber'] as String? ?? '';
    idImagePath = m['idImagePath'] as String?;
    residencyProofType = m['residencyProofType'] as String?;
    selfiePath = m['selfiePath'] as String?;
    livenessMethod = m['livenessMethod'] as String?;
    livenessAssertedAt = DateTime.tryParse(
      m['livenessAssertedAt'] as String? ?? '',
    );
    skippedVerification = m['skippedVerification'] as bool? ?? false;
    portraitPath = m['portraitPath'] as String?;
    portraitChecks = (m['portraitChecks'] as Map?)?.cast<String, dynamic>();
    ocrNameMatched = m['ocrNameMatched'] as bool?;
    idNumberSource = m['idNumberSource'] as String?;
    idChecks = (m['idChecks'] as Map?)?.cast<String, dynamic>();
    faceMatchVerdict = m['faceMatchVerdict'] as String?;
    faceMatchScore = (m['faceMatchScore'] as num?)?.toDouble();
    faceMatchModel = m['faceMatchModel'] as String?;
    faceMatchCheckedAt = DateTime.tryParse(
      m['faceMatchCheckedAt'] as String? ?? '',
    );
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_toMap()));
    } catch (_) {
      // Losing the draft is recoverable; crashing the form is not.
    }
  }

  Future<void> _clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// True if a saved draft was found and loaded.
  Future<bool> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return false;
      _fromMap(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
      return true;
    } catch (_) {
      // A draft written by an older build may not parse. Discard it rather
      // than half-restoring into a form the user cannot correct.
      await _clear();
      return false;
    }
  }

  /// Does a stored draft exist, without loading it? Used to decide whether to
  /// offer "continue where you left off".
  static Future<bool> hasSavedDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey) != null;
    } catch (_) {
      return false;
    }
  }
}
