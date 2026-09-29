import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// One "how do I …" topic in Help.
class HelpTopic {
  const HelpTopic({
    required this.icon,
    required this.title,
    required this.summary,
    required this.steps,
    this.tip,
    this.route,
    this.routeLabel,
  });

  final IconData icon;
  final String title;

  /// One line under the title, so the list can be scanned closed.
  final String summary;

  /// What to do, in order.
  final List<String> steps;

  /// A good-to-know line after the steps.
  final String? tip;

  /// Where "Try it" goes, when the topic has a screen to open.
  final String? route;
  final String? routeLabel;
}

/// "How to use Ziren" — for residents and for responders.
///
/// Bundled in the app rather than fetched: help is needed exactly when the
/// app is confusing, and that is often when the connection is bad too.
/// Filipino is the default; English for anyone who chose it.
///
/// Keep these true to the app. Every step names a button that exists, with the
/// label it actually has; when a screen changes, change its topic here.
abstract final class HelpContent {
  static List<HelpTopic> resident(String languageCode) =>
      languageCode == 'en' ? _residentEn : _residentFil;

  static List<HelpTopic> responder(String languageCode) =>
      languageCode == 'en' ? _responderEn : _responderFil;

  // ── Resident — Filipino ──────────────────────────────────────────────────
  static const _residentFil = [
    HelpTopic(
      icon: LucideIcons.siren,
      title: 'Mag-report ng emergency',
      summary: 'Pinakamabilis: pindutin ang uri ng emergency sa Home.',
      steps: [
        'Sa Home, pindutin ang uri ng emergency: Sunog, Medikal, Aksidente, Krimen, Kalamidad, o Iba pa.',
        'Sa "Nasaan ang insidente?", iwan sa "Nandito ako mismo" kung nasa lugar ka. Awtomatikong kukunin ang GPS mo.',
        'Tingnan ang Landmark (kailangan). Kadalasan napupunan na ito ng pinakamalapit na landmark — itama kung mali.',
        'Ikuwento ang nangyari: magsalita gamit ang mikropono, o mag-type. Puwede ring maglagay ng litrato o video.',
        'Pindutin ang "I-review ang ulat", tingnan kung tama lahat, at saka ipadala.',
      ],
      tip: 'Awtomatikong pinipili ng Ziren ang pinakamalapit na tamang station — BFP sa sunog, PNP sa krimen, MDRRMO sa iba.',
    ),
    HelpTopic(
      icon: LucideIcons.map_pinned,
      title: 'Kung nasa ibang lugar ang insidente',
      summary: 'Halimbawa: nasa Kawayan ka pero sa Larrazabal ang insidente.',
      steps: [
        'Sa report, sa "Nasaan ang insidente?", piliin ang "Sa ibang lugar".',
        'Igalaw ang mapa hanggang nasa mismong lugar ng insidente ang orange na pin — o i-type ang barangay o landmark sa search.',
        'Pindutin ang "Gamitin ang lokasyong ito".',
        'Tingnan ang landmark at ituloy ang report gaya ng dati.',
      ],
      tip: 'Sa lugar ng insidente pupunta ang responder, hindi sa kinaroroonan mo. Makikita rin ng station na nasa ibang lugar ka, para matawagan ka kung may itatanong.',
    ),
    HelpTopic(
      icon: LucideIcons.phone_call,
      title: 'Walang internet? Tumawag sa station',
      summary: 'Nasa app ang opisyal na numero ng bawat station — gumagana kahit offline.',
      steps: [
        'Kapag "Walang internet" ang nasa itaas ng Home, pindutin ang uri ng emergency.',
        'Lalabas ang mga numero ng tamang station, nauuna ang pinakamalapit na bayan.',
        'Pindutin ang "Tumawag" sa numero — bubukas ang dialer ng phone mo.',
        'Puwede mo ring buksan anumang oras ang "Hotline ng mga station" sa Home.',
      ],
      tip: 'Signal lang ang kailangan sa tawag, hindi data. Nandiyan din ang 911.',
      route: '/hotlines',
      routeLabel: 'Buksan ang hotlines',
    ),
    HelpTopic(
      icon: LucideIcons.circle_alert,
      title: 'Hindi alam kung anong emergency? Gamitin ang SOS',
      summary: 'Ang malaking "Mag-ulat ng Emergency" sa Home.',
      steps: [
        'Pindutin ang malaking orange na card sa Home.',
        'Puwedeng pumili ng uri ng emergency kung alam mo — hindi ito kailangan.',
        'Lagyan ng tsek ang babala, at pindutin nang matagal ang button para ipadala.',
      ],
      tip: 'Kasama nang awtomatiko ang lokasyon at pinakamalapit na landmark. Para lamang ito sa totoong emergency — may parusa ang maling report.',
    ),
    HelpTopic(
      icon: LucideIcons.clipboard_list,
      title: 'Subaybayan ang report mo',
      summary: 'Sa "Mga Ulat" tab makikita ang estado at usapan sa station.',
      steps: [
        'Buksan ang "Mga Ulat" tab sa ibaba.',
        'Pindutin ang report para makita ang estado: Natanggap, Sinusuri, May paparating na responder, Dumating na ang responder, Nalutas.',
        'Kung may tanong ang station, lalabas ito bilang notification. Sagutin sa loob ng report.',
        'Sa "Tingnan sa Mapa", makikita ang station na humahawak at ang guhit papunta sa insidente.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.map,
      title: 'Ang Mapa',
      summary: 'Mga station, landmark, at ikaw.',
      steps: [
        'Buksan ang "Mapa" tab. Ang pin na may "Ikaw" ay ang lokasyon mo.',
        'Pindutin ang pin ng station para makita ang pangalan at layo nito.',
        'Pindutin ang "Kunin ang direksyon" para sa guhit papunta rito, o "Tawagan" para tumawag.',
        'I-filter ang BFP, PNP o MDRRMO gamit ang mga button sa itaas.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.user_round_check,
      title: 'Account at verification',
      summary: 'Profile, ID, wika at notifications.',
      steps: [
        'Sa Profile tab, i-verify ang account gamit ang valid ID para mas mabilis na ma-accept ang mga report mo.',
        'Sa Settings, palitan ang wika (Filipino o English) at ang notifications.',
        'Ilagay ang emergency contact mo para matawagan kung kailangan.',
      ],
    ),
  ];

  // ── Resident — English ───────────────────────────────────────────────────
  static const _residentEn = [
    HelpTopic(
      icon: LucideIcons.siren,
      title: 'Report an emergency',
      summary: 'Fastest way: tap the kind of emergency on Home.',
      steps: [
        'On Home, tap the kind of emergency: Fire, Medical, Accident, Crime, Calamity, or Other.',
        'Under "Where is the incident?", keep "I\'m at the incident" if you are there. Your GPS is used automatically.',
        'Check the Landmark (required). It is usually filled in with the nearest landmark — correct it if it is wrong.',
        'Say what happened with the microphone, or type it. You can add a photo or video too.',
        'Tap "Review report", check that everything is right, then send.',
      ],
      tip: 'Ziren picks the nearest right station for you — BFP for fire, PNP for crime, MDRRMO for the rest.',
    ),
    HelpTopic(
      icon: LucideIcons.map_pinned,
      title: 'When the incident is somewhere else',
      summary: 'For example: you are in Kawayan but the incident is in Larrazabal.',
      steps: [
        'In the report, under "Where is the incident?", choose "Somewhere else".',
        'Move the map until the orange pin is on the incident — or type the barangay or landmark in search.',
        'Tap "Use this location".',
        'Check the landmark and finish the report as usual.',
      ],
      tip: 'Responders go to the incident, not to you. The station also sees that you reported from elsewhere, so they can call you back if needed.',
    ),
    HelpTopic(
      icon: LucideIcons.phone_call,
      title: 'No internet? Call a station',
      summary: 'Every station\'s official number is inside the app — works offline.',
      steps: [
        'When Home shows "No internet" at the top, tap the kind of emergency.',
        'The numbers of the right stations appear, nearest town first.',
        'Tap "Call now" on a number — your phone\'s dialer opens.',
        'You can also open "Station hotlines" on Home at any time.',
      ],
      tip: 'A call needs only a signal, not data. 911 is listed too.',
      route: '/hotlines',
      routeLabel: 'Open hotlines',
    ),
    HelpTopic(
      icon: LucideIcons.circle_alert,
      title: 'Not sure what it is? Use SOS',
      summary: 'The big "Report an Emergency" card on Home.',
      steps: [
        'Tap the big orange card on Home.',
        'Choose the kind of emergency if you know it — it is optional.',
        'Tick the warning, then press and hold the button to send.',
      ],
      tip: 'Your location and nearest landmark are attached automatically. Use it only for real emergencies — false reports are penalised.',
    ),
    HelpTopic(
      icon: LucideIcons.clipboard_list,
      title: 'Track your report',
      summary: 'The Reports tab shows the status and messages from the station.',
      steps: [
        'Open the Reports tab at the bottom.',
        'Tap a report to see its status: Received, Being reviewed, Responder on the way, Responder arrived, Resolved.',
        'If the station asks something, you get a notification. Answer inside the report.',
        '"View on Map" shows the station handling it and the line to the incident.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.map,
      title: 'The Map',
      summary: 'Stations, landmarks, and you.',
      steps: [
        'Open the Map tab. The pin labelled "You" is where you are.',
        'Tap a station pin to see its name and distance.',
        'Tap "Get directions" for a line to it, or "Call" to phone it.',
        'Filter BFP, PNP or MDRRMO with the buttons at the top.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.user_round_check,
      title: 'Account and verification',
      summary: 'Profile, ID, language and notifications.',
      steps: [
        'In the Profile tab, verify your account with a valid ID so your reports are accepted faster.',
        'In Settings, change the language (Filipino or English) and notifications.',
        'Add your emergency contact so they can be reached if needed.',
      ],
    ),
  ];

  // ── Responder — Filipino ─────────────────────────────────────────────────
  static const _responderFil = [
    HelpTopic(
      icon: LucideIcons.toggle_right,
      title: 'Mag-on duty',
      summary: 'Walang ipapadalang assignment habang off duty ka.',
      steps: [
        'Sa Home, pindutin ang "Mag-on duty".',
        'Makikita sa "Mga nakatalaga sa iyo" ang mga insidenteng ibinigay sa iyo.',
        'Pagkatapos ng shift, pindutin ang "Mag-off duty".',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.bell_ring,
      title: 'Tumanggap o tumanggi sa assignment',
      summary: 'Tutunog ang alarm kapag may bagong assignment.',
      steps: [
        'Buksan ang insidente mula sa alarm o sa "Mga nakatalaga sa iyo".',
        'Pindutin ang "TATANGGAPIN KO" para tanggapin — malalaman agad ng dispatcher.',
        'Kung hindi kaya, pindutin ang "HINDI KAYA" at ilagay ang dahilan para makapagpadala sila ng iba.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.navigation,
      title: 'Pumunta at i-update ang status',
      summary: 'Makikita ng dispatcher at ng resident ang bawat update.',
      steps: [
        'Pindutin ang "Puntahan" para sa mapa papunta sa insidente.',
        'Sa "I-update ang Status", piliin ang "Papunta na" habang papunta, at "Nasa lugar" pagdating.',
        'Kapag tapos na, markahan bilang Nalutas at ilagay ang kinalabasan.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.camera,
      title: 'Litrato ng lugar at tulong mula sa ibang agency',
      summary: 'Ebidensya at dagdag na tulong.',
      steps: [
        'Kapag "Nasa lugar" ka na, pindutin ang "Kumuha ng larawan sa lugar".',
        'Kung kailangan ng ibang agency (hal. ambulansya), pindutin ang "Humingi ng saklolo sa ibang ahensya" at ilarawan ang kailangan.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.shield_alert,
      title: 'Kung ikaw mismo ang nasa panganib',
      summary: 'Ang distress signal ay para sa kaligtasan mo, hindi sa insidente.',
      steps: [
        'Pindutin nang matagal ang "PINDUTIN NANG MATAGAL KUNG NASA PANGANIB KA".',
        'Makikita agad ng dispatcher ang lokasyon mo.',
        'Kung walang signal, naka-queue ito — tumawag agad sa station sa radyo.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.radar,
      title: 'Mga insidente malapit sa iyo',
      summary: 'Bago pa may maipadala, puwede mong sabihin kung kaya mong pumunta.',
      steps: [
        'Lalabas sa "May insidenteng malapit sa iyo" ang mga bagong report sa paligid mo.',
        'Pindutin ang "Kaya kong pumunta" o "Hindi kaya". Ang dispatcher pa rin ang magpapasya.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.phone_call,
      title: 'Walang internet',
      summary: 'Naka-queue ang mga action mo at maipapadala pagbalik ng signal.',
      steps: [
        'Ang pag-accept, status update at litrato ay ipapadala kapag may signal na.',
        'Para sa agarang koordinasyon, tawagan ang station — nasa "Hotline ng mga station" ang lahat ng numero.',
      ],
      route: '/hotlines',
      routeLabel: 'Buksan ang hotlines',
    ),
  ];

  // ── Responder — English ──────────────────────────────────────────────────
  static const _responderEn = [
    HelpTopic(
      icon: LucideIcons.toggle_right,
      title: 'Go on duty',
      summary: 'No assignments are sent while you are off duty.',
      steps: [
        'On Home, tap "Go on duty".',
        'Incidents given to you appear under "Assigned to you".',
        'At the end of your shift, tap "Go off duty".',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.bell_ring,
      title: 'Accept or decline an assignment',
      summary: 'An alarm sounds when a new assignment arrives.',
      steps: [
        'Open the incident from the alarm or from "Assigned to you".',
        'Tap "I WILL RESPOND" to accept — the dispatcher knows at once.',
        'If you cannot, tap "CAN\'T RESPOND" and give the reason so they can send someone else.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.navigation,
      title: 'Go, and update your status',
      summary: 'The dispatcher and the resident see every update.',
      steps: [
        'Tap "Navigate" for a map to the incident.',
        'In "Update Status", choose En route on the way and On scene when you arrive.',
        'When done, mark it Resolved and record the outcome.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.camera,
      title: 'Scene photos and help from another agency',
      summary: 'Evidence and extra hands.',
      steps: [
        'Once you are On scene, tap "Take a photo of the scene".',
        'If another agency is needed (for example an ambulance), tap "Request another agency\'s help" and describe what you need.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.shield_alert,
      title: 'If you yourself are in danger',
      summary: 'The distress signal is for your safety, not the incident.',
      steps: [
        'Press and hold "PRESS AND HOLD IF YOU ARE IN DANGER".',
        'The dispatcher sees your location at once.',
        'With no signal it is queued — call the station on the radio right away.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.radar,
      title: 'Incidents near you',
      summary: 'Before anyone is sent, you can say whether you can go.',
      steps: [
        'New reports around you appear under "Incidents near you".',
        'Tap "I can respond" or "Not available". The dispatcher still decides.',
      ],
    ),
    HelpTopic(
      icon: LucideIcons.phone_call,
      title: 'No internet',
      summary: 'Your actions are queued and sent when the signal returns.',
      steps: [
        'Accepting, status updates and photos are sent once you have a signal.',
        'For anything urgent, call the station — every number is in "Station hotlines".',
      ],
      route: '/hotlines',
      routeLabel: 'Open hotlines',
    ),
  ];
}
