import 'package:flutter/material.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/announcement_repository.dart';
import '../domain/announcement_model.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Official broadcasts from Super Admin — spec Section 24.
///
/// A resident's read-only view of a role Super Admin publishes and this app
/// only ever receives; there is no compose action here on purpose.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _repo = AnnouncementRepository();
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
        setState(() => _error = AppLocalizations.of(context).announcementsLoadError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.announcementsTitle)),
      body: RefreshIndicator(
        color: ZirenTokens.brandOrange,
        onRefresh: _load,
        child: _buildBody(t),
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

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      itemCount: _items!.length,
      separatorBuilder: (_, __) => const SizedBox(height: ZirenTokens.space10),
      itemBuilder: (_, i) => _AnnouncementCard(item: _items![i]),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item});
  final AnnouncementModel item;

  (Color, IconData) get _style => switch (item.category) {
    'emergency' => (ZirenTokens.severityCritical, LucideIcons.triangle_alert),
    'service_interruption' => (
      ZirenTokens.systemWarning,
      LucideIcons.wifi_off,
    ),
    'maintenance' => (ZirenTokens.statusProcessing, LucideIcons.wrench),
    'feature' => (ZirenTokens.agencyMDRRMO, LucideIcons.sparkles),
    'reminder' => (ZirenTokens.textSecondary, LucideIcons.bell),
    _ => (ZirenTokens.brandOrange, LucideIcons.megaphone),
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (color, icon) = _style;
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space10,
                  vertical: ZirenTokens.space4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: color),
                    const SizedBox(width: 4),
                    Text(
                      item.categoryLabel(t),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _timeAgo(item.createdAt, t),
                style: TextStyle(
                  fontSize: 11,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.body,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt, AppLocalizations t) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return t.timeAgoJustNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
