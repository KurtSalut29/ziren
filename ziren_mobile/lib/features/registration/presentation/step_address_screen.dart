import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../auth/data/barangay_repository.dart';
import '../domain/address_resolver.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 3 — where the person lives.
///
/// This is the step that decides which station is dispatched, so the
/// municipality and barangay come from the reference table rather than free
/// text. Purok and street are free text on purpose: nobody maintains an
/// authoritative list of those, and a crew still needs them to find the door.
class StepAddressScreen extends StatefulWidget {
  const StepAddressScreen({super.key});

  @override
  State<StepAddressScreen> createState() => _StepAddressScreenState();
}

class _StepAddressScreenState extends State<StepAddressScreen> {
  final _repo = BarangayRepository();
  late Future<List<Barangay>> _future;

  late final TextEditingController _purok;
  late final TextEditingController _street;

  bool _locating = false;
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
    final d = context.read<RegistrationDraft>();
    _purok = TextEditingController(text: d.purokSitio);
    _street = TextEditingController(text: d.streetAddress);
  }

  @override
  void dispose() {
    _purok.dispose();
    _street.dispose();
    super.dispose();
  }

  /// Prefill the municipality AND the barangay from GPS.
  ///
  /// It used to fill in the municipality only, on the worry that a coordinate
  /// near a boundary could land on the wrong barangay and a plausible wrong
  /// answer already filled in is one nobody re-reads. Residents testing it
  /// wanted the barangay found as well, so it is - but the worry is kept, not
  /// dropped: the barangay is only ever a row of the reference list, in the
  /// municipality that was found; a barangay that is not certain is worded as
  /// "closest" and asks to be confirmed; and both dropdowns stay editable.
  /// See [AddressResolver] for how each is decided.
  Future<void> _useMyLocation(RegistrationDraft d) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _locating = true;
      _locationNote = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationNote = t.regLocationDenied);
        return;
      }

      // High accuracy: a barangay is a few kilometres across, and a cell-tower
      // fix can be further out than that. If a fix cannot be had in time, the
      // phone's last known one is still better than giving up.
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) rethrow;
        pos = last;
      }

      final reference = await _future;
      final osm = await _reverseGeocode(pos.latitude, pos.longitude);
      final found = AddressResolver.resolve(
        lat: pos.latitude,
        lon: pos.longitude,
        reference: reference,
        osmAddress: osm,
      );
      if (!mounted) return;

      final municipality = found.municipality;
      if (municipality == null) {
        setState(() => _locationNote = t.regNotInBiliran);
        return;
      }

      d.municipality = municipality;
      final barangay = found.barangay;
      d.barangayId = barangay?.id;
      d.barangayName = barangay?.name;
      d.commit();
      setState(() {
        _locationNote =
            barangay == null
                ? t.regLocationMunicipalityOnly(municipality)
                : found.barangayIsConfident
                ? t.regLocationBarangaySet(barangay.name, municipality)
                : t.regLocationBarangayNear(barangay.name, municipality);
      });
    } catch (_) {
      if (mounted) setState(() => _locationNote = t.regLocationFailed);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// OpenStreetMap's reading of a position, or null when it cannot be had.
  ///
  /// Best-effort by design: it sharpens the answer where OpenStreetMap knows the
  /// barangay, and the resolver works without it (the on-device place table)
  /// when the phone is offline, the service is slow, or Biliran is thinly mapped
  /// at that spot.
  Future<Map<String, dynamic>?> _reverseGeocode(double lat, double lon) async {
    try {
      final response = await http
          .get(
            Uri.https('nominatim.openstreetmap.org', '/reverse', {
              'lat': lat.toString(),
              'lon': lon.toString(),
              'format': 'json',
              'addressdetails': '1',
              'zoom': '16',
              'accept-language': 'en',
            }),
            headers: const {'User-Agent': 'ZirenEmergencyApp/1.0'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic>
          ? body['address'] as Map<String, dynamic>?
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final complete = d.municipality != null && d.barangayId != null;

    return RegistrationScaffold(
      step: RegStep.address,
      title: t.regAddressTitle,
      subtitle: t.regAddressSubtitle,
      onContinue:
          complete
              ? () {
                d.purokSitio = _purok.text.trim();
                d.streetAddress = _street.text.trim();
                d.commit();
                context.go(d.next(RegStep.address)!.path);
              }
              : null,
      child: FutureBuilder<List<Barangay>>(
        future: _future,
        builder: (context, snapshot) {
          final t = AppLocalizations.of(context);
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: ZirenTokens.space32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _ReferenceDataError(
              onRetry:
                  () =>
                      setState(() => _future = BarangayRepository().fetchAll()),
            );
          }

          final all = snapshot.data!;
          final municipalities =
              all.map((b) => b.municipality).toSet().toList();
          final inMunicipality =
              all.where((b) => b.municipality == d.municipality).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _locating ? null : () => _useMyLocation(d),
                icon:
                    _locating
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(LucideIcons.locate_fixed, size: 18),
                label: Text(_locating ? t.regFindingYou : t.regUseMyLocation),
              ),
              if (_locationNote != null) ...[
                const SizedBox(height: ZirenTokens.space8),
                Text(
                  _locationNote!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              ],

              const SizedBox(height: ZirenTokens.space24),

              RegField(
                label: t.fieldMunicipality,
                child: _Dropdown(
                  value: d.municipality,
                  hint: t.hintMunicipality,
                  icon: LucideIcons.landmark,
                  items: [
                    for (final m in municipalities)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) {
                    d.municipality = v;
                    // The old barangay belongs to the old municipality.
                    d.barangayId = null;
                    d.barangayName = null;
                    d.commit();
                  },
                ),
              ),
              const SizedBox(height: ZirenTokens.space20),
              RegField(
                label: t.fieldBarangay,
                child: _Dropdown(
                  value: d.barangayId,
                  hint:
                      d.municipality == null
                          ? t.regChooseMunicipalityFirst
                          : t.hintBarangay,
                  icon: LucideIcons.house,
                  enabled: d.municipality != null,
                  items: [
                    for (final b in inMunicipality)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) {
                    d.barangayId = v;
                    d.barangayName =
                        inMunicipality
                            .where((b) => b.id == v)
                            .firstOrNull
                            ?.name;
                    d.commit();
                  },
                ),
              ),

              const SizedBox(height: ZirenTokens.space20),
              RegField(
                label: t.fieldPurok,
                optional: true,
                child: ZirenTextField(
                  label: '',
                  hint: t.hintPurok,
                  controller: _purok,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  prefixIcon: const Icon(LucideIcons.signpost),
                ),
              ),
              const SizedBox(height: ZirenTokens.space20),
              RegField(
                label: t.fieldStreet,
                optional: true,
                child: ZirenTextField(
                  label: '',
                  hint: t.hintStreet,
                  controller: _street,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  helperText: t.regStreetHelp,
                  prefixIcon: const Icon(LucideIcons.house),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReferenceDataError extends StatelessWidget {
  const _ReferenceDataError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.severityHighBg,
        border: Border.all(color: ZirenTokens.severityHighBorder),
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.cloud_off, color: ZirenTokens.severityHigh),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              t.regBarangayListFailed,
              style: TextStyle(fontSize: 13.5, height: 1.4),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(t.actionRetry)),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.hint,
    required this.icon,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final String hint;
  final IconData icon;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: ZirenTokens.surfaceOverlay,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      icon: Icon(LucideIcons.chevron_down, color: ZirenTokens.textMuted),
      hint: Text(hint, style: TextStyle(color: ZirenTokens.textMuted)),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 20, color: ZirenTokens.textMuted),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }
}
