import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/announcement_model.dart';

/// The icon and colour of each kind of announcement - the same table the
/// dashboard uses (components/announcements/kinds.ts), so a Provincial Admin's
/// preview and the resident's phone agree.
///
/// Red stays reserved for critical severity: the evacuation order (and the
/// legacy "emergency") is the one life-safety order, so it is the only red one.
(IconData, Color) announcementStyle(String category) => switch (category) {
  'evacuation' => (LucideIcons.door_open, ZirenTokens.severityCritical),
  'weather' => (LucideIcons.cloud_lightning, ZirenTokens.systemInfo),
  'hazard' => (LucideIcons.triangle_alert, ZirenTokens.severityHigh),
  'road_closure' => (LucideIcons.construction, ZirenTokens.systemWarning),
  'missing_person' => (LucideIcons.user_search, ZirenTokens.agencyPNP),
  'all_clear' => (LucideIcons.shield_check, ZirenTokens.systemSuccess),
  'emergency' => (LucideIcons.siren, ZirenTokens.severityCritical),
  'relief' => (LucideIcons.package, ZirenTokens.agencyMDRRMO),
  'health' => (LucideIcons.heart_pulse, ZirenTokens.statusProcessing),
  'drill' => (LucideIcons.bell_ring, ZirenTokens.textSecondary),
  'utility' => (LucideIcons.plug_zap, ZirenTokens.systemWarning),
  'service_interruption' => (LucideIcons.wifi_off, ZirenTokens.systemWarning),
  'maintenance' => (LucideIcons.wrench, ZirenTokens.statusProcessing),
  'feature' => (LucideIcons.sparkles, ZirenTokens.agencyMDRRMO),
  'reminder' => (LucideIcons.bell, ZirenTokens.textSecondary),
  _ => (LucideIcons.megaphone, ZirenTokens.brandOrange),
};

/// PAGASA's own rainfall colours - that is what people know them by.
Color rainfallColor(String level) => switch (level) {
  'red' => ZirenTokens.severityCritical,
  'orange' => const Color(0xFFEA580C),
  _ => const Color(0xFFCA8A04),
};

String hazardLabel(AppLocalizations t, String key) => switch (key) {
  'flood' => t.annHazardFlood,
  'landslide' => t.annHazardLandslide,
  'storm_surge' => t.annHazardStormSurge,
  'earthquake' => t.annHazardEarthquake,
  'tsunami' => t.annHazardTsunami,
  'volcanic' => t.annHazardVolcanic,
  'fire' => t.annHazardFire,
  _ => t.annHazardOther,
};

String rainfallLabel(AppLocalizations t, String key) => switch (key) {
  'red' => t.annRainfallRed,
  'orange' => t.annRainfallOrange,
  _ => t.annRainfallYellow,
};

/// The short facts shown as chips under the title: "Signal No. 3", "Flood".
List<({String label, Color? color})> announcementChips(
  AppLocalizations t,
  AnnouncementModel a,
) {
  final out = <({String label, Color? color})>[];
  final d = a.details;
  switch (a.category) {
    case 'weather':
      final signal = (d['signal'] as num?)?.toInt();
      if (signal != null) {
        out.add((label: t.annSignal(signal), color: signal >= 3 ? ZirenTokens.severityHigh : null));
      }
      final rain = a.detail('rainfall');
      if (rain != null) out.add((label: rainfallLabel(t, rain), color: rainfallColor(rain)));
      final storm = a.detail('storm_name');
      if (storm != null) out.add((label: storm, color: null));
    case 'hazard':
      final h = a.detail('hazard');
      if (h != null) out.add((label: hazardLabel(t, h), color: null));
    case 'evacuation':
      final kind = a.detail('kind');
      if (kind == 'forced') {
        out.add((label: t.annEvacForced, color: ZirenTokens.severityCritical));
      } else if (kind == 'preemptive') {
        out.add((label: t.annEvacPreemptive, color: null));
      }
    case 'road_closure':
      final reopens = a.detail('reopens');
      if (reopens != null) out.add((label: t.annReopens(reopens), color: null));
    case 'missing_person':
      final age = (d['age'] as num?)?.toInt();
      if (age != null) out.add((label: t.annAge(age), color: null));
    case 'relief' || 'drill' || 'health' || 'utility':
      final when = a.detail('when');
      if (when != null) out.add((label: when, color: null));
  }
  return out;
}

/// The facts that are sentences: where to go, which road, who is missing.
List<({String label, String value})> announcementFacts(
  AppLocalizations t,
  AnnouncementModel a,
) {
  final out = <({String label, String value})>[];
  void add(String label, String? value) {
    if (value != null && value.trim().isNotEmpty) out.add((label: label, value: value.trim()));
  }

  switch (a.category) {
    case 'evacuation':
      for (final c in a.centers) {
        add(t.annGoTo, c['place'] == null ? c['name'] : '${c['name']} — ${c['place']}');
      }
      add(t.annBring, a.detail('bring'));
    case 'hazard':
      add(t.annArea, a.detail('area'));
    case 'road_closure':
      add(t.annClosed, a.detail('road'));
      add(t.annUseInstead, a.detail('alternate'));
    case 'missing_person':
      add(t.annName, a.detail('name'));
      add(t.annLastSeen, a.detail('last_seen'));
      add(t.annLooksLike, a.detail('description'));
      add(t.annCall, a.detail('contact'));
    case 'relief':
      add(t.annWhere, a.detail('where'));
      add(t.annBring, a.detail('bring'));
    case 'utility':
      add(t.annFrom, a.detail('provider'));
  }
  return out;
}
