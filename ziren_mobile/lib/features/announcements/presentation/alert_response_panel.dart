import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../auth/domain/auth_provider.dart';
import '../../incident_report/domain/incident_provider.dart';
import '../data/announcement_repository.dart';
import '../domain/announcement_model.dart';

/// Where the phone is, for an "I need help" answer. Null when there is no fix
/// (location refused, or none yet) - the answer is sent without one.
typedef PositionReader = ({double latitude, double longitude})? Function(BuildContext);

({double latitude, double longitude})? _currentPosition(BuildContext context) {
  try {
    final p = context.read<IncidentProvider>().currentPosition;
    return p == null ? null : (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null; // no IncidentProvider above this widget (a test, a preview)
  }
}

/// Only a resident answers a safety alert (the server refuses anyone else). A
/// responder can open the same alert from their notifications, and must not be
/// shown buttons that can only fail. With no AuthProvider above (a test), yes.
bool canAnswerAlerts(BuildContext context) {
  try {
    final role = context.read<AuthProvider>().userRole;
    return role == null || role == 'resident';
  } catch (_) {
    return true;
  }
}

/// "Are you safe?" - the resident's answer to a safety alert that asked.
///
/// Two big buttons, one tap each. "I am safe" is sent at once. "I need help"
/// asks for one optional line ("three children on the roof") and sends the
/// phone's position with it, and the stations of the resident's town are told
/// straight away. Once answered, the panel says what was said - and whether a
/// station has reached them - with a way to change it.
///
/// If the answer cannot be sent, "I need help" does not just fail: it offers
/// the hotlines, because a call needs only signal.
class AlertResponsePanel extends StatefulWidget {
  const AlertResponsePanel({
    super.key,
    required this.announcement,
    this.repository,
    this.onAnswered,
    this.positionReader,
    this.dense = false,
  });

  final AnnouncementModel announcement;
  final AnnouncementRepository? repository;
  final ValueChanged<AlertResponse>? onAnswered;
  final PositionReader? positionReader;

  /// Smaller, for the card on Home.
  final bool dense;

  @override
  State<AlertResponsePanel> createState() => _AlertResponsePanelState();
}

class _AlertResponsePanelState extends State<AlertResponsePanel> {
  late final AnnouncementRepository _repo = widget.repository ?? AnnouncementRepository();
  AlertResponse? _answer;
  String? _sending;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _answer = widget.announcement.myResponse;
  }

  @override
  void didUpdateWidget(AlertResponsePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.myResponse != widget.announcement.myResponse &&
        widget.announcement.myResponse != null) {
      _answer = widget.announcement.myResponse;
    }
  }

  Future<void> _send(String status) async {
    final t = AppLocalizations.of(context);
    String? note;
    if (status == 'need_help') {
      var typed = '';
      final go = await showZirenDialog<bool>(
        context,
        icon: LucideIcons.life_buoy,
        tone: ZirenTone.danger,
        title: t.annNeedHelpTitle,
        message: t.annNeedHelpBody,
        body: _HelpNote(hint: t.annNeedHelpHint, onChanged: (v) => typed = v),

        actions: [
          ZirenDialogAction(label: t.annNeedHelpSend, value: true, kind: ZirenActionKind.danger, icon: LucideIcons.life_buoy),
          ZirenDialogAction(label: t.annCancel, value: false),
        ],
      );
      note = typed;
      if (go != true || !mounted) return;
    }

    final where = status == 'need_help'
        ? (widget.positionReader ?? _currentPosition)(context)
        : null;
    setState(() => _sending = status);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final answer = await _repo.respond(
        widget.announcement.id,
        status: status,
        note: note,
        latitude: where?.latitude,
        longitude: where?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _changing = false;
        _sending = null;
      });
      widget.onAnswered?.call(answer);
      if (messenger != null) {
        ZirenToast.success(messenger, status == 'safe' ? t.annSentSafe : t.annSentHelp);
      }
    } on AlertEndedException {
      if (!mounted) return;
      setState(() => _sending = null);
      await showZirenDialog<void>(
        context,
        icon: LucideIcons.shield_check,
        tone: ZirenTone.info,
        title: t.annEndedTitle,
        message: t.annEndedBody,
        actions: [ZirenDialogAction(label: t.notifStatusOk, value: null, kind: ZirenActionKind.primary)],
      );
    } on Failure {
      if (!mounted) return;
      setState(() => _sending = null);
      // Asking for help and not being heard is the one failure that must
      // point somewhere else at once.
      final call = await showZirenDialog<bool>(
        context,
        icon: LucideIcons.wifi_off,
        tone: status == 'need_help' ? ZirenTone.danger : ZirenTone.warning,
        title: t.annNotSentTitle,
        message: status == 'need_help' ? t.annNotSentHelpBody : t.annNotSentBody,
        actions: [
          if (status == 'need_help')
            ZirenDialogAction(label: t.accountOpenHotlines, value: true, kind: ZirenActionKind.danger, icon: LucideIcons.phone),
          ZirenDialogAction(label: t.notifStatusOk, value: false),
        ],
      );
      if (call == true && mounted) await context.push('/hotlines');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final answer = _answer;
    if (answer != null && !_changing) return _answered(t, answer);
    if (!widget.announcement.canAnswer) return const SizedBox.shrink();

    return Column(
      key: const Key('alert-response-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.annAreYouSafe,
          style: TextStyle(
            fontSize: widget.dense ? 13.5 : 15,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textPrimary,
          ),
        ),
        const SizedBox(height: ZirenTokens.space8),
        _BigButton(
          key: const Key('alert-safe'),
          icon: LucideIcons.shield_check,
          label: t.annImSafe,
          color: ZirenTokens.systemSuccess,
          busy: _sending == 'safe',
          enabled: _sending == null,
          dense: widget.dense,
          onTap: () => _send('safe'),
        ),
        const SizedBox(height: ZirenTokens.space8),
        _BigButton(
          key: const Key('alert-need-help'),
          icon: LucideIcons.life_buoy,
          label: t.annINeedHelp,
          color: ZirenTokens.severityCritical,
          busy: _sending == 'need_help',
          enabled: _sending == null,
          dense: widget.dense,
          onTap: () => _send('need_help'),
        ),
        if (_changing)
          TextButton(
            onPressed: () => setState(() => _changing = false),
            child: Text(t.annCancel),
          ),
      ],
    );
  }

  Widget _answered(AppLocalizations t, AlertResponse a) {
    final help = a.needsHelp;
    final reached = help && a.handledAt != null;
    final color = help && !reached ? ZirenTokens.severityCritical : ZirenTokens.systemSuccess;
    final text = !help
        ? t.annYouSaidSafe
        : reached
        ? t.annHelpReached
        : t.annYouAskedHelp;
    return Container(
      key: Key(help ? 'alert-answered-help' : 'alert-answered-safe'),
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(help && !reached ? LucideIcons.life_buoy : LucideIcons.shield_check, size: 20, color: color),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ZirenTokens.textPrimary),
                ),
                if (help && !reached) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.annHelpWhileWaiting,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: ZirenTokens.textSecondary),
                  ),
                ],
                if ((a.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '“${a.note!.trim()}”',
                    style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: ZirenTokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (widget.announcement.canAnswer)
            TextButton(
              key: const Key('alert-change'),
              onPressed: () => setState(() => _changing = true),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(t.annChange),
            ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;
  final bool enabled;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: dense ? 48 : 54,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: busy ? 0.85 : 0.45),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZirenTokens.radius12)),
          textStyle: TextStyle(fontSize: dense ? 14.5 : 15.5, fontWeight: FontWeight.w700),
        ),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

/// The one optional line under "I need help". Its own widget so the text
/// controller lives exactly as long as the field: disposing it as soon as the
/// dialog returned - while the dialog was still animating away with the field
/// in it - threw "A TextEditingController was used after being disposed".
class _HelpNote extends StatefulWidget {
  const _HelpNote({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_HelpNote> createState() => _HelpNoteState();
}

class _HelpNoteState extends State<_HelpNote> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('alert-help-note'),
      controller: _controller,
      onChanged: widget.onChanged,
      maxLength: 300,
      maxLines: 3,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: widget.hint),
    );
  }
}