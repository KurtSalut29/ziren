import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../incident_report/domain/incident_model.dart';
import '../../domain/responder_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Field Response Updates (Section 11) and Incident-Specific Communication
/// (Section 12) — the same thread the Agency Admin reads and writes on the
/// dashboard, now given a mobile screen for the first time. The backend
/// (`GET/POST /responder/queue/{id}/notes`) has been ready since migration
/// 030; this closes the "no mobile screen calls this yet" gap noted in its
/// header.
///
/// Inline, not a sheet: a crew mid-response keeps this screen open, and the
/// dashboard's own equivalent (IncidentNotesPanel) is inline for the same
/// reason — it is context the responder returns to, not a one-off action.
class ResponderNotesPanel extends StatefulWidget {
  const ResponderNotesPanel({super.key, required this.incidentId});

  final String incidentId;

  @override
  State<ResponderNotesPanel> createState() => _ResponderNotesPanelState();
}

class _ResponderNotesPanelState extends State<ResponderNotesPanel> {
  final _controller = TextEditingController();
  List<IncidentNote>? _notes;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await context.read<ResponderProvider>().fetchIncidentNotes(
        widget.incidentId,
      );
      if (mounted) setState(() => _notes = notes);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the thread.');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final provider = context.read<ResponderProvider>();
    final error = await provider.sendIncidentNote(widget.incidentId, text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error;
      });
      return;
    }
    _controller.clear();
    await _load();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.message_square,
                size: 16,
                color: ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(child: Text(
                'FIELD UPDATES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: ZirenTokens.textMuted,
                ),
              )),
            ],
          ),
          const SizedBox(height: ZirenTokens.space12),
          if (_notes == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: ZirenTokens.space12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_notes!.isEmpty)
            Text(
              'No updates yet. Add what you find as the response unfolds.',
              style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
            )
          else
            Column(
              children: [
                for (final n in _notes!) _NoteRow(note: n),
              ],
            ),
          const SizedBox(height: ZirenTokens.space12),
          if (_error != null) ...[
            Text(
              _error!,
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
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Fire has spread to the second floor.',
                    hintStyle: TextStyle(fontSize: 12.5),
                    isDense: true,
                    border: OutlineInputBorder(),
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
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(LucideIcons.send, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});
  final IncidentNote note;

  bool get _isMine => note.authorRole == 'responder';

  Color get _color => switch (note.authorRole) {
    'responder' => ZirenTokens.brandOrange,
    'agency_admin' => ZirenTokens.statusProcessing,
    'provincial_admin' => ZirenTokens.textSecondary,
    _ => ZirenTokens.textSecondary,
  };

  String get _label {
    if (note.authorName?.isNotEmpty == true) return note.authorName!;
    return switch (note.authorRole) {
      'responder' => _isMine ? 'You' : 'Responder',
      'agency_admin' => 'Agency Admin',
      'provincial_admin' => 'Provincial Admin',
      _ => note.authorRole,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space8),
      padding: const EdgeInsets.only(left: ZirenTokens.space10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: _color, width: 2.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(
                _label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              )),
              const SizedBox(width: ZirenTokens.space6),
              Flexible(child: Text(
                _clock(note.createdAt),
                style: TextStyle(
                  fontSize: 10.5,
                  color: ZirenTokens.textMuted,
                ),
              )),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            note.body,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
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
