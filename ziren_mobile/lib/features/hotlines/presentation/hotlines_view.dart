import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../incident_report/domain/incident_provider.dart';
import '../../incident_report/presentation/incident_labels.dart';
import '../data/hotlines_store.dart';
import '../domain/station_hotlines.dart';

/// Opens the phone's dialer on [number]. Never places the call by itself:
/// the resident still presses the dialer's call button, so a mis-tap here
/// costs nothing.
Future<void> callHotline(BuildContext context, HotlineNumber number) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(number.telUri);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(content: Text(t.hotlinesCallFailed(number.display))),
    );
  }
}

Color _agencyColor(String type) => switch (type) {
      'BFP' => ZirenTokens.agencyBFP,
      'PNP' => ZirenTokens.agencyPNP,
      'MDRRMO' => ZirenTokens.agencyMDRRMO,
      _ => ZirenTokens.systemInfo,
    };

IconData _agencyIcon(String type) => switch (type) {
      'BFP' => LucideIcons.flame,
      'PNP' => LucideIcons.shield,
      'MDRRMO' => LucideIcons.shield_plus,
      _ => LucideIcons.hospital,
    };

/// The station hotlines for one kind of emergency, as a bottom sheet.
///
/// Opened by Home when there is no internet and a category is tapped (the
/// report could not be sent, so the next best thing is shown at once), and
/// by the report screens when a send fails. [offline] adds the "no internet"
/// explanation at the top.
Future<void> showHotlinesSheet(
  BuildContext context, {
  IncidentCategory? category,
  bool offline = false,
}) {
  HotlinesStore.instance.refresh();
  // Nullable lookup: the sheet must open even where no report is in
  // progress (and in previews); without a fix the towns are just listed A–Z.
  final pos = Provider.of<IncidentProvider?>(context, listen: false)?.currentPosition;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZirenTokens.surfaceOverlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZirenTokens.radius24)),
    ),
    builder: (sheetContext) {
      final t = AppLocalizations.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => ListenableBuilder(
          listenable: HotlinesStore.instance,
          builder: (context, _) {
            final entries = StationHotlines.forCategory(
              HotlinesStore.instance.entries,
              category,
              lat: pos?.latitude,
              lng: pos?.longitude,
            );
            // Only with a fix: without one the towns are merely A–Z, and
            // calling the first one "nearest" would send a caller the wrong way.
            final nearestTown = pos == null || entries.isEmpty ? null : entries.first.municipality;
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space20,
                ZirenTokens.space12,
                ZirenTokens.space20,
                ZirenTokens.space24,
              ),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZirenTokens.surfaceBorder,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                    ),
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),
                if (offline) ...[
                  _OfflineNotice(t: t),
                  const SizedBox(height: ZirenTokens.space16),
                ],
                Text(
                  category == null
                      ? t.hotlinesTitle
                      : t.hotlinesForCategory(IncidentLabels.categoryShort(t, category)),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  t.hotlinesSheetSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.4, color: ZirenTokens.textSecondary),
                ),
                const SizedBox(height: ZirenTokens.space16),
                for (final h in entries) ...[
                  HotlineCard(entry: h, nearest: h.municipality == nearestTown),
                  const SizedBox(height: ZirenTokens.space10),
                ],
                const SizedBox(height: ZirenTokens.space6),
                const _NationalHotline(),
                const SizedBox(height: ZirenTokens.space12),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.list, size: 18),
                  label: Text(t.hotlinesSeeAll),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/hotlines');
                  },
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.t});

  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.systemWarning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.wifi_off, size: 20, color: ZirenTokens.systemWarning),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.hotlinesOfflineTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.hotlinesOfflineBody,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: ZirenTokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 911 — always last, always there: it reaches someone even where no station
/// number is known.
class _NationalHotline extends StatelessWidget {
  const _NationalHotline();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    const number = HotlineNumber('911');
    return HotlineCard(
      entry: StationHotline(
        municipality: t.hotlinesNationalScope,
        agencyType: 'RHU',
        name: t.hotlinesNational,
        numbers: const [number],
      ),
      icon: LucideIcons.phone_call,
    );
  }
}

