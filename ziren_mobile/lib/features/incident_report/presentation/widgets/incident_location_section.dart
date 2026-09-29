import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/incident_provider.dart';

/// WHERE, for every report screen: where the incident is, and the landmark a
/// crew can find it by.
///
///  * "I am here" (the default) — the phone's GPS, as before.
///  * "Somewhere else" — the resident places the incident on the map. The
///    report then carries that point as the incident location and the phone's
///    position separately, so a crew is not sent to the reporter.
///
/// The landmark is required (the stations asked for it: GPS inside a
/// barangay is not an address a driver can find). It is filled in for the
/// resident from the map data bundled in the app — the named landmark nearest
/// the incident — and they can correct it.
class IncidentLocationSection extends StatefulWidget {
  const IncidentLocationSection({
    super.key,
    required this.landmarkController,
    this.showLandmarkError = false,
    this.onLandmarkChanged,
    this.header,
  });

  final TextEditingController landmarkController;

  /// The screen tried to continue with no landmark.
  final bool showLandmarkError;
  final ValueChanged<String>? onLandmarkChanged;

  /// Section label style of the host screen (quick report and wizard differ).
  final Widget Function(String text)? header;

  @override
  State<IncidentLocationSection> createState() => _IncidentLocationSectionState();
}

class _IncidentLocationSectionState extends State<IncidentLocationSection> {
  /// The exact text last auto-filled. The field is refilled only while it
  /// still holds that text — the moment the resident types, it is theirs.
  String? _autoFilled;

  void _maybeAutoFill(String? suggestion) {
    if (suggestion == null) return;
    final current = widget.landmarkController.text.trim();
    final untouched = current.isEmpty || current == _autoFilled;
    if (!untouched || current == suggestion) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = widget.landmarkController.text.trim();
      if (now.isNotEmpty && now != _autoFilled) return;
      setState(() {
        widget.landmarkController.text = suggestion;
        _autoFilled = suggestion;
      });
      widget.onLandmarkChanged?.call(suggestion);
    });
  }

  Future<void> _pickOnMap(IncidentProvider p) async {
    final picked = await context.push<LatLng>('/report/pick-location');
    if (picked != null) await p.setIncidentPoint(picked.latitude, picked.longitude);
  }

  Widget _label(String text) =>
      widget.header?.call(text) ??
      Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ZirenTokens.textPrimary),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<IncidentProvider>();
    final elsewhere = p.reportingElsewhere;
    final locating = p.currentPosition == null && !p.locationDenied;

    _maybeAutoFill(p.suggestedLandmark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(t.locWhereTitle),
        const SizedBox(height: ZirenTokens.space8),
        Row(
          children: [
            Expanded(
              child: _ChoicePill(
                icon: LucideIcons.locate_fixed,
                label: t.locHere,
                selected: !elsewhere,
                onTap: () {
                  p.clearIncidentPoint();
                },
              ),
            ),
            const SizedBox(width: ZirenTokens.space8),
            Expanded(
              child: _ChoicePill(
                icon: LucideIcons.map,
                label: t.locElsewhere,
                selected: elsewhere,
                onTap: () => _pickOnMap(p),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space10),
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                elsewhere ? LucideIcons.map_pinned : LucideIcons.map_pin,
                size: 18,
                color: ZirenTokens.brandOrange,
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      elsewhere
                          ? (p.incidentAddress ?? t.locPickedPoint)
                          : p.locationDenied
                              ? t.quickLocationOff
                              : locating
                                  ? t.quickSearching
                                  : (p.locationAddress ?? t.quickCoordinatesFound),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ZirenTokens.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (elsewhere)
                      Text(
                        p.locationAddress == null
                            ? t.locElsewhereNote
                            : t.locElsewhereNoteFrom(p.locationAddress!),
                        style: TextStyle(fontSize: 12, height: 1.35, color: ZirenTokens.textSecondary),
                      )
                    else if (!locating && !p.locationDenied && p.locationAccuracyM != null)
                      Text(
                        t.quickAccuracy(p.locationAccuracyM!.round()),
                        style: TextStyle(
                          fontSize: 12,
                          color: p.locationIsPrecise ? ZirenTokens.textMuted : ZirenTokens.systemWarning,
                        ),
                      ),
                  ],
                ),
              ),
              if (elsewhere)
                TextButton(onPressed: () => _pickOnMap(p), child: Text(t.locChange))
              else if (locating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!p.locationDenied)
                IconButton(
                  tooltip: t.locRefresh,
                  onPressed: () => p.fetchLocation(),
                  icon: Icon(LucideIcons.refresh_cw, size: 20, color: ZirenTokens.textMuted),
                ),
            ],
          ),
        ),
        if (!elsewhere && p.locationDenied) ...[
          const SizedBox(height: ZirenTokens.space6),
          Text(
            t.locDeniedPickHint,
            style: TextStyle(fontSize: 12, color: ZirenTokens.textSecondary),
          ),
        ],
        const SizedBox(height: ZirenTokens.space20),

        // ── Landmark (required) ──────────────────────────────
        _label(t.locLandmarkRequired),
        const SizedBox(height: ZirenTokens.space8),
        TextField(
          controller: widget.landmarkController,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 300,
          onChanged: (v) {
            setState(() {});
            widget.onLandmarkChanged?.call(v);
          },
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: t.quickLandmarkHint,
            counterText: '',
            prefixIcon: const Icon(LucideIcons.landmark, size: 20),
            errorText: widget.showLandmarkError && widget.landmarkController.text.trim().isEmpty
                ? t.locLandmarkMissing
                : null,
          ),
        ),
        if (_autoFilled != null && widget.landmarkController.text.trim() == _autoFilled)
          Padding(
            padding: const EdgeInsets.only(top: ZirenTokens.space6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.sparkles, size: 13, color: ZirenTokens.textMuted),
                const SizedBox(width: ZirenTokens.space6),
                Expanded(
                  child: Text(
                    t.locLandmarkAutoFilled,
                    style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ZirenTokens.brandOrange : ZirenTokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? ZirenTokens.brandOrange.withValues(alpha: 0.10) : ZirenTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          side: BorderSide(
            color: selected ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
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

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: child,
    );
  }
}
