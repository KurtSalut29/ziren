import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/announcement_repository.dart';
import '../domain/announcement_model.dart';
import 'announcement_tile.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../demo/presentation/demo_anchor.dart';

/// Official broadcasts from a Provincial Admin — spec Section 24.
///
/// Safety alerts for where the resident lives come first (an evacuation order,
/// a wind signal, a hazard warning - each opening to the "are you safe?"
/// answer), then everything else. There is still no compose action here on
/// purpose: residents receive, they do not publish.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.repository});

  final AnnouncementRepository? repository;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final AnnouncementRepository _repo =
      widget.repository ?? AnnouncementRepository();
  List<AnnouncementModel>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _repo.getAnnouncements();
      if (mounted) setState(() => _items = items);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NetworkFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).announcementsLoadError,
        );
      }
    }
  }

  Future<void> _open(AnnouncementModel a) async {
    await context.push('/announcements/${a.id}');
    // They may have answered on the detail screen.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.announcementsTitle)),
      body: DemoAnchor(
        id: 'ann.screen',
        child: RefreshIndicator(
          color: ZirenTokens.brandOrange,
          onRefresh: _load,
          child: _buildBody(t),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations t) {
    if (_error != null && _items == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(ZirenTokens.space32),
            child: Column(
              children: [
                Icon(
                  LucideIcons.cloud_off,
                  size: 40,
                  color: ZirenTokens.textMuted,
                ),
                const SizedBox(height: ZirenTokens.space12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZirenTokens.textSecondary),
                ),
                const SizedBox(height: ZirenTokens.space16),
                OutlinedButton(
                  onPressed: _load,
                  child: Text(t.announcementsRetry),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_items == null) {
      return const Center(
        child: CircularProgressIndicator(color: ZirenTokens.brandOrange),
      );
    }

    if (_items!.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(ZirenTokens.space32),
            child: Column(
              children: [
                const SizedBox(height: ZirenTokens.space32),
                Icon(
                  LucideIcons.megaphone,
                  size: 48,
                  color: ZirenTokens.surfaceBorder,
                ),
                const SizedBox(height: ZirenTokens.space12),
                Text(
                  t.announcementsEmptyTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  t.announcementsEmptyBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final safety =
        _items!.where((a) => a.isSafety).toList()
          // Unanswered questions first, then newest.
          ..sort((a, b) {
            final pa = a.canAnswer && a.myResponse == null ? 0 : 1;
            final pb = b.canAnswer && b.myResponse == null ? 0 : 1;
            return pa != pb ? pa - pb : b.createdAt.compareTo(a.createdAt);
          });
    final other = _items!.where((a) => !a.isSafety).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      children: [
        if (safety.isNotEmpty) ...[
          _Heading(icon: LucideIcons.triangle_alert, label: t.annSafetyAlerts),
          for (final a in safety) ...[
            DemoAnchor(
              id: a == safety.first ? 'ann.safety' : 'ann.safety.${a.id}',
              child: AnnouncementTile(item: a, onTap: () => _open(a)),
            ),
            const SizedBox(height: ZirenTokens.space10),
          ],
          const SizedBox(height: ZirenTokens.space8),
        ],
        if (other.isNotEmpty) ...[
          _Heading(icon: LucideIcons.megaphone, label: t.annUpdates),
          for (final a in other) ...[
            DemoAnchor(
              id: a == other.first ? 'ann.update' : 'ann.update.${a.id}',
              child: AnnouncementTile(item: a, onTap: () => _open(a)),
            ),
            const SizedBox(height: ZirenTokens.space10),
          ],
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: ZirenTokens.space8,
        top: ZirenTokens.space4,
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: ZirenTokens.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
