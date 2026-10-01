import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../auth/domain/auth_provider.dart';
import '../../incident_report/domain/incident_provider.dart';
import '../../incident_report/presentation/incident_labels.dart';
import '../data/hotlines_store.dart';
import '../domain/station_hotlines.dart';
import '../../demo/presentation/demo_anchor.dart';

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
  final pos =
      Provider.of<IncidentProvider?>(context, listen: false)?.currentPosition;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZirenTokens.surfaceOverlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZirenTokens.radius24),
      ),
    ),
    builder: (sheetContext) {
      final t = AppLocalizations.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder:
            (_, controller) => ListenableBuilder(
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
                final nearestTown =
                    pos == null || entries.isEmpty
                        ? null
                        : entries.first.municipality;
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
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius4,
                          ),
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
                          : t.hotlinesForCategory(
                            IncidentLabels.categoryShort(t, category),
                          ),
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
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space16),
                    for (final h in entries) ...[
                      HotlineCard(
                        entry: h,
                        nearest: h.municipality == nearestTown,
                      ),
                      const SizedBox(height: ZirenTokens.space10),
                    ],
                    const SizedBox(height: ZirenTokens.space6),
                    const _NationalHotline(),
                    const SizedBox(height: ZirenTokens.space12),
                    OutlinedButton.icon(
                      icon: const Icon(LucideIcons.list, size: 18),
                      label: Text(t.hotlinesSeeAll),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
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
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.wifi_off,
            size: 20,
            color: ZirenTokens.systemWarning,
          ),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
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
  const HotlineCard({
    super.key,
    required this.entry,
    this.nearest = false,
    this.icon,
  });

  final StationHotline entry;
  final bool nearest;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = _agencyColor(entry.agencyType);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: profileCardDecoration().copyWith(
        border: Border.all(
          color:
              nearest
                  ? color.withValues(alpha: 0.55)
                  : ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
          width: nearest ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: ZirenTokens.isDark ? 0.2 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon ?? _agencyIcon(entry.agencyType),
                  size: 20,
                  color: color,
                ),
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
                      entry.agencyType == 'RHU' &&
                              entry.agencyId == null &&
                              icon == null
                          ? '${t.hotlinesRhu} · ${entry.municipality}'
                          : entry.municipality,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (nearest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  ),
                  child: Text(
                    t.hotlinesNearest,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          for (final n in entry.numbers) ...[
            _CallButton(number: n, color: color),
            if (n != entry.numbers.last)
              const SizedBox(height: ZirenTokens.space8),
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
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space12,
                vertical: 8,
              ),
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
                            style: TextStyle(
                              fontSize: 11.5,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ZirenTokens.systemSuccess,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.phone,
                          size: 15,
                          color: Colors.white,
                        ),
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
///
/// 911 opens the list rather than closing it - it is the one number that
/// works anywhere, and in a panic it should not need scrolling to. Then the
/// agency filter, then each town under its own heading, the nearest one first
/// when there is a location fix.
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
    final towns = StationHotlines.nearestTowns(
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    // /map is the RESIDENT shell's tab. The router has no role guard, so a
    // responder sent there landed in the resident app; theirs is
    // /responder/map.
    final isResponder =
        Provider.of<AuthProvider?>(context, listen: false)?.userRole ==
        'responder';
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.hotlinesTitle),
      ),
      body: ListenableBuilder(
        listenable: HotlinesStore.instance,
        builder: (context, _) {
          final all =
              HotlinesStore.instance.entries
                  .where((h) => _type == null || h.agencyType == _type)
                  .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space4,
              ZirenTokens.space16,
              ZirenTokens.space32,
            ),
            children: [
              const DemoAnchor(id: 'hot.national', child: _NationalHotline()),
              const SizedBox(height: ZirenTokens.space16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space4,
                ),
                child: Text(
                  t.hotlinesScreenIntro,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: ZirenTokens.space12),
              DemoAnchor(
                id: 'hot.filters',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (label, value) in [
                        (t.hotlinesFilterAll, null),
                        ('BFP', 'BFP'),
                        ('PNP', 'PNP'),
                        ('MDRRMO', 'MDRRMO'),
                        ('RHU', 'RHU'),
                      ]) ...[
                        _FilterPill(
                          label: label,
                          icon:
                              value == null
                                  ? LucideIcons.list
                                  : _agencyIcon(value),
                          color:
                              value == null
                                  ? ZirenTokens.brandOrange
                                  : _agencyColor(value),
                          selected: _type == value,
                          onTap: () => setState(() => _type = value),
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                      ],
                    ],
                  ),
                ),
              ),
              for (final town in towns)
                if (all.any((h) => h.municipality == town)) ...[
                  const SizedBox(height: ZirenTokens.space20),
                  _TownHeading(
                    town: town,
                    nearest: town == towns.first && pos != null,
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  for (final h in all.where((h) => h.municipality == town)) ...[
                    DemoAnchor(
                      id:
                          town == towns.first &&
                                  h ==
                                      all.firstWhere(
                                        (x) => x.municipality == town,
                                      )
                              ? 'hot.first'
                              : 'hot.${identityHashCode(h)}',
                      child: HotlineCard(entry: h),
                    ),
                    const SizedBox(height: ZirenTokens.space10),
                  ],
                ],
              const SizedBox(height: ZirenTokens.space16),
              ProfileGroup(
                title: t.contactsHospitalsSection,
                children: [
                  // go, not push: the map is a tab of the shell, and pushing it
                  // builds a second shell over the first.
                  ProfileTile(
                    icon: LucideIcons.hospital,
                    tone: ZirenTokens.systemInfo,
                    label: t.contactsFindOnMap,
                    value: t.contactsFindOnMapBody,
                    onTap:
                        () =>
                            context.go(isResponder ? '/responder/map' : '/map'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TownHeading extends StatelessWidget {
  const _TownHeading({required this.town, required this.nearest});

  final String town;
  final bool nearest;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: ZirenTokens.space4),
      child: Row(
        children: [
          Icon(LucideIcons.map_pin, size: 14, color: ZirenTokens.textSecondary),
          const SizedBox(width: ZirenTokens.space6),
          Text(
            town.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: ZirenTokens.textSecondary,
            ),
          ),
          if (nearest) ...[
            const SizedBox(width: ZirenTokens.space8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: ZirenTokens.systemSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ZirenTokens.radius32),
              ),
              child: Text(
                t.hotlinesNearest,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ZirenTokens.systemSuccess,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One agency filter: a pill with the agency's own icon and hue.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color : ZirenTokens.surfaceCard,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? color : ZirenTokens.surfaceBorder),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: selected ? Colors.white : color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : ZirenTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
