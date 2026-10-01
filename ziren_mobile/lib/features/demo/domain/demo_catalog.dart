import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../incident_report/domain/incident_provider.dart';
import '../../incident_report/presentation/report_detail_screen.dart';
import '../../responder/domain/responder_provider.dart';
import '../../responder/domain/responder_vocabulary.dart';
import '../../sos/domain/sos_provider.dart';
import 'demo_models.dart';

/// Every screen Ziren can demonstrate, for residents and for responders.
///
/// The same rule as Help (help_content.dart): every line names a button that
/// exists, with the label it actually has. When a screen changes, change its
/// demo here, and its [DemoAnchor] ids in the screen.
///
/// A demo never sends, saves or changes anything. The report and SOS demos
/// open the real forms (the dimmed screen cannot be tapped while the mascot
/// talks) and close them again when the demo ends.
abstract final class DemoCatalog {
  static List<DemoScript> resident() => [
    _residentHome,
    _report,
    _sos,
    _myReports,
    _reportDetail,
    _residentMap,
    _residentProfile,
    _notifications,
    _hotlines(responder: false),
    _announcements,
  ];

  static List<DemoScript> responder() => [
    _responderHome,
    _assignment,
    _responderReports,
    _responderMap,
    _responderProfile,
    _notificationsResponder,
    _hotlines(responder: true),
  ];

  // ── Resident ────────────────────────────────────────────────────────────

  static final _residentHome = DemoScript(
    id: 'resident.home',
    icon: LucideIcons.house,
    titleFil: 'Ang Home',
    titleEn: 'Home',
    summaryFil: 'Saan nagsisimula ang report, ang SOS, at ang mga hotline.',
    summaryEn: 'Where reports, SOS and the hotlines start.',
    open: (context) async => GoRouter.of(context).go('/home'),
    steps: const [
      DemoStep(
        pose: DemoPose.excited,
        fil:
            'Hi! Ako si Ziren. Ipapakita ko sa iyo ang Home — dito nagsisimula ang bawat report.',
        en: "Hi! I'm Ziren. Let me show you Home — every report starts here.",
      ),
      DemoStep(
        anchor: 'header.mascot',
        fil:
            'Dito ako nagsasalita. Sa ilalim, dalawang chip: kung nasaan ka ngayon (GPS), at kung konektado ka sa Ziren.',
        en:
            'This is where I talk to you. Underneath, two chips: where you are now (GPS), and whether you are connected to Ziren.',
      ),
      DemoStep(
        anchor: 'home.alerts',
        fil:
            'Kapag may babala para sa barangay o bayan mo — halimbawa evacuation — lalabas ito rito, at dito mo sasabihin kung ligtas ka o kailangan mo ng tulong.',
        en:
            'When there is an alert for your barangay or town — an evacuation, say — it shows up here, and you answer right here whether you are safe or need help.',
      ),
      DemoStep(
        anchor: 'home.sos',
        pose: DemoPose.running,
        fil:
            'Hindi sigurado kung ano ang ilalarawan? Pindutin ang "Mag-ulat ng Emergency" — ang SOS. Piliin ang klase, i-check ang kumpirmasyon, at hawakan ang button para ipadala.',
        en:
            'Not sure what to describe? Press "Report an Emergency" — the SOS. Pick what is wrong, tick the confirmation, and hold the button to send.',
      ),
      DemoStep(
        anchor: 'home.categories',
        fil:
            'O pindutin agad ang uri ng emergency: Sunog, Medikal, Aksidente, Krimen, Kalamidad o Iba pa. Bubukas ang maikling report form — may hiwalay akong demo para doon.',
        en:
            'Or tap the kind of emergency straight away: Fire, Medical, Accident, Crime, Calamity or Other. A short report form opens — I have a separate demo for it.',
      ),
      DemoStep(
        anchor: 'home.hotlines',
        fil:
            'Hotline ng mga station: tawagan nang direkta ang BFP, PNP o MDRRMO. Kapag walang internet, ang pagpindot sa uri ng emergency ay magbubukas din ng mga numerong ito.',
        en:
            'Station hotlines: call BFP, PNP or MDRRMO directly. With no internet, tapping a kind of emergency opens these numbers too.',
      ),
      DemoStep(
        anchor: 'header.bell',
        fil:
            'Ang kampana: mga abiso tungkol sa report mo at mga anunsyo. May tuldok kapag may bago.',
        en:
            'The bell: news about your reports, and announcements. It shows a dot when something is new.',
      ),
      DemoStep(
        anchor: 'header.profile',
        fil: 'Ang bilog na may initials mo — papunta sa Profile mo.',
        en: 'The circle with your initials takes you to your Profile.',
      ),
      DemoStep(
        anchor: 'nav.reports',
        fil:
            'Sa "Mga Ulat", makikita mo ang lahat ng ipinadala mo at kung nasaan na ang bawat isa.',
        en: 'In "Reports" you see everything you sent and where each one stands.',
      ),
      DemoStep(
        anchor: 'nav.map',
        fil:
            'Sa "Mapa", ang mga emergency station na malapit sa iyo at ang mga report mo.',
        en: 'In "Map": the emergency stations near you, and your reports.',
      ),
      DemoStep(
        anchor: 'home.help',
        pose: DemoPose.wink,
        fil:
            'At kapag kailangan mo ulit ako, pindutin lang ang ulo ko rito. Ayan, tapos na tayo!',
        en: 'And whenever you need me again, just tap my head here. That is it!',
      ),
    ],
  );

