import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../domain/incident_provider.dart';
import '../domain/station_model.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class StationSelectorScreen extends StatefulWidget {
  const StationSelectorScreen({super.key});

  @override
  State<StationSelectorScreen> createState() => _StationSelectorScreenState();
}

class _StationSelectorScreenState extends State<StationSelectorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<IncidentProvider>();
      if (provider.stations.isEmpty) provider.loadStations();
    });
  }

  void _handleBack() {
    // canPop() is false when this is the root of a branch —
    // in that case go back to /home explicitly.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevron_left, size: 20),
          onPressed: _handleBack,
        ),
        title: Text(
          t.stationPickTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: ZirenTokens.surfaceBorder),
        ),
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(IncidentProvider provider) {
    final t = AppLocalizations.of(context);
    if (provider.loadingStations) return const LoadingIndicator();

    if (provider.stationsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.cloud_off,
                size: 52,
                color: ZirenTokens.textMuted,
              ),
              const SizedBox(height: ZirenTokens.space16),
              Text(
                provider.stationsError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ZirenTokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: ZirenTokens.space20),
              FilledButton.icon(
                onPressed: () => provider.loadStations(),
                icon: const Icon(LucideIcons.refresh_cw, size: 18),
                label: Text(t.actionTryAgainStation),
                style: FilledButton.styleFrom(
                  backgroundColor: ZirenTokens.brandOrange,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.stations.isEmpty) {
      return Center(
        child: Text(
          t.stationNoneAvailable,
          style: TextStyle(color: ZirenTokens.textMuted),
        ),
      );
    }

    final grouped = provider.stationsByAgencyType;
    const agencyOrder = ['BFP', 'PNP', 'MDRRMO'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Instruction strip ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            0,
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.pointer,
                size: 15,
                color: ZirenTokens.brandOrange,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Expanded(
                child: Text(
                  t.stationPickHelp,
                  style: TextStyle(
                    fontSize: 13,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: ZirenTokens.space12),

        // ── Station list ────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              0,
              ZirenTokens.space16,
              ZirenTokens.space32,
            ),
            children: [
              for (final agencyType in agencyOrder)
                if (grouped.containsKey(agencyType)) ...[
                  _AgencySection(
                    agencyType: agencyType,
                    stations: grouped[agencyType]!,
                    selectedId: provider.selectedStation?.id,
                    onSelect: (station) {
                      provider.selectStation(station);
                      provider.checkCoverage();
                      context.push('/report/category');
                    },
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Agency section — header + station rows ─────────────────────

class _AgencySection extends StatelessWidget {
  const _AgencySection({
    required this.agencyType,
    required this.stations,
    required this.selectedId,
    required this.onSelect,
  });

  final String agencyType;
  final List<StationModel> stations;
  final String? selectedId;
  final void Function(StationModel) onSelect;

  Color get _color {
    switch (agencyType) {
      case 'BFP':
        return ZirenTokens.agencyBFP;
      case 'PNP':
        return ZirenTokens.agencyPNP;
      case 'MDRRMO':
        return ZirenTokens.agencyMDRRMO;
      default:
        return ZirenTokens.brandOrange;
    }
  }

  Color get _bg {
    switch (agencyType) {
      case 'BFP':
        return ZirenTokens.agencyBFPBg;
      case 'PNP':
        return ZirenTokens.agencyPNPBg;
      case 'MDRRMO':
        return ZirenTokens.agencyMDRRMOBg;
      default:
        return ZirenTokens.brandSubtle;
    }
  }

  IconData get _icon {
    switch (agencyType) {
      case 'BFP':
        return LucideIcons.flame;
      case 'PNP':
        return LucideIcons.shield;
      case 'MDRRMO':
        return LucideIcons.triangle_alert;
      default:
        return LucideIcons.building;
    }
  }

  String get _label {
    switch (agencyType) {
      case 'BFP':
        return 'Bureau of Fire Protection';
      case 'PNP':
        return 'Philippine National Police';
      case 'MDRRMO':
        return 'Disaster Risk Reduction';
      default:
        return agencyType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Agency header pill
        Container(
          margin: const EdgeInsets.only(bottom: ZirenTokens.space8),
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space12,
            vertical: ZirenTokens.space8,
          ),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, size: 17, color: _color),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Flexible(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agencyType,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _color,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _label,
                    style: TextStyle(
                      fontSize: 11,
                      color: _color.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              )),
            ],
          ),
        ),

        // Station rows — clean list, no card borders
        ...stations.map(
          (s) => _StationRow(
            station: s,
            isSelected: selectedId == s.id,
            accentColor: _color,
            onTap: () => onSelect(s),
          ),
        ),

        const SizedBox(height: ZirenTokens.space16),
      ],
    );
  }
}

// ── Station row ────────────────────────────────────────────────

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final StationModel station;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ZirenTokens.motionQuick,
        margin: const EdgeInsets.only(bottom: ZirenTokens.space6),
        padding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: ZirenTokens.space12,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? accentColor.withValues(alpha: 0.06)
                  : ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          border: Border.all(
            color:
                isSelected
                    ? accentColor.withValues(alpha: 0.40)
                    : ZirenTokens.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Selection indicator dot
            AnimatedContainer(
              duration: ZirenTokens.motionQuick,
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: ZirenTokens.space12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : ZirenTokens.surfaceBorder,
                border:
                    isSelected
                        ? null
                        : Border.all(color: ZirenTokens.textDisabled),
              ),
            ),

            // Station info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? accentColor : ZirenTokens.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space2),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.map_pin,
                        size: 12,
                        color: ZirenTokens.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        station.municipality,
                        style: TextStyle(
                          fontSize: 12,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                      if (station.address != null) ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 12,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            station.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: ZirenTokens.space8),
            Icon(
              isSelected
                  ? LucideIcons.circle_check_big
                  : LucideIcons.chevron_right,
              size: 20,
              color: isSelected ? accentColor : ZirenTokens.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
