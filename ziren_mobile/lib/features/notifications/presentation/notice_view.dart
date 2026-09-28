import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../incident_report/presentation/incident_labels.dart';
import '../domain/notification_provider.dart';

/// What a notice offers to do about itself.
enum NoticeAction {
  /// Just close it.
  dismiss,

  /// Open the report it is about.
  viewReport,

  /// Open the chat on the report, to answer a question or a message.
  openChat,
}

/// One notification, as the resident should read it: the words, the picture and
/// the buttons. A pure function of ([AppNotification], the language), so the
/// pop-up, the notifications list and the tests all read from the same place and
/// cannot disagree about what "a responder is on the way" is called.
///
/// WHY EVERY KIND HAS ITS OWN WORDS
///
/// A notice used to be one template with the status dropped into it: "Report
/// update - Cancelled - Your report was cancelled." That sentence was shown when
/// the resident moved their own report to Trash (they had just done it), when the
/// agency cancelled it (and it gave no reason), and when the agency rejected it.
/// Three different things, one line. Now each says what actually happened, in the
/// words for it, and offers the one thing worth doing about it.
class NoticeView {
  const NoticeView({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.quote,
    this.help,
    this.etaLine,
    this.stage,
    this.halted = false,
    this.primary = NoticeAction.dismiss,
    this.primaryLabel = '',
  });

  final IconData icon;
  final Color color;

  /// The headline: what happened.
  final String title;

  /// One sentence saying it plainly.
  final String body;

  /// The agency's own words - its reason, its question or its message.
  final String? quote;

  /// What to do next, when there is something.
  final String? help;

  /// "About 7 minutes" - only while help is on the way.
  final String? etaLine;

  /// Where the report stands on the four-step rail, when the rail is useful.
  final int? stage;

  /// The rail is drawn stopped at the first step (the report will go no further).
  final bool halted;

  /// The main button. [NoticeAction.dismiss] means the only button is "Got it".
  final NoticeAction primary;
  final String primaryLabel;

  bool get hasRail => stage != null || halted;
}

/// The canonical four-step rail every report shares (My Reports, the detail
/// screen, and here). En route and arrived are both part of "responder on the
/// way": a rail that read them as "before received" was how a resident whose
/// responder had arrived saw an empty progress bar.
int noticeStage(String status) => switch (status) {
  'received' => 0,
  'processing' => 1,
  'dispatched' || 'en_route' || 'arrived' => 2,
  'resolved' => 3,
  _ => 0,
};

NoticeView noticeView(AppLocalizations t, AppNotification n) {
  final status = n.newStatus;
  final detail = (n.detail ?? '').trim();

  switch (n.kind) {
    case NotificationKind.accepted:
      return NoticeView(
        icon: LucideIcons.shield_check,
        // Blue, the verification colour - see VerificationBanner. Not green:
        // accepted is not resolved.
        color: ZirenTokens.systemInfo,
        title: t.notifAcceptedTitle,
        body: t.notifAcceptedBody,
        stage: 1,
      );

    case NotificationKind.rejected:
      return NoticeView(
        icon: LucideIcons.circle_x,
        color: ZirenTokens.systemWarning,
        title: t.notifRejectedTitle,
        body: t.reportRejectedTitle,
        quote: detail.isEmpty ? null : detail,
        help: t.reportRejectedHelp,
        primary: NoticeAction.viewReport,
        primaryLabel: t.notifViewReport,
      );

    case NotificationKind.clarification:
      return NoticeView(
        icon: LucideIcons.message_circle_question_mark,
        color: ZirenTokens.systemWarning,
        title: t.notifClarificationTitle,
        body: t.clarificationReplyHint,
        quote: detail.isEmpty ? null : detail,
        primary: NoticeAction.openChat,
        primaryLabel: t.notifReplyNow,
      );

    case NotificationKind.cancelled:
      return NoticeView(
        icon: LucideIcons.circle_x,
        color: ZirenTokens.systemWarning,
        title: t.notifCancelledTitle,
        body: detail.isEmpty ? t.notifCancelledBody : t.notifCancelledReason(detail),
        help: t.notifCancelledHelp,
        halted: true,
        primary: NoticeAction.viewReport,
        primaryLabel: t.notifViewReport,
      );

    case NotificationKind.message:
      return NoticeView(
        icon: LucideIcons.message_square,
        color: ZirenTokens.brandOrange,
        title: n.serverTitle?.trim().isNotEmpty == true ? n.serverTitle!.trim() : t.notifMessageTitle,
        body: t.notifMessageHelp,
        quote: detail.isEmpty ? null : detail,
        primary: NoticeAction.openChat,
        primaryLabel: t.notifOpenChat,
      );

    case NotificationKind.status:
      break;
  }

  switch (status) {
    case 'processing':
      return NoticeView(
        icon: LucideIcons.clipboard_check,
        color: ZirenTokens.systemInfo,
        title: IncidentLabels.status(t, 'processing'),
        body: t.notifStatusProcessing,
        stage: 1,
      );
    case 'dispatched':
      return NoticeView(
        icon: LucideIcons.truck,
        color: ZirenTokens.brandOrange,
        title: IncidentLabels.status(t, 'dispatched'),
        body: t.notifStatusDispatched,
        etaLine: _etaLine(t, n),
        stage: 2,
      );
    case 'en_route':
      return NoticeView(
        icon: LucideIcons.navigation,
        color: ZirenTokens.brandOrange,
        title: IncidentLabels.status(t, 'en_route'),
        body: t.notifEnRouteBody,
        etaLine: _etaLine(t, n),
        stage: 2,
      );
    case 'arrived':
      return NoticeView(
        icon: LucideIcons.map_pin,
        color: ZirenTokens.brandOrange,
        title: IncidentLabels.status(t, 'arrived'),
        body: t.notifArrivedBody,
        stage: 2,
      );
    case 'resolved':
      return NoticeView(
        icon: LucideIcons.circle_check_big,
        color: ZirenTokens.systemSuccess,
        title: IncidentLabels.status(t, 'resolved'),
        body: t.notifStatusResolved,
        help: t.notifResolvedHelp,
        stage: 3,
        primary: NoticeAction.viewReport,
        primaryLabel: t.notifViewReport,
      );
    default:
      // A status the app does not recognise yet: say it as it is rather than
      // swallow it - see IncidentLabels.status.
      return NoticeView(
        icon: LucideIcons.info,
        color: ZirenTokens.brandOrange,
        title: IncidentLabels.status(t, status),
        body: status,
      );
  }
}

/// "About 7 minutes", never a clock time - same rule and rounding as
/// IncidentModel.etaLabel, from the two columns the realtime row carries.
String? _etaLine(AppLocalizations t, AppNotification n) {
  final m = n.etaMinutes;
  if (m == null) return null;
  final eta = m <= 1 ? t.respNavClose : t.incidentEtaMinutes(m);
  final agency = n.respondingAgency;
  return agency != null
      ? t.activeReportAgencyEnRoute(agency, eta)
      : t.activeReportResponderEnRoute(eta);
}
