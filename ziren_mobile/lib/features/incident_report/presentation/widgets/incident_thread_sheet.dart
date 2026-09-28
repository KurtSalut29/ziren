import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/incident_model.dart';
import '../../domain/incident_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'review_notice.dart';

/// "Add Information to an Existing Report" (spec Section 14) and
/// "Incident-Specific Communication" (Section 16), as one sheet.
///
/// They read as two features in the spec but are the same act from the
/// reporter's side: a line added to the one thread tied to this incident,
/// which the agency can also write back on. Splitting them into two screens
/// would mean asking a resident which of two identical-looking text boxes
/// to use for "3 people still inside" — the backend table is already one
/// thread (migration 031), and the UI follows it.
Future<void> showIncidentThreadSheet(
  BuildContext context,
  IncidentModel incident,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _IncidentThreadSheet(incident: incident),
  );
}

class _IncidentThreadSheet extends StatefulWidget {
  const _IncidentThreadSheet({required this.incident});
  final IncidentModel incident;

  @override
  State<_IncidentThreadSheet> createState() => _IncidentThreadSheetState();
}

class _IncidentThreadSheetState extends State<_IncidentThreadSheet> {
  final _controller = TextEditingController();
  List<IncidentNote>? _notes;
  String? _loadError;
  bool _sending = false;
  String? _sendError;

  /// Set once a reply has gone out, so the question the agency asked is not
  /// left sitting over an answer that has already been sent.
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await context.read<IncidentProvider>().fetchIncidentNotes(
        widget.incident.id,
      );
      if (mounted) setState(() => _notes = notes);
    } catch (e) {
      if (mounted) {
        setState(
          () => _loadError = AppLocalizations.of(context).threadLoadError,
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final error = await context.read<IncidentProvider>().sendIncidentNote(
      widget.incident.id,
      text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _sendError = error;
      });
      return;
    }
    _controller.clear();
    await _load();
    if (mounted) {
      setState(() {
        _sending = false;
        if (widget.incident.needsClarification) _answered = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final closed =
        widget.incident.status == 'resolved' ||
        widget.incident.status == 'cancelled';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceCard,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(ZirenTokens.radius24),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: ZirenTokens.space12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZirenTokens.space20,
                    ZirenTokens.space16,
                    ZirenTokens.space20,
                    ZirenTokens.space8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.message_square,
                        size: 18,
                        color: ZirenTokens.brandOrange,
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      Expanded(
                        child: Text(
                          t.threadTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: ZirenTokens.surfaceBorder),
                // The agency's question, pinned above the thread so the
                // resident sees what they are answering.
                if (widget.incident.needsClarification && !_answered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ZirenTokens.space16,
                      ZirenTokens.space12,
                      ZirenTokens.space16,
                      0,
                    ),
                    child: ReviewNotice(
                      icon: LucideIcons.message_circle_question_mark,
                      title: t.clarificationTitle,
                      label: t.clarificationAsked,
                      body: widget.incident.clarificationNote,
                      footnote: t.clarificationReplyHint,
                    ),
                  ),
                Expanded(child: _buildBody(scrollController, t)),
                if (!closed) _buildComposer(t) else _buildClosedNotice(t),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController, AppLocalizations t) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space24),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: ZirenTokens.textMuted),
          ),
        ),
      );
    }
    if (_notes == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: ZirenTokens.brandOrange,
          strokeWidth: 2,
        ),
      );
    }
    if (_notes!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.message_square,
                size: 36,
                color: ZirenTokens.surfaceBorder,
              ),
              const SizedBox(height: ZirenTokens.space12),
              Text(
                t.threadEmptyTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textSecondary,
                ),
              ),
              const SizedBox(height: ZirenTokens.space4),
              Text(
                t.threadEmptyBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(ZirenTokens.space16),
      itemCount: _notes!.length,
      itemBuilder: (context, i) {
        final note = _notes![i];
        // A "run" is a block of consecutive messages from the same person —
        // real messenger apps show the avatar and name once per run, not on
        // every bubble, which is most of what makes a thread read as a
        // conversation rather than a stack of identical cards.
        final prev = i > 0 ? _notes![i - 1] : null;
        final next = i < _notes!.length - 1 ? _notes![i + 1] : null;
        final isRunStart = prev == null || prev.authorId != note.authorId;
        final isRunEnd = next == null || next.authorId != note.authorId;
        return _NoteBubble(
          note: note,
          incident: widget.incident,
          showAvatar: isRunStart,
          showName: isRunStart,
          tightTop: !isRunStart,
          roundedTail: isRunEnd,
        );
      },
    );
  }

  Widget _buildComposer(AppLocalizations t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space16,
          ZirenTokens.space10,
          ZirenTokens.space16,
          ZirenTokens.space10,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_sendError != null) ...[
              Text(
                _sendError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: ZirenTokens.systemError,
                ),
              ),
              const SizedBox(height: ZirenTokens.space6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: t.threadComposerHint,
                      isDense: true,
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: ZirenTokens.brandOrange,
                    disabledBackgroundColor: ZirenTokens.surfaceBorder,
                  ),
                  icon:
                      _sending
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(LucideIcons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedNotice(AppLocalizations t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(ZirenTokens.space16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        ),
        child: Text(
          t.threadClosedNotice,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
        ),
      ),
    );
  }
}

