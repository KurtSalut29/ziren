import '../../../l10n/app_localizations.dart';
import '../domain/incident_model.dart';
import '../domain/incident_provider.dart' show IncidentCategory;

/// Localised display names for incident status and category.
///
/// These used to live on IncidentModel as `statusLabel`, which meant the data
/// model carried English display strings with no way to reach a BuildContext.
/// The result was visible on a single card in My Reports: the progress stepper
/// underneath read "Natanggap · Sinusuri · May responder" while the badge
/// above it read "Received". Display text belongs in the widget layer, where
/// the resident's chosen language is available.
///
/// Wire values (`'received'`, `'fire'`, …) stay exactly as the API sends them.
/// Only what the resident reads changes.
class IncidentLabels {
  const IncidentLabels._();

  /// Status of a report, as the resident should read it.
  ///
  /// An unrecognised status returns the raw wire value rather than an empty
  /// string — if the backend adds a state before the app knows about it, a
  /// resident seeing `en_route` is better served than one seeing nothing.
  static String status(AppLocalizations l10n, String status) {
    switch (status) {
      case 'received':
        return l10n.statusReceived;
      case 'processing':
        return l10n.statusProcessing;
      case 'dispatched':
      // En route is still "a responder is on the way". Shown as its raw wire
      // word - `en_route` - to a resident, which is what this used to do.
      case 'en_route':
        return l10n.statusDispatched;
      case 'arrived':
        return l10n.statusArrived;
      case 'resolved':
        return l10n.statusResolved;
      case 'cancelled':
        return l10n.statusCancelled;
      default:
        return status;
    }
  }

  /// What the resident should read as the status of THIS report.
  ///
  /// [status] alone is not enough: an agency rejection is wire status
  /// `cancelled`, same as a report the resident withdrew, and "Cancelled" is
  /// the wrong word for one the agency looked at and turned down. This reads
  /// the review decision too. A pending clarification wins over the workflow
  /// stage, because "the agency is waiting on you" is the thing to act on.
  static String reportStatus(AppLocalizations l10n, IncidentModel incident) {
    if (incident.needsClarification) return l10n.statusNeedsReply;
    if (incident.isRejected) return l10n.statusRejected;
    if (incident.isCancelledByAgency) return l10n.statusCancelledByAgency;
    return status(l10n, incident.status);
  }

  /// The five wizard categories plus `other`.
  static String category(AppLocalizations l10n, IncidentCategory category) {
    switch (category) {
      case IncidentCategory.fire:
        return l10n.categoryFire;
      case IncidentCategory.medicalTrauma:
        return l10n.categoryMedicalTrauma;
      case IncidentCategory.vehicular:
        return l10n.categoryVehicular;
      case IncidentCategory.floodLandslideCalamity:
        return l10n.categoryFloodLandslideCalamity;
      case IncidentCategory.domesticDisputeCrime:
        return l10n.categoryDomesticDisputeCrime;
      case IncidentCategory.other:
        return l10n.categoryOther;
    }
  }

  /// The short, one-word form used where space is tight (quick-report header,
  /// Home's category grid, My Reports cards) — "Fire" rather than
  /// "Sunog / Fire".
  static String categoryShort(AppLocalizations l10n, IncidentCategory category) {
    switch (category) {
      case IncidentCategory.fire:
        return l10n.categoryFireShort;
      case IncidentCategory.medicalTrauma:
        return l10n.categoryMedicalShort;
      case IncidentCategory.vehicular:
        return l10n.categoryAccidentShort;
      case IncidentCategory.floodLandslideCalamity:
        return l10n.categoryCalamityShort;
      case IncidentCategory.domesticDisputeCrime:
        return l10n.categoryCrimeShort;
      case IncidentCategory.other:
        return l10n.categoryOtherShort;
    }
  }

  /// Same as [category], but from the wire value the API stores.
  /// Returns null for an unknown value so callers can omit the row entirely
  /// rather than print a raw enum name at a resident.
  static String? categoryFromValue(AppLocalizations l10n, String? value) {
    if (value == null) return null;
    for (final c in IncidentCategory.values) {
      if (c.value == value) return category(l10n, c);
    }
    return null;
  }
}