  static final _report = DemoScript(
    id: 'resident.report',
    icon: LucideIcons.siren,
    titleFil: 'Paano mag-report',
    titleEn: 'How to report',
    summaryFil: 'Ang report form, hakbang-hakbang. Walang maipapadala.',
    summaryEn: 'The report form, step by step. Nothing is sent.',
    open: (context) async {
      // The form needs a category, the way a tile on Home sets one. Fire is
      // only the example; nothing leaves the phone.
      context.read<IncidentProvider>()
        ..clearWizard()
        ..setCategory(IncidentCategory.fire);
      final router = GoRouter.of(context)..go('/home');
      router.push('/report/quick');
    },
    close: (context) {
      final router = GoRouter.of(context);
      if (router.canPop()) router.pop();
      context.read<IncidentProvider>().clearWizard();
    },
    steps: const [
      DemoStep(
        pose: DemoPose.excited,
        fil:
            'Ganito mag-report. Halimbawa lang itong Sunog — walang maipapadala habang demo.',
        en:
            'This is how you report. Fire is only the example — nothing is sent during a demo.',
      ),
      DemoStep(
        anchor: 'report.category',
        fil:
            'Nasa itaas ang uri ng emergency na pinindot mo sa Home. Mali ang napili? Bumalik at pumili ng iba.',
        en:
            'At the top is the kind of emergency you tapped on Home. Wrong one? Go back and pick another.',
      ),
      DemoStep(
        anchor: 'report.where',
        fil:
            '"Nasaan ang insidente?" — iwan sa "Nandito ako mismo" kung nasa lugar ka; GPS ang kukuha ng lokasyon. Kung nasa ibang lugar, piliin ang "Sa ibang lugar" at igalaw ang mapa sa mismong lugar.',
        en:
            '"Where is the incident?" — leave it on "I\'m at the incident" if you are there; GPS finds the spot. If it is elsewhere, choose "Somewhere else" and move the map to the exact place.',
      ),
      DemoStep(
        anchor: 'report.where',
        pose: DemoPose.thinking,
        fil:
            'Kailangan ang Landmark, para mahanap ka ng responder. Kadalasan napupunan na ito ng pinakamalapit na landmark — itama kung mali.',
        en:
            'The Landmark is required, so the crew can find the place. It is usually filled in from the nearest landmark — fix it if it is wrong.',
      ),
      DemoStep(
        anchor: 'report.voice',
        fil:
            'I-tap ang mikropono at sabihin ang nangyari sa sarili mong salita. I-tap ulit para itigil. Diretso itong maririnig ng station.',
        en:
            'Tap the microphone and say what happened in your own words. Tap again to stop. The station hears it directly.',
      ),
      DemoStep(
        anchor: 'report.type',
        fil:
            'Puwede ring i-type ang mensahe, halimbawa "may naipit sa loob". Opsyonal ito.',
        en:
            'You can also type a message, like "someone is trapped inside". It is optional.',
      ),
      DemoStep(
        anchor: 'report.media',
        fil:
            'Maglagay ng litrato o video bilang ebidensya — hanggang 5. Opsyonal din.',
        en: 'Add photos or videos as evidence — up to 5. Also optional.',
      ),
      DemoStep(
        anchor: 'report.review',
        fil:
            'Pindutin ang "I-review ang ulat". Makikita mo ang buod at kung aling ahensya ang tatanggap — saka mo pipindutin ang "Ipadala ang ulat".',
        en:
            'Press "Review report". You see a summary and which agency will receive it — then press "Send report".',
      ),
      DemoStep(
        pose: DemoPose.ok,
        fil:
            'Tandaan: tunay na emergency report ang maipapadala, kaya maging seryoso at tumpak. Ibabalik na kita sa Home.',
        en:
            'Remember: what you send is a real emergency report, so be serious and accurate. Taking you back to Home now.',
      ),
    ],
  );

