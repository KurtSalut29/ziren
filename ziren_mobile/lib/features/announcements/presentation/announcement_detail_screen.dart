import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/announcement_repository.dart';
import '../domain/announcement_model.dart';
import 'alert_response_panel.dart';
import 'announcement_style.dart';
import 'announcement_tile.dart';

/// One announcement, whole: what it is, what to do, where to go, where it
/// applies - and, on a safety alert that asked, "Are you safe?" right under
/// the headline, before the message. That order is deliberate: someone who
/// opens an evacuation order from a notification in the middle of the night
/// should be able to answer without scrolling.
///
/// Opened by id (a notification, the Home card, the list), so it reads the
/// announcement fresh - including after it ended, when it says so.
class AnnouncementDetailScreen extends StatefulWidget {
  const AnnouncementDetailScreen({super.key, required this.id, this.repository, this.positionReader});

  final String id;
  final AnnouncementRepository? repository;
  final PositionReader? positionReader;

  @override
  State<AnnouncementDetailScreen> createState() => _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  late final AnnouncementRepository _repo = widget.repository ?? AnnouncementRepository();
  AnnouncementModel? _item;
  bool _loading = true;
  bool _missing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await _repo.getAnnouncement(widget.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _missing = item == null;
        _loading = false;
      });
    } on Failure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final item = _item;
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(item?.categoryLabel(t) ?? t.announcementsTitle)),
      body: _loading && item == null
          ? const Center(child: CircularProgressIndicator(color: ZirenTokens.brandOrange))
          : _missing
          ? _Message(icon: LucideIcons.megaphone_off, title: t.annNotFoundTitle, body: t.annNotFoundBody)
          : item == null
          ? _Message(
              icon: LucideIcons.cloud_off,
              title: t.announcementsLoadError,
              body: _error ?? '',
              action: OutlinedButton(onPressed: _load, child: Text(t.announcementsRetry)),
            )
          : RefreshIndicator(
              color: ZirenTokens.brandOrange,
              onRefresh: _load,
              child: _body(t, item),
            ),
    );
  }

  Widget _body(AppLocalizations t, AnnouncementModel a) {
    final (icon, color) = announcementStyle(a.category);
    final chips = announcementChips(t, a);
    final facts = announcementFacts(t, a);
    final ended = !a.isActive || !a.isOpen;
    final meta = [
      if (a.issuer != null) t.annIssuedBy(a.issuer!),
      timeAgoShort(t, a.createdAt),
    ].join(' · ');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: ZirenTokens.space32),
      children: [
        // ── Headline ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space20,
            ZirenTokens.space20,
            ZirenTokens.space20,
            ZirenTokens.space20,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.25))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: ZirenTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.categoryLabel(t).toUpperCase(),
                          style: TextStyle(fontSize: 12, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: color),
                        ),
                        Text(meta, style: TextStyle(fontSize: 12, color: ZirenTokens.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space12),
              Text(
                a.title,
                key: const Key('announcement-title'),
                style: TextStyle(fontSize: 21, height: 1.25, fontWeight: FontWeight.w800, color: ZirenTokens.textPrimary),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: ZirenTokens.space10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final c in chips) AnnouncementChip(label: c.label, color: c.color)],
                ),
              ],
              if (a.category == 'all_clear' && a.detail('ends_title') != null) ...[
                const SizedBox(height: ZirenTokens.space8),
                Text(t.annEndsTitle(a.detail('ends_title')!), style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary)),
              ],
            ],
          ),
        ),

        // ── It has ended ─────────────────────────────────────────
        if (ended)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space16, ZirenTokens.space16, 0),
            child: Container(
              key: const Key('announcement-ended'),
              padding: const EdgeInsets.all(ZirenTokens.space12),
              decoration: BoxDecoration(
                color: ZirenTokens.systemSuccess.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                border: Border.all(color: ZirenTokens.systemSuccess.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.shield_check, size: 18, color: ZirenTokens.systemSuccess),
                  const SizedBox(width: ZirenTokens.space10),
                  Expanded(
                    child: Text(
                      a.endedByTitle != null ? '${t.annEnded}. ${t.annEndedBy(a.endedByTitle!)}' : t.annEnded,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ZirenTokens.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Are you safe? ────────────────────────────────────────
        if (canAnswerAlerts(context) && (a.canAnswer || a.myResponse != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space16, ZirenTokens.space16, 0),
            child: AlertResponsePanel(
              announcement: a,
              repository: _repo,
              positionReader: widget.positionReader,
              onAnswered: (r) => setState(() => _item = a.withResponse(r)),
            ),
          ),

        // ── The message ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(ZirenTokens.space20, ZirenTokens.space20, ZirenTokens.space20, 0),
          child: Text(
            a.body,
            style: TextStyle(fontSize: 15, height: 1.55, color: ZirenTokens.textPrimary),
          ),
        ),

        // ── Facts: where to go, which road, who is missing ───────
        if (facts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space16, ZirenTokens.space16, 0),
            child: Container(
              key: const Key('announcement-facts'),
              padding: const EdgeInsets.all(ZirenTokens.space16),
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                border: Border.all(color: ZirenTokens.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) const SizedBox(height: ZirenTokens.space10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          facts[i].label == t.annGoTo ? LucideIcons.door_open : LucideIcons.dot,
                          size: 18,
                          color: facts[i].label == t.annGoTo ? color : ZirenTokens.textMuted,
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(facts[i].label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ZirenTokens.textMuted)),
                              Text(facts[i].value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: ZirenTokens.textPrimary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

        // ── Where, and until when ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(ZirenTokens.space20, ZirenTokens.space16, ZirenTokens.space20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(icon: LucideIcons.map_pin, text: a.placeLine(t)),
              if (a.expiresAt != null) ...[
                const SizedBox(height: 6),
                _Line(icon: LucideIcons.calendar_clock, text: t.annUntil(_dateTime(t, a.expiresAt!))),
              ],
            ],
          ),
        ),

        // ── The hotlines, always ─────────────────────────────────
        if (a.isSafety)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space20, ZirenTokens.space16, 0),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/hotlines'),
              icon: const Icon(LucideIcons.phone, size: 18),
              label: Text(t.accountOpenHotlines),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZirenTokens.radius12)),
              ),
            ),
          ),
      ],
    );
  }

  static String _dateTime(AppLocalizations t, DateTime when) {
    try {
      return DateFormat.MMMd(t.localeName).add_jm().format(when);
    } catch (_) {
      return DateFormat.MMMd().add_jm().format(when);
    }
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: ZirenTokens.textMuted),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary))),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZirenTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: ZirenTokens.textMuted),
            const SizedBox(height: ZirenTokens.space12),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ZirenTokens.textPrimary)),
            const SizedBox(height: ZirenTokens.space6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary)),
            if (action != null) ...[const SizedBox(height: ZirenTokens.space16), action!],
          ],
        ),
      ),
    );
  }
}
