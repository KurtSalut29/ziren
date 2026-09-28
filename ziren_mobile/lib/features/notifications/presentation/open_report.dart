import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../incident_report/domain/incident_provider.dart';
import '../../incident_report/presentation/report_detail_screen.dart';
import '../../incident_report/presentation/widgets/incident_thread_sheet.dart';

/// Open one of the resident's own reports by id.
///
/// A notification carries an id, not a report - the rejected or clarified
/// report has to be found in (a fresh copy of) the resident's list first. If it
/// is no longer there (removed from Trash after 30 days, say) the Reports tab is
/// the honest place to land, not an error.
Future<void> openReportById(BuildContext context, String incidentId) async {
  final incidents = context.read<IncidentProvider>();
  await incidents.loadMyIncidents();
  if (!context.mounted) return;

  final match = incidents.myIncidents.where((i) => i.id == incidentId);
  if (match.isEmpty) {
    context.go('/my-reports');
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => ReportDetailScreen(incident: match.first),
    ),
  );
}

/// Open the chat on one of the resident's own reports by id - where a question
/// from the agency is answered and a message from it is read. Same fallback as
/// [openReportById] when the report is no longer in the list.
Future<void> openReportChatById(BuildContext context, String incidentId) async {
  final incidents = context.read<IncidentProvider>();
  await incidents.loadMyIncidents();
  if (!context.mounted) return;

  final match = incidents.myIncidents.where((i) => i.id == incidentId);
  if (match.isEmpty) {
    context.go('/my-reports');
    return;
  }
  await showIncidentThreadSheet(context, match.first);
}