/// One station: who it is, and a Call button per number.
class HotlineCard extends StatelessWidget {
  const HotlineCard({super.key, required this.entry, this.nearest = false, this.icon});

  final StationHotline entry;
  final bool nearest;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = _agencyColor(entry.agencyType);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color: nearest ? color.withValues(alpha: 0.55) : ZirenTokens.surfaceBorder,
          width: nearest ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon ?? _agencyIcon(entry.agencyType), size: 20, color: color),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    Text(
                      entry.agencyType == 'RHU' && entry.agencyId == null && icon == null
                          ? '${t.hotlinesRhu} · ${entry.municipality}'
                          : entry.municipality,
                      style: TextStyle(fontSize: 12.5, color: ZirenTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              if (nearest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  ),
                  child: Text(
                    t.hotlinesNearest,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          for (final n in entry.numbers) ...[
            _CallButton(number: n, color: color),
            if (n != entry.numbers.last) const SizedBox(height: ZirenTokens.space8),
          ],
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.number, required this.color});

  final HotlineNumber number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: t.hotlinesCallSemantics(number.display),
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          onTap: () => callHotline(context, number),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          number.display,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                        if (number.label != null)
                          Text(
                            number.label!,
                            style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: ZirenTokens.systemSuccess,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.phone, size: 15, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          t.hotlinesCallNow,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every station hotline in Biliran, filterable by agency, nearest town first.
class HotlinesScreen extends StatefulWidget {
  const HotlinesScreen({super.key});

  @override
  State<HotlinesScreen> createState() => _HotlinesScreenState();
}

class _HotlinesScreenState extends State<HotlinesScreen> {
  String? _type;

  @override
  void initState() {
    super.initState();
    HotlinesStore.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pos = Provider.of<IncidentProvider?>(context)?.currentPosition;
    final towns = StationHotlines.nearestTowns(lat: pos?.latitude, lng: pos?.longitude);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.hotlinesTitle)),
      body: ListenableBuilder(
        listenable: HotlinesStore.instance,
        builder: (context, _) {
          final all = HotlinesStore.instance.entries
              .where((h) => _type == null || h.agencyType == _type)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space12,
              ZirenTokens.space16,
              ZirenTokens.space24,
            ),
            children: [
              Text(
                t.hotlinesScreenIntro,
                style: TextStyle(fontSize: 13, height: 1.4, color: ZirenTokens.textSecondary),
              ),
              const SizedBox(height: ZirenTokens.space12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, value) in [
                    (t.hotlinesFilterAll, null),
                    ('BFP', 'BFP'),
                    ('PNP', 'PNP'),
                    ('MDRRMO', 'MDRRMO'),
                    ('RHU', 'RHU'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _type == value,
                      onSelected: (_) => setState(() => _type = value),
                    ),
                ],
              ),
              for (final town in towns)
                if (all.any((h) => h.municipality == town)) ...[
                  const SizedBox(height: ZirenTokens.space20),
                  Text(
                    town == towns.first && pos != null ? '$town · ${t.hotlinesNearest}' : town,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  for (final h in all.where((h) => h.municipality == town)) ...[
                    HotlineCard(entry: h),
                    const SizedBox(height: ZirenTokens.space10),
                  ],
                ],
              const SizedBox(height: ZirenTokens.space12),
              const _NationalHotline(),
              const SizedBox(height: ZirenTokens.space20),
              Text(
                t.contactsHospitalsSection,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const SizedBox(height: ZirenTokens.space8),
              // The whole card opens the map. go, not push: /map is a tab of
              // the shell, and pushing it builds a second shell over the first
              // (the white screen the old contacts page used to open).
              Material(
                color: ZirenTokens.surfaceCard,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  side: BorderSide(color: ZirenTokens.surfaceBorder),
                ),
                child: InkWell(
                  onTap: () => context.go('/map'),
                  child: Padding(
                    padding: const EdgeInsets.all(ZirenTokens.space16),
                    child: Row(
                      children: [
                        Icon(LucideIcons.hospital, size: 20, color: ZirenTokens.textMuted),
                        const SizedBox(width: ZirenTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.contactsFindOnMap,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: ZirenTokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.contactsFindOnMapBody,
                                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevron_right, size: 18, color: ZirenTokens.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