  static final _sos = DemoScript(
    id: 'resident.sos',
    icon: LucideIcons.triangle_alert,
    titleFil: 'Emergency SOS',
    titleEn: 'Emergency SOS',
    summaryFil: 'Ang pinakamabilis na paraan. Walang maipapadala.',
    summaryEn: 'The fastest way. Nothing is sent.',
    open: (context) async {
      final router = GoRouter.of(context)..go('/home');
      router.push('/sos-confirm');
    },
    close: (context) {
      context.read<SosProvider>().reset();
      final router = GoRouter.of(context);
      if (router.canPop()) router.pop();
    },
    steps: const [
      DemoStep(
        pose: DemoPose.excited,
        fil:
            'Ito ang Emergency SOS — para kapag nagmamadali ka o hindi mo alam kung paano ilalarawan. Demo lang ito.',
        en:
            'This is Emergency SOS — for when you are in a hurry or cannot describe it. This is only a demo.',
      ),
      DemoStep(
        anchor: 'sos.where',
        fil:
            'Awtomatikong kinukuha ang lokasyon mo at ang pinakamalapit na landmark. Pindutin ang landmark kung gusto mong palitan.',
        en:
            'Your location and the nearest landmark are found automatically. Tap the landmark if you want to change it.',
      ),
      DemoStep(
        anchor: 'sos.category',
        fil: 'Piliin ang klase ng emergency — kailangan ito bago maipadala.',
        en:
            'Pick what kind of emergency it is — it is needed before you can send.',
      ),
      DemoStep(
        anchor: 'sos.confirm',
        pose: DemoPose.thinking,
        fil:
            'Basahin ang Babala sa Batas at i-check na totoo ang emergency. May parusa ang pekeng report.',
        en:
            'Read the Legal Warning and tick that the emergency is real. A false report is punishable.',
      ),
      DemoStep(
        anchor: 'sos.send',
        fil:
            'Pindutin nang MATAGAL ang "Ipadala ang SOS Ngayon" — hindi isang tap, para hindi ito aksidenteng maipadala.',
        en:
            'Press and HOLD "Send SOS Now" — not a tap, so it is never sent by accident.',
      ),
      DemoStep(
        pose: DemoPose.ok,
        fil:
            'Ipapadala ang pangalan at lokasyon mo sa pinakamalapit na station. Walang naipadala ngayon — ibabalik na kita sa Home.',
        en:
            'Your name and location go to the nearest station. Nothing was sent now — taking you back to Home.',
      ),
    ],
  );

  static final _myReports = DemoScript(
    id: 'resident.reports',
    icon: LucideIcons.receipt_text,
    titleFil: 'Mga Ulat',
    titleEn: 'My Reports',
    summaryFil: 'Subaybayan ang bawat report na ipinadala mo.',
    summaryEn: 'Follow every report you sent.',
    open: (context) async => GoRouter.of(context).go('/my-reports'),
    steps: const [
      DemoStep(
        anchor: 'reports.title',
        fil:
            'Dito ang lahat ng report mo — ilan ang bukas, at ilan ang tapos na.',
        en:
            'All your reports are here — how many are open, and how many are done.',
      ),
      DemoStep(
        anchor: 'reports.filters',
        fil: 'Salain: Lahat, Bukas, Tapos, o Basura (mga report na binawi mo).',
        en: 'Filter: All, Active, Resolved, or Trash (reports you took back).',
      ),
      DemoStep(
        anchor: 'reports.card',
        fil:
            'Bawat report ay isang card na may takbo: Natanggap → Sinusuri → Papunta na → Tapos na. Pindutin ang card para makita ang detalye.',
        en:
            'Each report is a card with its progress: Received → Checking → On the way → Resolved. Tap the card to see the details.',
      ),
      DemoStep(
        pose: DemoPose.pointYou,
        fil:
            'Sa detalye, puwede kang makipag-chat sa station, o bawiin ang report habang "Natanggap" pa lang. May hiwalay akong demo para doon.',
        en:
            'In the details you can chat with the station, or take the report back while it is still "Received". I have a separate demo for that.',
      ),
    ],
  );

