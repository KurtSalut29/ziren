import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/agency_contact_repository.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Official emergency contact numbers — spec Section 21.
///
/// The alternative path when Ziren itself cannot be used: the account is
/// locked out, the phone has no data, or the situation calls for a direct
/// call over a report. BFP/PNP/MDRRMO numbers come live from the agencies
/// table (never hardcoded — a wrong number here is worse than a missing
/// feature); the national emergency line is the one number true everywhere
/// in the Philippines regardless of what this database has on file.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _repo = AgencyContactRepository();
  List<AgencyContact>? _contacts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await _repo.fetchContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    await launchUrl(uri);
  }

  (Color, Color, IconData) _agencyStyle(String type) => switch (type) {
    'BFP' => (
      ZirenTokens.agencyBFP,
      ZirenTokens.agencyBFPBg,
      LucideIcons.flame,
    ),
    'PNP' => (
      ZirenTokens.agencyPNP,
      ZirenTokens.agencyPNPBg,
      LucideIcons.shield,
    ),
    _ => (
      ZirenTokens.agencyMDRRMO,
      ZirenTokens.agencyMDRRMOBg,
      LucideIcons.shield_plus,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.contactsTitle)),
      body: RefreshIndicator(
        color: ZirenTokens.brandOrange,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(ZirenTokens.space16),
          children: [
            // ── National line — always shown, never depends on data. ──
            _ContactCard(
              color: ZirenTokens.severityCritical,
              bg: ZirenTokens.severityCriticalBg,
              icon: LucideIcons.siren,
              title: t.contactsNationalTitle,
              subtitle: t.contactsNationalSubtitle,
              number: '911',
              onCall: () => _call('911'),
            ),
            const SizedBox(height: ZirenTokens.space16),

            _SectionLabel(t.contactsLocalAgencies),
            const SizedBox(height: ZirenTokens.space10),

            if (_contacts == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: ZirenTokens.space32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: ZirenTokens.brandOrange,
                  ),
                ),
              )
            else if (_contacts!.isEmpty)
              Container(
                padding: const EdgeInsets.all(ZirenTokens.space20),
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceCard,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  border: Border.all(color: ZirenTokens.surfaceBorder),
                ),
                child: Text(
                  t.contactsNoneListed,
                  style: TextStyle(
                    fontSize: 13,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              )
            else
              for (final c in _contacts!) ...[
                Builder(
                  builder: (context) {
                    final (color, bg, icon) = _agencyStyle(c.agencyType);
                    return _ContactCard(
                      color: color,
                      bg: bg,
                      icon: icon,
                      title: c.name,
                      subtitle: c.municipality,
                      number: c.contactNumber!,
                      onCall: () => _call(c.contactNumber!),
                    );
                  },
                ),
                const SizedBox(height: ZirenTokens.space10),
              ],

            const SizedBox(height: ZirenTokens.space16),
            _SectionLabel(t.contactsHospitalsSection),
            const SizedBox(height: ZirenTokens.space10),
            // The whole card opens the map, not only the small "Open" at its
            // edge: it reads as one button, and tapping its title did nothing.
            //
            // go, not push. /map is a tab of the shell; pushing it built a
            // second copy of the shell over the first (same navigator keys, so
            // Flutter could not render it) - which is the white screen this
            // used to open.
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
                      Icon(
                        LucideIcons.hospital,
                        size: 20,
                        color: ZirenTokens.textMuted,
                      ),
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
                              style: TextStyle(
                                fontSize: 12,
                                color: ZirenTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/map'),
                        child: Text(t.contactsOpen),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: ZirenTokens.textMuted,
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.color,
    required this.bg,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.number,
    required this.onCall,
  });

  final Color color;
  final Color bg;
  final IconData icon;
  final String title;
  final String subtitle;
  final String number;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
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
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  number,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: onCall,
            style: IconButton.styleFrom(backgroundColor: color),
            icon: const Icon(LucideIcons.phone, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
