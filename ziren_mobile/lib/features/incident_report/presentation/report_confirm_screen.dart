import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/incident_repository.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// "This is what we heard — did we get it right?"
///
/// Why this screen exists
/// ----------------------
/// No recogniser reads Waray well. Measured on real recordings from a real
/// handset: 51% word error rate, and the clip that came out nearly perfect
/// still lost the child left inside a burning house, because the transcript
/// said "batang" where the pattern expected "bata". Waiting for a model that
/// reads Waray correctly means waiting for something that does not exist.
///
/// The resident is standing at the scene. Asking them costs two seconds and is
/// the only certainty in the pipeline. Every correction is also labelled Waray
/// emergency speech — the exact data whose absence caused the problem.
///
/// The order matters
/// -----------------
/// The report is ALREADY SENT before this screen opens. It says so first,
/// plainly, above everything else. Someone whose house is on fire must never
/// be left unsure whether help was called because a screen is asking them to
/// proofread. Every path off this screen — confirm, correct, back out, give
/// up waiting — leaves a report that was already filed.
class ReportConfirmScreen extends StatefulWidget {
  const ReportConfirmScreen({
    super.key,
    required this.incidentId,
    this.stationName,
  });

  final String incidentId;
  final String? stationName;

  @override
  State<ReportConfirmScreen> createState() => _ReportConfirmScreenState();
}

class _ReportConfirmScreenState extends State<ReportConfirmScreen> {
  /// How long to wait for words before giving up gracefully.
  ///
  /// Transcription takes a few seconds on a laptop and longer on a loaded one.
  /// Past this the screen stops waiting and closes itself out honestly rather
  /// than spinning at someone in an emergency.
  static const _giveUpAfter = Duration(seconds: 40);
  static const _pollEvery = Duration(seconds: 3);

  final _repo = IncidentRepository();
  final _editCtrl = TextEditingController();

  Timer? _poll;
  Duration _waited = Duration.zero;
  String? _heard;
  bool _editing = false;
  bool _saving = false;
  bool _gaveUp = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(_pollEvery, (_) {
      _waited += _pollEvery;
      if (_waited >= _giveUpAfter) {
        _poll?.cancel();
        if (mounted) setState(() => _gaveUp = true);
        return;
      }
      _check();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final incident = await _repo.getIncident(widget.incidentId);
      final heard = incident.heardText;
      if (heard != null && mounted) {
        _poll?.cancel();
        setState(() {
          _heard = heard;
          _editCtrl.text = heard;
        });
      }
    } catch (_) {
      // Silent on purpose. A failed poll is not worth an error banner over a
      // report that is already filed; the give-up path covers the rest.
    }
  }

  Future<void> _send({String? corrected}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.confirmTranscript(
        widget.incidentId,
        correctedText: corrected,
      );
      if (mounted) _leave();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppLocalizations.of(context).voiceConfirmSaveError;
        });
      }
    }
  }

  void _leave() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopScope(
      // Backing out is allowed. The report is sent either way, and trapping
      // someone on a proofreading screen during an emergency would be worse
      // than an unconfirmed transcript.
      canPop: true,
      child: Scaffold(
        backgroundColor: ZirenTokens.surfaceBase,
        appBar: AppBar(
          title: Text(t.voiceConfirmAppBarTitle),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _saving ? null : _leave,
              child: Text(t.voiceConfirmSkip),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sentBanner(t),
                const SizedBox(height: ZirenTokens.space20),
                if (_heard == null) _waiting(t) else _understanding(t),
                if (_error != null) ...[
                  const SizedBox(height: ZirenTokens.space12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: ZirenTokens.severityCritical,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Said first and said plainly. Everything below this is optional.
  Widget _sentBanner(AppLocalizations t) {
    final where = widget.stationName;
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemSuccessBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circle_check_big,
            color: ZirenTokens.systemSuccess,
            size: 26,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.voiceConfirmSentTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  where == null
                      ? t.voiceConfirmSentBodyStation
                      : t.voiceConfirmSentBodyStationNamed(where),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waiting(AppLocalizations t) {
    if (_gaveUp) {
      return _card(
        title: t.voiceConfirmGaveUpTitle,
        body: t.voiceConfirmGaveUpBody,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ZirenTokens.brandOrange,
            ),
            onPressed: _leave,
            child: Text(t.voiceConfirmOk),
          ),
        ],
      );
    }
    return _card(
      title: t.voiceConfirmListeningTitle,
      body: t.voiceConfirmListeningBody,
      actions: const [
        SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ],
    );
  }

  Widget _understanding(AppLocalizations t) {
    if (_editing) {
      return _card(
        title: t.voiceConfirmEditTitle,
        body: null,
        child: TextField(
          controller: _editCtrl,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: ZirenTokens.surfaceCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => setState(() => _editing = false),
            child: Text(t.voiceConfirmBack),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ZirenTokens.brandOrange,
            ),
            onPressed:
                _saving ? null : () => _send(corrected: _editCtrl.text.trim()),
            child:
                _saving
                    ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : Text(t.voiceConfirmSave),
          ),
        ],
      );
    }

    return _card(
      title: t.voiceConfirmHeardTitle,
      body: null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ZirenTokens.space12),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        ),
        child: Text(
          '"$_heard"',
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            fontStyle: FontStyle.italic,
            color: ZirenTokens.textPrimary,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => setState(() => _editing = true),
          child: Text(t.voiceConfirmWrongFix),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ZirenTokens.systemSuccess,
          ),
          onPressed: _saving ? null : () => _send(),
          child:
              _saving
                  ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Text(t.voiceConfirmCorrect),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    String? body,
    Widget? child,
    required List<Widget> actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 12.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: ZirenTokens.space12),
            child,
          ],
          const SizedBox(height: ZirenTokens.space16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final a in actions) ...[
                a,
                const SizedBox(width: ZirenTokens.space8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
