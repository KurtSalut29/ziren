/// One acceptable identity document.
class IdOption {
  const IdOption({
    required this.value,
    required this.label,
    required this.provesResidency,
    this.hint,
  });

  /// Matches the `valid_id_type` CHECK constraint in migration 012. Adding a
  /// value here without adding it there produces a 23514 at registration.
  final String value;
  final String label;

  /// Whether this document establishes that the holder lives in Biliran.
  ///
  /// An LGU issues its IDs only to its own residents, so a barangay ID or a
  /// PWD ID from a Biliran municipality is direct evidence of residency. A
  /// passport proves who someone is and says nothing at all about where they
  /// live. Both are useful, for different things, and the registration flow
  /// tells the person which one they are giving us.
  final bool provesResidency;

  final String? hint;
}

/// The documents Ziren accepts, split by what they actually prove.
abstract final class IdCatalogue {
  static const lguIssued = <IdOption>[
    IdOption(
      value: 'barangay_id',
      label: 'Barangay ID or Clearance',
      provesResidency: true,
      hint: 'Issued by your own barangay',
    ),
    IdOption(
      value: 'voters_id',
      label: "Voter's ID",
      provesResidency: true,
      hint: 'Registered in Biliran',
    ),
    IdOption(
      value: 'pwd_id',
      label: 'PWD ID',
      provesResidency: true,
      hint: 'Issued by your MSWDO or PDAO',
    ),
    IdOption(
      value: 'senior_citizen_id',
      label: 'Senior Citizen ID',
      provesResidency: true,
      hint: 'Issued by your OSCA',
    ),
  ];

  static const national = <IdOption>[
    IdOption(
      value: 'philsys',
      label: 'PhilSys / National ID',
      provesResidency: false,
    ),
    IdOption(value: 'umid', label: 'UMID', provesResidency: false),
    IdOption(
      value: 'drivers_license',
      label: "Driver's License",
      provesResidency: false,
    ),
    IdOption(value: 'passport', label: 'Passport', provesResidency: false),
    IdOption(value: 'postal_id', label: 'Postal ID', provesResidency: false),
    IdOption(
      value: 'philhealth',
      label: 'PhilHealth ID',
      provesResidency: false,
    ),
    IdOption(value: 'sss', label: 'SSS ID', provesResidency: false),
    IdOption(value: 'tin', label: 'TIN ID', provesResidency: false),
  ];

  static List<IdOption> get all => [...lguIssued, ...national];

  static IdOption? byValue(String? value) {
    if (value == null) return null;
    for (final o in all) {
      if (o.value == value) return o;
    }
    return null;
  }

  /// The `residency_proof_type` to record for a chosen ID. Mirrors the CHECK
  /// constraint added in migration 020.
  static String residencyProofFor(String? idType) {
    final option = byValue(idType);
    if (option == null) return 'none';
    return option.provesResidency ? 'lgu_id' : 'national_id';
  }
}

/// Disability categories offered in the accessibility profile.
///
/// The labels describe the operational consequence rather than the condition,
/// because that is what the responding crew needs to act on.
const disabilityOptions = <({String value, String label})>[
  (value: 'hearing', label: 'Deaf or hard of hearing'),
  (value: 'speech', label: 'Speech disability'),
  (value: 'visual', label: 'Blind or low vision'),
  (value: 'mobility', label: 'Mobility disability'),
  (value: 'intellectual', label: 'Intellectual disability'),
  (value: 'psychosocial', label: 'Psychosocial disability'),
];