class _NoteBubble extends StatelessWidget {
  const _NoteBubble({
    required this.note,
    required this.incident,
    required this.showAvatar,
    required this.showName,
    required this.tightTop,
    required this.roundedTail,
  });

  final IncidentNote note;
  final IncidentModel incident;

  /// First message of a consecutive run from this author — gets the avatar
  /// and name. A run's later messages sit under it with a spacer instead, so
  /// the column of bubbles still lines up.
  final bool showAvatar;
  final bool showName;

  /// Later messages in a run sit closer together than the gap before a new
  /// speaker starts — the same visual grouping cue Messenger/Viber use.
  final bool tightTop;

  /// Last message of a run — only it gets the "tail" corner; a run's earlier
  /// bubbles stay square on that corner so the group reads as one shape.
  final bool roundedTail;

  bool get _isMine => note.authorRole == 'resident';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final avatar = _ThreadAvatar(note: note, incident: incident);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.68,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color:
            _isMine
                ? ZirenTokens.brandOrange.withValues(alpha: 0.14)
                : ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(ZirenTokens.radius16),
          topRight: const Radius.circular(ZirenTokens.radius16),
          bottomLeft: Radius.circular(
            _isMine || !roundedTail ? ZirenTokens.radius16 : 4,
          ),
          bottomRight: Radius.circular(
            !_isMine || !roundedTail ? ZirenTokens.radius16 : 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            note.body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _clock(note.createdAt),
            style: TextStyle(fontSize: 10, color: ZirenTokens.textMuted),
          ),
        ],
      ),
    );

    final bubbleColumn = Column(
      crossAxisAlignment:
          _isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(
              bottom: 3,
              left: ZirenTokens.space4,
              right: ZirenTokens.space4,
            ),
            child: Text(
              note.authorLabel(t),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textMuted,
              ),
            ),
          ),
        bubble,
      ],
    );

    // 30px avatar + its gap, reserved even when this bubble is not a run's
    // first — otherwise a grouped message would drift under the other
    // side's margin instead of staying under its own avatar's column.
    const avatarSlot = SizedBox(width: 30, height: 30);

    return Padding(
      padding: EdgeInsets.only(top: tightTop ? 2 : ZirenTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            _isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!_isMine) ...[
            showAvatar ? avatar : avatarSlot,
            const SizedBox(width: ZirenTokens.space8),
          ],
          Flexible(child: bubbleColumn),
          if (_isMine) ...[
            const SizedBox(width: ZirenTokens.space8),
            showAvatar ? avatar : avatarSlot,
          ],
        ],
      ),
    );
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// The "profile pic" side of the messenger feel — Ziren has no photo upload
/// for chat, so each side gets a consistent generated badge instead: the
/// resident's own initials on brand orange, and the agency's initials on
/// that agency's fixed hue (BFP red-coral / PNP sky-blue / MDRRMO emerald —
/// see ZirenTokens), so the colour itself says who is answering before the
/// text is even read.
class _ThreadAvatar extends StatelessWidget {
  const _ThreadAvatar({required this.note, required this.incident});

  final IncidentNote note;
  final IncidentModel incident;

  bool get _isMine => note.authorRole == 'resident';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
      child:
          _isMine
              ? Text(
                _initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              )
              : Icon(_agencyIcon, size: 15, color: Colors.white),
    );
  }

  Color get _bg {
    if (_isMine) return ZirenTokens.brandOrange;
    switch (incident.respondingAgency) {
      case 'BFP':
        return ZirenTokens.agencyBFP;
      case 'PNP':
        return ZirenTokens.agencyPNP;
      case 'MDRRMO':
        return ZirenTokens.agencyMDRRMO;
      default:
        // No agency assigned yet (report still pending) — neutral, not one
        // of the three fixed agency hues, so it never implies a dispatch
        // decision that has not actually happened.
        return ZirenTokens.statusProcessing;
    }
  }

  IconData get _agencyIcon {
    switch (note.authorRole) {
      case 'provincial_admin':
        return LucideIcons.landmark;
      case 'responder':
        return LucideIcons.siren;
      default:
        return LucideIcons.shield_check;
    }
  }

  String get _initials {
    final name = note.authorName?.trim();
    if (name == null || name.isEmpty) return 'R';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? 'R' : letters;
  }
}