  static final _reportDetail = DemoScript(
    id: 'resident.reportDetail',
    icon: LucideIcons.file_text,
    titleFil: 'Detalye ng report',
    titleEn: 'Report details',
    summaryFil: 'Chat sa station, mapa, at takbo ng report.',
    summaryEn: 'Chat with the station, the map, and the progress.',
    available:
        (context) => context.read<IncidentProvider>().myIncidents.isNotEmpty,
    unavailableFil: 'Kailangan muna ng kahit isang report.',
    unavailableEn: 'Needs at least one report first.',
    open: (context) async {
      final mine = context.read<IncidentProvider>().myIncidents;
      if (mine.isEmpty) return;
      // An open report shows the most (chat, withdraw); else the newest.
      final pick = mine.firstWhere(
        (i) => i.status != 'resolved' && i.status != 'cancelled',
        orElse: () => mine.first,
      );
      GoRouter.of(context).go('/my-reports');
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportDetailScreen(incident: pick),
        ),
      );
    },
    steps: const [
      DemoStep(
        anchor: 'detail.hero',
        fil:
            'Nasa itaas ang kalagayan ngayon ng report mo at kung kailan ito ipinadala.',
        en: 'At the top: where your report stands now, and when you sent it.',
      ),
      DemoStep(
        pose: DemoPose.thinking,
        fil:
            'Kapag may tanong ang ahensya, lalabas dito ang "Kailangan ng ahensya ng karagdagang impormasyon" — pindutin ang "Sagutin". Hinihintay nila ang sagot mo.',
        en:
            'If the agency has a question, "The agency needs more information" appears here — press "Reply". They wait for your answer.',
      ),
      DemoStep(
        anchor: 'detail.said',
        fil: '"Ang iniulat mo" — ang mismong sinabi o isinulat mo.',
        en: '"What you reported" — exactly what you said or wrote.',
      ),
      DemoStep(
        anchor: 'detail.map',
        fil:
            'Pindutin ang "Tingnan sa Mapa" para makita kung saan ito at kung aling station ang humahawak.',
        en:
            'Press "View on Map" to see where it is and which station is handling it.',
      ),
      DemoStep(
        anchor: 'detail.progress',
        fil: 'Ang takbo ng report, kasama ang oras ng bawat hakbang.',
        en: 'The progress of the report, with the time of every step.',
      ),
      DemoStep(
        anchor: 'detail.actions',
        fil:
            'Habang bukas: "Chat" para makausap ang station. Habang "Natanggap" pa lang: "Ilipat sa Basura" kung nagkamali ka. Kapag tapos na: dito ka magre-rate ng serbisyo.',
        en:
            'While open: "Chat" to talk to the station. While still "Received": "Move to Trash" if it was a mistake. Once resolved: rate the service here.',
      ),
    ],
  );

  static List<DemoStep> _mapSteps({required bool responder}) => [
    DemoStep(
      anchor: 'map.header',
      fil:
          responder
              ? 'Ang Mapa ng mga Insidente: ang mga incident na naka-assign sa iyo, at ang mga station.'
              : 'Ang Mapa: ang mga emergency station na malapit sa iyo, at ang mga report mo.',
      en:
          responder
              ? 'The Incident Map: the incidents assigned to you, and the stations.'
              : 'The Map: the emergency stations near you, and your reports.',
    ),
    const DemoStep(
      anchor: 'map.filters',
      fil:
          'Pindutin ang BFP, PNP o MDRRMO para itago o ipakita ang mga station nila.',
      en: 'Tap BFP, PNP or MDRRMO to hide or show their stations.',
    ),
    const DemoStep(
      anchor: 'map.mylocation',
      fil:
          'Dito makikita kung alam ng Ziren kung nasaan ka, at gaano katumpak ang GPS.',
      en:
          'This shows whether Ziren knows where you are, and how precise the GPS is.',
    ),
    const DemoStep(
      anchor: 'map.locate',
      fil: 'Pindutin para bumalik ang mapa sa lokasyon mo.',
      en: 'Tap to bring the map back to where you are.',
    ),
    const DemoStep(
      anchor: 'map.station',
      fil:
          'Ang pinakamalapit na station. Pindutin ang "Kunin ang direksyon" para sa ruta, o pumili ng iba sa "Iba pang istasyon".',
      en:
          'The nearest station. Press "Get directions" for the route, or pick another under "Other stations".',
    ),
    const DemoStep(
      pose: DemoPose.pointYou,
      fil: 'Pindutin ang anumang pin sa mapa para makita ang detalye nito.',
      en: 'Tap any pin on the map to see its details.',
    ),
  ];

  static final _residentMap = DemoScript(
    id: 'resident.map',
    icon: LucideIcons.map,
    titleFil: 'Ang Mapa',
    titleEn: 'The Map',
    summaryFil: 'Mga station na malapit sa iyo at ang mga report mo.',
    summaryEn: 'Stations near you and your reports.',
    open: (context) async => GoRouter.of(context).go('/map'),
    steps: _mapSteps(responder: false),
  );

  static final _residentProfile = DemoScript(
    id: 'resident.profile',
    icon: LucideIcons.user,
    titleFil: 'Ang Profile',
    titleEn: 'Profile',
    summaryFil: 'Ang impormasyon mo, verification, at Settings.',
    summaryEn: 'Your details, verification and Settings.',
    open: (context) async => GoRouter.of(context).go('/profile'),
    steps: const [
      DemoStep(
        anchor: 'profile.hero',
        fil:
            'Ang profile mo: pangalan, email, at kung verified ka. Pindutin ang litrato para palitan.',
        en:
            'Your profile: name, email, and whether you are verified. Tap the photo to change it.',
      ),
      DemoStep(
        anchor: 'profile.verify',
        fil:
            'Hindi pa verified? Dito mo ipapadala ang ID mo para ma-verify ang account mo.',
        en:
            'Not verified yet? This is where you send your ID to verify your account.',
      ),
      DemoStep(
        anchor: 'profile.info',
        fil:
            'Ang personal mong impormasyon. Pindutin ang alinman para baguhin ito sa Settings.',
        en: 'Your personal details. Tap any of them to change it in Settings.',
      ),
      DemoStep(
        anchor: 'profile.emergency',
        fil:
            'Ang emergency contact: ang taong tatawagan kung hindi ka makasagot. Hindi ikaw.',
        en:
            'Your emergency contact: someone we can call if you cannot answer. Not you.',
      ),
      DemoStep(
        anchor: 'profile.help',
        fil:
            'Mga hotline, ang gabay na ito, ang Safety guide at mga Anunsyo — laging narito.',
        en:
            'Hotlines, this guide, the Safety guide and Announcements — always here.',
      ),
      DemoStep(
        anchor: 'profile.account',
        pose: DemoPose.ok,
        fil:
            'Sa Settings: wika, mga notification, at pagpalit ng password. At dito rin ang Log out.',
        en:
            'In Settings: language, notifications, and changing your password. Log out is here too.',
      ),
    ],
  );

  static List<DemoStep> _notificationSteps({required bool responder}) => [
    DemoStep(
      anchor: 'notif.first',
      fil:
          responder
              ? 'Dito ang mga abiso: bagong assignment, kung inalis ka sa isang tawag, at mga anunsyo. Pindutin para buksan; i-swipe para alisin.'
              : 'Dito ang mga abiso: pagbabago sa report mo, mensahe ng station, at mga anunsyo. Pindutin para buksan; i-swipe para alisin.',
      en:
          responder
              ? 'Your notifications: a new assignment, being taken off a call, and announcements. Tap to open; swipe to dismiss.'
              : 'Your notifications: changes to your reports, messages from the station, and announcements. Tap to open; swipe to dismiss.',
    ),
    const DemoStep(
      anchor: 'notif.menu',
      fil: 'Kapag may abiso, nasa menu (⋮) sa itaas ang "I-clear lahat".',
      en:
          'When there are notifications, the menu (⋮) at the top has "Clear all".',
    ),
    const DemoStep(
      pose: DemoPose.ok,
      fil:
          'Walang abiso? Lalabas dito ang bago, at magkakaroon ng tuldok ang kampana sa Home.',
      en: 'Nothing here? New ones appear here, and the bell on Home gets a dot.',
    ),
  ];

  static final _notifications = DemoScript(
    id: 'resident.notifications',
    icon: LucideIcons.bell,
    titleFil: 'Mga abiso',
    titleEn: 'Notifications',
    summaryFil: 'Balita tungkol sa report mo at mga anunsyo.',
    summaryEn: 'News about your reports, and announcements.',
    screenAnchor: 'notif.screen',
    open: (context) async {
      // Not returned: push's future completes only when the screen is closed,
      // and the tour would wait for that before it began.
      GoRouter.of(context).push('/notifications');
    },
    steps: _notificationSteps(responder: false),
  );

  static DemoScript _hotlines({required bool responder}) => DemoScript(
    id: responder ? 'responder.hotlines' : 'resident.hotlines',
    icon: LucideIcons.phone_call,
    titleFil: 'Mga hotline',
    titleEn: 'Hotlines',
    summaryFil: 'Tumawag sa station, kahit walang internet.',
    summaryEn: 'Call a station, even with no internet.',
    open: (context) async {
      // Not returned: push's future completes only when the screen is closed,
      // and the tour would wait for that before it began.
      GoRouter.of(context).push('/hotlines');
    },
    steps: const [
      DemoStep(
        anchor: 'hot.national',
        fil:
            'Ang National Emergency Hotline — gumagana kahit saan sa Pilipinas.',
        en: 'The National Emergency Hotline — works anywhere in the Philippines.',
      ),
      DemoStep(
        anchor: 'hot.filters',
        fil: 'Salain ayon sa ahensya: BFP, PNP, MDRRMO o RHU.',
        en: 'Filter by agency: BFP, PNP, MDRRMO or RHU.',
      ),
      DemoStep(
        anchor: 'hot.first',
        fil:
            'Nauuna ang bayang pinakamalapit sa iyo. Pindutin ang numero para buksan ang dialer — ikaw pa rin ang magpipindot ng tawag.',
        en:
            'The nearest town comes first. Tap a number to open the dialer — you still place the call yourself.',
      ),
      DemoStep(
        pose: DemoPose.ok,
        fil:
            'Nasa app mismo ang mga numero, kaya gumagana ito kahit walang internet.',
        en:
            'The numbers are inside the app, so this works even with no internet.',
      ),
    ],
  );

  static final _announcements = DemoScript(
    id: 'resident.announcements',
    icon: LucideIcons.megaphone,
    titleFil: 'Mga anunsyo at babala',
    titleEn: 'Announcements and alerts',
    summaryFil: 'Mga babala sa lugar mo, at paano sumagot.',
    summaryEn: 'Alerts for your area, and how to answer.',
    open: (context) async {
      // Not returned: push's future completes only when the screen is closed,
      // and the tour would wait for that before it began.
      GoRouter.of(context).push('/announcements');
    },
    screenAnchor: 'ann.screen',
    steps: const [
      DemoStep(
        anchor: 'ann.safety',
        fil:
            'Dito lalabas ang mga babala para sa lugar mo — halimbawa evacuation o bagyo. Nauuna ang mga hindi mo pa nasasagot.',
        en:
            'Alerts for your area show up here — an evacuation or a storm, say. The ones you have not answered come first.',
      ),
      DemoStep(
        anchor: 'ann.update',
        fil: 'Sa ilalim nila, ang iba pang abiso mula sa mga ahensya.',
        en: 'Below them, other updates from the agencies.',
      ),
      DemoStep(
        pose: DemoPose.pointYou,
        fil:
            'Pindutin ang anunsyo para basahin nang buo. Kapag nagtatanong ito, sabihin kung ligtas ka o kailangan mo ng tulong — agad na maaabisuhan ang mga station ng bayan mo, kasama kung nasaan ang phone mo.',
        en:
            'Tap an announcement to read it in full. When it asks, say whether you are safe or need help — the stations of your town are told at once, with where your phone is.',
      ),
    ],
  );

  // ── Responder ───────────────────────────────────────────────────────────

  static final _responderHome = DemoScript(
    id: 'responder.home',
    icon: LucideIcons.house,
    titleFil: 'Ang Home',
    titleEn: 'Home',
    summaryFil: 'Duty status, ang trabaho mo, at mga insidenteng malapit.',
    summaryEn: 'Duty status, your work, and incidents near you.',
    open: (context) async => GoRouter.of(context).go('/responder/queue'),
    steps: const [
      DemoStep(
        pose: DemoPose.excited,
        fil: 'Hi! Ako si Ziren. Ipapakita ko ang Home mo bilang responder.',
        en: "Hi! I'm Ziren. Let me show you your Home as a responder.",
      ),
      DemoStep(
        anchor: 'header.mascot',
        fil:
            'Dito ko sinasabi ang kalagayan mo: off duty, handa, o ilan ang naka-assign at ilan ang critical.',
        en:
            'Here I tell you where you stand: off duty, ready, or how many are assigned and how many are critical.',
      ),
      DemoStep(
        anchor: 'resp.duty',
        fil:
            'Ang Duty Status. I-on para makatanggap ng dispatch; i-off kapag tapos na ang shift. Walang ipapadala sa iyo habang off duty.',
        en:
            'Duty Status. Turn it on to receive dispatches; off when your shift ends. Nothing is sent to you while off duty.',
      ),
      DemoStep(
        anchor: 'resp.stats',
        fil:
            'Ang mga numero mo: Nakatalaga, Kritikal, at Pinakamatagal na naghihintay. Pindutin ang isa para makita ang trabahong binibilang nito.',
        en:
            'Your numbers: Assigned, Critical, and Longest waiting. Tap one to bring the work it counts into view.',
      ),
      DemoStep(
        anchor: 'resp.work',
        fil:
            'Dito lalabas ang trabaho mo. Ang "Unahin mo ito" ang dapat mong unahin — pindutin ang "Buksan" para sa detalye, o "Puntahan" para sa ruta.',
        en:
            'Your work shows up here. "Do this first" is the one to do first — press "Open" for the details, or "Navigate" for the route.',
      ),
      DemoStep(
        anchor: 'resp.nearby',
        pose: DemoPose.thinking,
        fil:
            '"May insidenteng malapit sa iyo": wala pang naipadalang responder. Sabihin kung "Kaya kong pumunta" o "Hindi kaya" — ang dispatcher pa rin ang magpapasya.',
        en:
            '"Incidents near you": nobody has been sent yet. Say "I can respond" or "Not available" — the dispatcher still decides.',
      ),
      DemoStep(
        anchor: 'resp.recent',
        fil: 'Kamakailang naisara. Ang buong listahan ay nasa Reports.',
        en: 'Recently closed. The full list is in Reports.',
      ),
      DemoStep(
        anchor: 'header.bell',
        fil: 'Ang kampana: bagong assignment, o kung inalis ka sa isang tawag.',
        en: 'The bell: a new assignment, or being taken off a call.',
      ),
      DemoStep(
        anchor: 'rnav.reports',
        fil:
            'Reports — lahat ng ipinadala sa iyo ng dispatcher, bukas at sarado.',
        en: 'Reports — everything a dispatcher has sent you, open and closed.',
      ),
      DemoStep(
        anchor: 'rnav.map',
        fil: 'Mapa — ang mga incident mo at ang mga station.',
        en: 'Map — your incidents and the stations.',
      ),
      DemoStep(
        anchor: 'resp.help',
        pose: DemoPose.wink,
        fil:
            'Pindutin ang ulo ko kapag kailangan mo ulit ng tulong. Mag-ingat ka!',
        en: 'Tap my head whenever you need help again. Stay safe!',
      ),
    ],
  );

  static String? _assignmentId(BuildContext context) {
    final p = context.read<ResponderProvider>();
    if (p.queue.isNotEmpty) return ResponderVocabulary.sorted(p.queue).first.id;
    if (p.history.isNotEmpty) return p.history.first.id;
    return null;
  }

  static final _assignment = DemoScript(
    id: 'responder.assignment',
    icon: LucideIcons.clipboard_check,
    titleFil: 'Ang isang assignment',
    titleEn: 'An assignment',
    summaryFil: 'Tanggapin, puntahan, i-update ang status, at isara.',
    summaryEn: 'Accept, go, update the status, and close.',
    available: (context) => _assignmentId(context) != null,
    unavailableFil: 'Kailangan muna ng kahit isang assignment.',
    unavailableEn: 'Needs at least one assignment first.',
    open: (context) async {
      final id = _assignmentId(context);
      if (id == null) return;
      final router = GoRouter.of(context)..go('/responder/queue');
      router.push('/responder/incident/$id');
    },
    steps: const [
      DemoStep(
        pose: DemoPose.excited,
        fil:
            'Ito ang detalye ng isang assignment — dito mo ginagawa ang trabaho. Walang babaguhin ang demo.',
        en:
            'These are the details of an assignment — this is where the work happens. The demo changes nothing.',
      ),
      DemoStep(
        anchor: 'ridet.summary',
        fil:
            'Ano ang nangyari: ang uri, ang severity, at ang sinabi ng nag-report.',
        en: 'What happened: the kind, the severity, and what the reporter said.',
      ),
      DemoStep(
        anchor: 'ridet.progress',
        fil: 'Ang takbo ng assignment, hakbang-hakbang, hanggang matapos.',
        en: 'The progress of the assignment, step by step, until it is done.',
      ),
      DemoStep(
        anchor: 'ridet.where',
        fil: 'Saan: ang address, ang palatandaan, at ang mapa.',
        en: 'Where: the address, the landmark, and the map.',
      ),
      DemoStep(
        anchor: 'ridet.navigate',
        fil: 'Pindutin ang "Puntahan" para buksan ang ruta papunta roon.',
        en: 'Press "Navigate" to open the route there.',
      ),
      DemoStep(
        anchor: 'ridet.reporter',
        fil: 'Ang nag-report, at kung paano sila tawagan.',
        en: 'The reporter, and how to call them.',
      ),
      DemoStep(
        anchor: 'ridet.notes',
        fil:
            'Mga update at mensahe para sa tawag na ito, kapag natanggap mo na.',
        en: 'Updates and messages for this call, once you have taken it.',
      ),
      DemoStep(
        anchor: 'ridet.emergency',
        pose: DemoPose.thinking,
        fil:
            'Humingi ng saklolo sa ibang ahensya, i-escalate kung mas malala ito, o kumuha ng larawan sa lugar (kapag nasa lugar ka na). Ang pulang button: pindutin nang matagal kung IKAW ang nasa panganib.',
        en:
            "Request another agency's help, escalate if it is worse than assessed, or take a photo of the scene (once you are on scene). The red button: press and hold if YOU are in danger.",
      ),
      DemoStep(
        anchor: 'ridet.action',
        fil:
            'Ang susunod na hakbang, nasa ilalim ng hinlalaki mo. Bagong tawag: "TATANGGAPIN KO" o "HINDI KAYA" (may dahilan). Pagkatapos: Papunta Na → Nakarating Na → Natapos Na.',
        en:
            'The next step, under your thumb. A new call: "I WILL RESPOND" or "CAN\'T RESPOND" (with a reason). Then: On my way → Arrived → Done.',
      ),
      DemoStep(
        pose: DemoPose.ok,
        fil:
            'Sa "Natapos Na", sasabihin mo kung ano ang natagpuan ninyo bago ito maisara. Ayan!',
        en:
            'At "Done", you say what you found before the incident is closed. That is it!',
      ),
    ],
  );

  static final _responderReports = DemoScript(
    id: 'responder.reports',
    icon: LucideIcons.clipboard_list,
    titleFil: 'Reports',
    titleEn: 'Reports',
    summaryFil: 'Lahat ng ipinadala sa iyo, at ang rekord mo.',
    summaryEn: 'Everything sent to you, and your record.',
    open: (context) async => GoRouter.of(context).go('/responder/reports'),
    steps: const [
      DemoStep(
        anchor: 'rrep.toggle',
        fil:
            '"Listahan" para sa mga report; "Rekord" para sa mga trend at oras ng pagtugon mo.',
        en:
            '"List" for the reports; "Record" for your trends and response times.',
      ),
      DemoStep(
        anchor: 'rrep.search',
        fil: 'Hanapin ayon sa barangay, numero (INC) o salita.',
        en: 'Search by barangay, number (INC) or words.',
      ),
      DemoStep(
        anchor: 'rrep.filters',
        fil: 'Salain: Lahat, Bukas o Sarado.',
        en: 'Filter: All, Open or Closed.',
      ),
      DemoStep(
        anchor: 'rrep.first',
        pose: DemoPose.ok,
        fil: 'Pindutin ang isang report para buksan ang detalye nito.',
        en: 'Tap a report to open its details.',
      ),
    ],
  );

  static final _responderMap = DemoScript(
    id: 'responder.map',
    icon: LucideIcons.map,
    titleFil: 'Ang Mapa',
    titleEn: 'The Map',
    summaryFil: 'Ang mga incident mo at ang mga station.',
    summaryEn: 'Your incidents and the stations.',
    open: (context) async => GoRouter.of(context).go('/responder/map'),
    steps: _mapSteps(responder: true),
  );

  static final _responderProfile = DemoScript(
    id: 'responder.profile',
    icon: LucideIcons.user,
    titleFil: 'Ang Profile',
    titleEn: 'Profile',
    summaryFil: 'Badge, istasyon, at Settings.',
    summaryEn: 'Badge, station and Settings.',
    open: (context) async => GoRouter.of(context).go('/responder/profile'),
    steps: const [
      DemoStep(
        anchor: 'rprof.hero',
        fil:
            'Ang profile mo: ahensya, duty status, Badge ID at kung aprubado ka na.',
        en:
            'Your profile: agency, duty status, Badge ID and whether you are approved.',
      ),
      DemoStep(
        anchor: 'rprof.contact',
        fil: 'Ang contact details mo. Binabago ang mga ito sa Settings.',
        en: 'Your contact details. They are changed in Settings.',
      ),
      DemoStep(
        anchor: 'rprof.station',
        fil:
            'Ang istasyon mo: ahensya, munisipyo, at ang mga numero ng station.',
        en: 'Your station: agency, municipality, and its phone numbers.',
      ),
      DemoStep(
        anchor: 'rprof.help',
        fil: 'Mga hotline at ang gabay na ito.',
        en: 'Hotlines and this guide.',
      ),
      DemoStep(
        anchor: 'rprof.account',
        pose: DemoPose.ok,
        fil: 'Settings at Log out.',
        en: 'Settings and Log out.',
      ),
    ],
  );

  static final _notificationsResponder = DemoScript(
    id: 'responder.notifications',
    icon: LucideIcons.bell,
    titleFil: 'Mga abiso',
    titleEn: 'Notifications',
    summaryFil: 'Bagong assignment at mga anunsyo.',
    summaryEn: 'New assignments and announcements.',
    screenAnchor: 'notif.screen',
    open: (context) async {
      // Not returned: push's future completes only when the screen is closed,
      // and the tour would wait for that before it began.
      GoRouter.of(context).push('/notifications');
    },
    steps: _notificationSteps(responder: true),
  );
}
