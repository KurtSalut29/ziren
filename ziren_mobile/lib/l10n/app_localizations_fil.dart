// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get regIdTypeTitle => 'Pumili ng ID';

  @override
  String get regIdTypeSubtitle => 'Isang beses lang namin ito gagamitin, para matiyak na totoong tao kayo sa Biliran.';

  @override
  String get actionTakePhoto => 'Kumuha ng larawan';

  @override
  String get regTakeIdPhoto => 'Kumuha ng larawan ng inyong ID';

  @override
  String get regIdPhotoTips => 'Patag, maliwanag, kita ang apat na sulok';

  @override
  String get regIdReadable => 'Mukhang nababasa ang inyong ID.';

  @override
  String get reportReceivedTitle => 'Natanggap ang Ulat';

  @override
  String get reportReceivedBody => 'Nasa dispatcher na ang iyong ulat.';

  @override
  String get recordedAs => 'Naitala bilang';

  @override
  String get sentTo => 'Ipinadala sa';

  @override
  String get locationAttached => 'May kasamang lokasyon';

  @override
  String mediaAttached(int count) {
    return '$count larawan o video';
  }

  @override
  String get reportIdLabel => 'Report ID';

  @override
  String get trackReport => 'Subaybayan ang Ulat';

  @override
  String get backToHome => 'Bumalik sa Home';

  @override
  String get myReportsTitle => 'Aking mga ulat';

  @override
  String get filterAll => 'Lahat';

  @override
  String get filterOpen => 'Bukas';

  @override
  String get filterDone => 'Tapos';

  @override
  String get statusReceived => 'Natanggap';

  @override
  String get statusProcessing => 'Sinusuri';

  @override
  String get statusDispatched => 'May paparating na responder';

  @override
  String get statusResolved => 'Nalutas';

  @override
  String get statusCancelled => 'Kinansela';

  @override
  String get notifStatusTitle => 'Update sa ulat';

  @override
  String get notifStatusProcessing => 'Sinusuri na ang iyong ulat.';

  @override
  String get notifStatusDispatched => 'May paparating nang responder.';

  @override
  String get notifStatusResolved => 'Naresolba na ang iyong ulat.';

  @override
  String get notifStatusCancelled => 'Kinansela ang iyong ulat.';

  @override
  String get notifStatusOk => 'Sige';

  @override
  String get noReportsYet => 'Wala ka pang ulat';

  @override
  String get noReportsYetBody => 'Lalabas dito ang mga isinumite mong ulat.';

  @override
  String get noOpenReports => 'Walang bukas na ulat';

  @override
  String get noOpenReportsBody => 'Lahat ng ulat mo ay tapos na.';

  @override
  String get noResolvedYet => 'Wala pang natapos';

  @override
  String get noResolvedYetBody => 'Lilitaw dito ang mga ulat na nalutas na.';

  @override
  String get noDetails => 'Walang detalye';

  @override
  String get retry => 'Subukan muli';

  @override
  String get groupToday => 'Ngayong araw';

  @override
  String get groupYesterday => 'Kahapon';

  @override
  String get groupThisWeek => 'Nitong linggo';

  @override
  String get groupThisMonth => 'Nitong buwan';

  @override
  String get groupOlder => 'Mas matagal na';

  @override
  String get categoryFire => 'Sunog';

  @override
  String get categoryMedicalTrauma => 'Medikal / Trauma';

  @override
  String get categoryVehicular => 'Aksidente sa Daan';

  @override
  String get categoryFloodLandslideCalamity => 'Baha / Landslide / Kalamidad';

  @override
  String get categoryDomesticDisputeCrime => 'Kaguluhan / Krimen';

  @override
  String get categoryOther => 'Iba pa';

  @override
  String get preferredLanguage => 'Wika';

  @override
  String reportsOpenCount(int open, int total) {
    return '$open bukas · $total sa kabuuan';
  }

  @override
  String reportsAllDone(int total) {
    return '$total ulat · lahat tapos na';
  }

  @override
  String get noReportsYetLong => 'Kapag nag-ulat ka ng emergency, makikita mo dito ang bawat hakbang ng tugon.';

  @override
  String get consentTitle => 'Bago kayo magsimula';

  @override
  String get consentSubtitle => 'Pakibasa at sang-ayunan ang dalawang dokumento sa ibaba.';

  @override
  String get consentSummaryTitle => 'Ang maikling bersyon';

  @override
  String get consentSummaryLocation => 'Ginagamit namin ang inyong lokasyon at contact details para matagpuan kayo ng mga responder.';

  @override
  String get consentSummaryReporting => 'Makakapagpadala ng ulat kapag na-verify na ng administrator ang inyong account. Laging gumagana ang mga emergency hotline.';

  @override
  String get consentSummaryPhotos => 'Buburahin ang larawan ng ID ninyo kapag nasuri na. Pribado ang larawan ng mukha ninyo, bilang larawan sa Ziren ID na administrator lang ang nakakakita.';

  @override
  String get consentSummaryNotHotline => 'Hindi kapalit ng 911 ang Ziren. Tumawag nang direkta kung hindi maabot ng app ang network.';

  @override
  String get consentPrivacyTitle => 'Paunawa sa Pagkapribado ng Datos';

  @override
  String get consentPrivacySubtitle => 'Ano ang kinokolekta namin at bakit';

  @override
  String get consentTermsTitle => 'Mga Tuntunin ng Paggamit';

  @override
  String get consentTermsSubtitle => 'Ano ang ginagawa ng Ziren, at ano ang hindi';

  @override
  String get consentActionRead => 'Basahin';

  @override
  String get consentBadgeRead => 'Nabasa na';

  @override
  String get consentAgreePrivacy => 'Sumasang-ayon ako sa Paunawa sa Pagkapribado ng Datos';

  @override
  String get consentAgreeTerms => 'Sumasang-ayon ako sa Mga Tuntunin ng Paggamit';

  @override
  String get consentMustReadFirst => 'Buksan muna ang bawat dokumento.';

  @override
  String get consentContinue => 'Sumang-ayon at magpatuloy';

  @override
  String get legalReadConfirm => 'Nabasa ko na ito';

  @override
  String get legalScrollHint => 'Mag-scroll hanggang dulo para magpatuloy';

  @override
  String get legalClose => 'Isara';

  @override
  String get legalLoadError => 'Hindi mabuksan ang dokumentong ito. Mangyaring i-update ang app o makipag-ugnayan sa inyong tanggapan ng MDRRMO.';

  @override
  String get welcomeTagline => 'Tugon sa emerhensiya para sa Biliran.';

  @override
  String get welcomeSignIn => 'Mag-sign in';

  @override
  String get welcomeCreateAccount => 'Gumawa ng account';

  @override
  String get welcomeHasAccount => 'Rehistrado na?';

  @override
  String get homeOnline => 'Online';

  @override
  String get homeOffline => 'Offline';

  @override
  String get homeConnecting => 'Kumokonekta';

  @override
  String get homeEmergency => 'EMERGENCY';

  @override
  String get categoryFireShort => 'Sunog';

  @override
  String get categoryMedicalShort => 'Medikal';

  @override
  String get categoryCrimeShort => 'Krimen';

  @override
  String get categoryCalamityShort => 'Kalamidad';

  @override
  String get categoryAccidentShort => 'Aksidente';

  @override
  String get categoryOtherShort => 'Iba pa';

  @override
  String get homeLocation => 'Lokasyon';

  @override
  String get homeTimeNow => 'Oras ngayon';

  @override
  String get homeRouting => 'Pagruruta';

  @override
  String homeBarangay(String name) {
    return 'Brgy. $name';
  }

  @override
  String get homeLocationUnknown => 'Hindi pa alam';

  @override
  String get homeRoutingAuto => 'Awtomatiko';

  @override
  String get homeSosHint => 'Hindi tiyak? Pindutin ito';

  @override
  String get homeResidentFallbackName => 'Residente';

  @override
  String get homeMapAction => 'Mapa';

  @override
  String get homeDeliveryOnlineTitle => 'May signal';

  @override
  String get homeDeliveryOnlineDetail => 'Diretso sa pinakamalapit na istasyon ang ulat mo.';

  @override
  String get homeDeliveryOfflineTitle => 'Walang internet';

  @override
  String get homeDeliveryOfflineDetail => 'Hindi maipapadala ang ulat ngayon. Kung emerhensiya ito, tumawag agad sa 911.';

  @override
  String get homeDeliveryCheckingTitle => 'Sinusuri ang koneksyon';

  @override
  String get homeDeliveryCheckingDetail => 'Sinusuri kung maaabot ang server.';

  @override
  String get homeBellLabel => 'Mga abiso';

  @override
  String get homeBellLabelUnread => 'Mga abiso, may bago';

  @override
  String homeReportAction(String category) {
    return 'Mag-ulat ng $category';
  }

  @override
  String get homeAlerts => 'Mga abiso';

  @override
  String get homeAlertsEmpty => 'Walang bagong abiso. Dito lalabas ang update sa mga ulat mo.';

  @override
  String get homeTapToView => 'I-tap para tingnan';

  @override
  String get homeSafePlaces => 'Ligtas na lugar';

  @override
  String get homeStationsUnavailable => 'Hindi pa nakukuha ang listahan ng istasyon.';

  @override
  String homeStationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count istasyon',
      one: '1 istasyon',
    );
    return '$_temp0';
  }

  @override
  String get agencyMdrrmo => 'MDRRMO';

  @override
  String get agencyPnp => 'Pulisya';

  @override
  String get agencyBfp => 'Bumbero';

  @override
  String get homeMyReports => 'Mga ulat mo';

  @override
  String get homeSeeAll => 'Lahat';

  @override
  String get homeNoReportsTitle => 'Wala pa';

  @override
  String get homeNoReportsBody => 'Kapag nag-ulat ka ng insidente, dito mo makikita ang status nito.';

  @override
  String get homeUntitledReport => 'Ulat';

  @override
  String homeGreetingMorning(String name) {
    return 'Magandang umaga, $name!';
  }

  @override
  String homeGreetingAfternoon(String name) {
    return 'Magandang hapon, $name!';
  }

  @override
  String homeGreetingEvening(String name) {
    return 'Magandang gabi, $name!';
  }

  @override
  String get homeStayAlertBody => 'Manatiling alerto. Laging malapit ang tulong.';

  @override
  String get homeReportCtaTitle => 'Mag-ulat ng Emergency';

  @override
  String get homeReportCtaSubtitle => 'Ang pinakamabilis na paraan para makahingi ng tulong — piliin ang klase ng emergency, hawakan para ipadala';

  @override
  String get homeReportCtaBadge => 'PINAKAMABILIS';

  @override
  String get homeRecentActivity => 'Kamakailang aktibidad';

  @override
  String get timeAgoJustNow => 'ngayon lang';

  @override
  String timeAgoMinutes(int count) {
    return '${count}m ang nakaraan';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h ang nakaraan';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}d ang nakaraan';
  }

  @override
  String get loginTitle => 'Mag-sign in';

  @override
  String get loginSubtitle => 'Mag-ulat ng emerhensiya, o tumugon dito.';

  @override
  String get fieldEmail => 'Email address';

  @override
  String get hintEmail => 'ikaw@halimbawa.com';

  @override
  String get fieldPassword => 'Password';

  @override
  String get hintPassword => 'Ilagay ang inyong password';

  @override
  String get validationPasswordRequired => 'Kailangan ang password.';

  @override
  String get loginForgotPassword => 'Nakalimutan ang password?';

  @override
  String get loginButton => 'Mag-sign in';

  @override
  String get loginNewToZiren => 'Bago sa Ziren?';

  @override
  String get loginCreateAccount => 'Gumawa ng account';

  @override
  String get regHaveAccount => 'May account ka na?';

  @override
  String get authLegalIntro => 'Sa pagpapatuloy, sumasang-ayon ka sa';

  @override
  String get authLegalAnd => 'at';

  @override
  String get actionClose => 'Isara';

  @override
  String get forgotSendLink => 'Ipadala ang reset link';

  @override
  String get forgotBackToSignIn => 'Bumalik sa sign in';

  @override
  String get forgotSentBody => 'Kung may account para sa email na iyon, naipadala na ang link para mag-reset ng password.';

  @override
  String get pendingTitle => 'Naghihintay ng approval ang account';

  @override
  String get pendingBody => 'Nagawa na ang inyong Responder account at naghihintay ng beripikasyon mula sa inyong Agency Admin.';

  @override
  String get pendingStep1 => 'Susuriin ng inyong Agency Admin ang inyong badge ID';

  @override
  String get pendingStep2 => 'Ikukumpara nila ito sa talaan ng ahensiya';

  @override
  String get pendingStep3 => 'Aabisuhan kayo agad kapag naaprubahan na ang account';

  @override
  String get rejectedTitle => 'Hindi naaprubahan ang account';

  @override
  String get rejectedBody => 'Hindi inaprubahan ng inyong Agency Admin ang inyong Responder account. Kadalasan ang dahilan ay badge ID na hindi matugma sa talaan ng ahensiya.';

  @override
  String get rejectedStep1 => 'Makipag-ugnayan nang direkta sa inyong ahensiya para makumpirma ang badge ID';

  @override
  String get rejectedStep2 => 'Hilingin sa inyong Agency Admin na suriing muli ang account';

  @override
  String get pendingWhatNext => 'Ano ang susunod';

  @override
  String get actionLogOut => 'Mag-log out';

  @override
  String get navHome => 'Home';

  @override
  String get navReports => 'Mga Ulat';

  @override
  String get navZirenAi => 'Ziren AI';

  @override
  String get navMap => 'Mapa';

  @override
  String get navProfile => 'Profile';

  @override
  String get forgotTitle => 'I-reset ang password';

  @override
  String get forgotSentTitle => 'Tingnan ang inyong email';

  @override
  String get forgotSubtitle => 'Ilagay ang inyong email address at ipapadalhan namin kayo ng link para makagawa ng bago.';

  @override
  String get regRoleTitle => 'Gumawa ng account';

  @override
  String get regRoleSubtitle => 'Alin sa mga ito kayo?';

  @override
  String get roleResident => 'Residente';

  @override
  String get roleResponder => 'Responder';

  @override
  String get regRoleResidentBody => 'Mag-ulat ng emerhensiya sa lugar ninyo, at subaybayan ang nangyari sa ulat ninyo.';

  @override
  String get regRoleResponderBody => 'BFP, PNP o MDRRMO. Aaprubahan muna ng inyong Agency Admin ang account bago ninyo ito magamit.';

  @override
  String get regNameTitle => 'Ang pangalan ninyo';

  @override
  String get regNameSubtitle => 'Ilagay ito nang eksakto tulad ng nasa inyong ID.';

  @override
  String get fieldFirstName => 'Pangalan';

  @override
  String get hintFirstName => 'Juan';

  @override
  String get fieldMiddleName => 'Gitnang pangalan';

  @override
  String get hintMiddleName => 'Santos';

  @override
  String get fieldLastName => 'Apelyido';

  @override
  String get hintLastName => 'dela Cruz';

  @override
  String get fieldSuffix => 'Suffix';

  @override
  String get hintSuffix => 'Jr, Sr, III';

  @override
  String get fieldDateOfBirth => 'Petsa ng kapanganakan';

  @override
  String get regChooseDob => 'Piliin ang petsa ng inyong kapanganakan';

  @override
  String get regDobWhy => 'Magkaiba ang pagtrato ng crew sa 3-taong-gulang at 40-taong-gulang kahit pareho ang sintomas.';

  @override
  String get fieldSex => 'Kasarian';

  @override
  String get sexMale => 'Lalaki';

  @override
  String get sexFemale => 'Babae';

  @override
  String get sexPreferNotToSay => 'Ayaw sabihin';

  @override
  String get regAddressTitle => 'Saan kayo nakatira';

  @override
  String get regAddressSubtitle => 'Ito ang magpapasya kung aling istasyon ang tutugon sa inyo.';

  @override
  String get fieldMunicipality => 'Munisipalidad';

  @override
  String get hintMunicipality => 'Piliin ang inyong munisipalidad';

  @override
  String get fieldBarangay => 'Barangay';

  @override
  String get fieldPurok => 'Purok o sitio';

  @override
  String get hintPurok => 'Purok 3';

  @override
  String get fieldStreet => 'Kalye o palatandaan';

  @override
  String get hintStreet => 'Rizal St, katabi ng kapilya';

  @override
  String get regStreetHelp => 'Ang makakatulong sa crew na makita ang pinto ninyo';

  @override
  String get regChooseMunicipalityFirst => 'Pumili muna ng munisipalidad';

  @override
  String get hintBarangay => 'Piliin ang inyong barangay';

  @override
  String get regUseMyLocation => 'Gamitin ang lokasyon ko';

  @override
  String get regFindingYou => 'Hinahanap kayo...';

  @override
  String get regLocationDenied => 'Tinanggihan ang pahintulot sa lokasyon.';

  @override
  String get regLocationSet => 'Nakuha ang munisipalidad mula sa lokasyon ninyo.';

  @override
  String get regLocationFailed => 'Hindi nabasa ang lokasyon ninyo. Piliin ito sa ibaba.';

  @override
  String get regNotInBiliran => 'Mukhang wala kayo sa Biliran ngayon. Piliin ang munisipalidad ninyo sa ibaba.';

  @override
  String get regBarangayListFailed => 'Hindi na-load ang listahan ng barangay. Tingnan ang koneksyon ninyo.';

  @override
  String get actionRetry => 'Subukan ulit';

  @override
  String get regContactTitle => 'Paano kayo makokontak';

  @override
  String get regContactSubtitle => 'Baka kailanganin kayong tawagan ng responder habang papunta.';

  @override
  String get fieldMobile => 'Numero ng cellphone';

  @override
  String get hintMobile => '09XX XXX XXXX';

  @override
  String get hintCreatePassword => 'Gumawa ng password';

  @override
  String get passwordRule => 'Hindi bababa sa 8 karakter, 1 malaking titik, 1 numero';

  @override
  String get passwordReqTitle => 'Ang password ay dapat may:';

  @override
  String passwordReqLength(int count) {
    return 'Hindi bababa sa $count character';
  }

  @override
  String get passwordReqUpper => '1 malaking titik (A-Z)';

  @override
  String get passwordReqNumber => '1 numero (0-9)';

  @override
  String get passwordConfirmHint => 'Ilagay muli ang parehong password.';

  @override
  String get fieldConfirmPassword => 'Kumpirmahin ang password';

  @override
  String get hintConfirmPassword => 'Ilagay muli ang password';

  @override
  String get fieldEmergencyContact => 'Emergency contact';

  @override
  String get hintName => 'Pangalan';

  @override
  String get hintTheirMobile => 'Numero nila';

  @override
  String get regEmergencyWhoTitle => 'Taong tatawagan sa oras ng emergency';

  @override
  String get regEmergencyWhoBody => 'Maglagay ng ISANG ibang tao na maaari naming tawagan kung may mangyari SA INYO — halimbawa magulang, asawa, kapatid, o malapit na kaibigan. Ilagay ang PANGALAN AT NUMERO NILA, hindi ang inyo. Maaari itong laktawan.';

  @override
  String get hintEmergencyName => 'Buong pangalan nila (hindi sa inyo)';

  @override
  String get hintEmergencyNumber => 'Mobile number nila (hindi sa inyo)';

  @override
  String get regEmergencyNeedsNumber => 'Ilagay din ang mobile number nila, o burahin ang pangalan.';

  @override
  String get regEmergencyNeedsName => 'Ilagay din ang pangalan nila, o burahin ang numero.';

  @override
  String get regEmergencySameAsYours => 'Sarili ninyong numero ito. Ilagay ang numero ng ibang tao — ang taong tatawagan namin tungkol sa inyo.';

  @override
  String get emergencyWhoShort => 'Ang taong tatawagan namin kung may mangyari SA INYO — kapamilya, kaibigan, o taong pinagkakatiwalaan. Ilagay ang PANGALAN AT NUMERO NILA, hindi ang inyo.';

  @override
  String get hintPwdId => 'PWD ID number';

  @override
  String get pwdIdHelp => 'Galing sa inyong MSWDO o PDAO - patunay din ito ng paninirahan';

  @override
  String get hintAccessibilityNotes => 'Iba pang makakatulong (opsyonal)';

  @override
  String get contactModeAny => 'Kahit paano';

  @override
  String get contactModeSms => 'Text lang';

  @override
  String get contactModeApp => 'Sa app lang';

  @override
  String get contactModeVoice => 'Pwedeng tawagan';

  @override
  String get regIsPwd => 'Ako ay person with disability';

  @override
  String get regAccessibility => 'Accessibility';

  @override
  String get regAccessibilityWhy => 'Para handa ang crew pagdating. Opsyonal.';

  @override
  String get regAccessibilityAsk => 'Ano ang dapat malaman ng crew bago sila dumating?';

  @override
  String get regContactModeAsk => 'Paano namin kayo kokontakin?';

  @override
  String get regAgencyTitle => 'Ang ahensiya ninyo';

  @override
  String get regAgencySubtitle => 'Susuriin ito ng inyong Agency Admin bago kayo aprubahan.';

  @override
  String get fieldAgency => 'Ahensiya';

  @override
  String get fieldBadgeId => 'Badge o employee ID';

  @override
  String get hintBadgeId => 'Ayon sa ibinigay ng inyong ahensiya';

  @override
  String get fieldRank => 'Ranggo o posisyon';

  @override
  String get hintRank => 'SFO1, PCpl, Rescue Team Leader';

  @override
  String get fieldUnit => 'Unit o istasyon';

  @override
  String get hintUnit => 'Naval Fire Station';

  @override
  String get fieldDateJoined => 'Petsa ng pagsali';

  @override
  String get fieldAgencyIdPhoto => 'Larawan ng inyong agency ID';

  @override
  String get regTakeAgencyIdPhoto => 'Kunan ng larawan ang inyong agency ID';

  @override
  String get regChooseDate => 'Pumili ng petsa';

  @override
  String get regAgencyIdWhy => 'Kailangan ito. Titingnan ng admin ninyo na iyo ang pangalan dito bago aprubahan ang account mo.';

  @override
  String get regIdBestChoice => 'Pinakamainam';

  @override
  String get regIdProvesResidency => 'Patunay din na nakatira kayo sa Biliran';

  @override
  String get regIdAlsoAccepted => 'Tinatanggap din';

  @override
  String get regIdIdentityOnly => 'Patunay kung sino kayo, pero hindi kung saan kayo nakatira';

  @override
  String get actionChooseFromGallery => 'Pumili mula sa gallery';

  @override
  String get regIdCaptureTitle => 'Kunan ng larawan ang inyong ID';

  @override
  String get fieldIdNumber => 'ID number';

  @override
  String get hintIdNumber => 'Ayon sa nakalimbag sa card';

  @override
  String get regReadingId => 'Binabasa ang inyong ID...';

  @override
  String get regOcrFilled => 'Nakuha mula sa larawan ninyo - itama kung mali';

  @override
  String get regIdPrivacyNote => 'Pribado ang larawang ito. Hindi ito ipinapakita sa publiko, hindi nakikita ng mga responder, at buburahin kapag nasuri na ng administrator.';

  @override
  String get regIdUnreadable => 'Kaunti lang ang nabasa namin sa larawang iyon. Pwede pa rin kayong magpatuloy - i-type na lang ang numero sa ibaba. Nakakatulong ang mas malinaw na larawan.';

  @override
  String get actionRetake => 'Kunan ulit';

  @override
  String get actionTryAgain => 'Subukan ulit';

  @override
  String get actionTakePhotoShort => 'Kumuha ng larawan';

  @override
  String get selfieFramingNone => 'Ilagay ang mukha ninyo sa loob ng bilog';

  @override
  String get selfieFramingMultiple => 'Isang mukha lang po';

  @override
  String get selfieFramingTooFar => 'Lumapit nang kaunti';

  @override
  String get selfieFramingTooClose => 'Umatras nang kaunti';

  @override
  String get selfieFramingOffCentre => 'Igitna ang mukha ninyo';

  @override
  String get selfieAutoCapture => 'Kusa naming kukunan ang larawan pagkatapos ninyo.';

  @override
  String get selfieOrManual => 'O kunan ninyo mismo ang larawan.';

  @override
  String get selfieTitle => 'Kumuha ng selfie';

  @override
  String get selfieReviewTitle => 'Kumusta ang hitsura nito?';

  @override
  String get selfieSubtitle => 'Para maitugma ng administrator ang mukha ninyo sa inyong ID.';

  @override
  String get selfieReviewSubtitle => 'Tiyaking malinaw at maliwanag ang mukha ninyo.';

  @override
  String get selfieCameraError => 'Hindi mabuksan ang camera. Tingnan kung may pahintulot ang Ziren sa camera sa settings ng telepono.';

  @override
  String get selfieCaptureError => 'Hindi nakuha ang larawan. Pakisubukan ulit.';

  @override
  String get regReviewTitle => 'Suriin ang inyong detalye';

  @override
  String get regReviewSubtitle => 'I-tap ang kahit ano para baguhin.';

  @override
  String get regGroupAboutYou => 'Tungkol sa inyo';

  @override
  String get regGroupAddress => 'Saan kayo nakatira';

  @override
  String get regGroupContact => 'Kontak';

  @override
  String get regGroupAgency => 'Ahensiya';

  @override
  String get regGroupIdentity => 'Pagkakakilanlan';

  @override
  String get actionChange => 'Palitan';

  @override
  String get regReenterPassword => 'Ilagay muli ang password';

  @override
  String get hintYourPassword => 'Ang password ninyo';

  @override
  String get regVerifyNowInstead => 'Mag-verify na lang ngayon';

  @override
  String get regVerificationSkipped => 'Nilaktawan ang beripikasyon';

  @override
  String get valueNotGiven => 'Hindi ibinigay';

  @override
  String get valueAttached => 'Nakakabit';

  @override
  String get labelName => 'Pangalan';

  @override
  String get labelDateOfBirth => 'Petsa ng kapanganakan';

  @override
  String get labelSex => 'Kasarian';

  @override
  String get labelMunicipality => 'Munisipalidad';

  @override
  String get labelBarangay => 'Barangay';

  @override
  String get labelPurok => 'Purok o sitio';

  @override
  String get labelStreet => 'Kalye';

  @override
  String get labelEmail => 'Email';

  @override
  String get labelMobile => 'Cellphone';

  @override
  String get labelEmergencyContact => 'Emergency contact';

  @override
  String get labelAccessibility => 'Accessibility';

  @override
  String get labelBadgeId => 'Badge ID';

  @override
  String get labelRank => 'Ranggo';

  @override
  String get labelUnit => 'Unit';

  @override
  String get labelAgencyIdPhoto => 'Larawan ng agency ID';

  @override
  String get labelIdType => 'Uri ng ID';

  @override
  String get labelIdNumber => 'ID number';

  @override
  String get labelIdPhoto => 'Larawan ng ID';

  @override
  String get regSelfieAttached => 'Nakakabit ang selfie para sa pagsusuri ng pagkakakilanlan.';

  @override
  String get regSkippedNotice => 'Gagana agad ang account ninyo at makakapag-ulat kayo ng emerhensiya. Tapusin ang beripikasyon mamaya sa inyong profile.';

  @override
  String get regSkipDialogTitle => 'Laktawan muna ang beripikasyon?';

  @override
  String get actionGoBack => 'Bumalik';

  @override
  String get actionSkipForNow => 'Laktawan muna';

  @override
  String get regSkipDialogBody => 'Magagawa ang account ninyo at makakapag-ulat agad kayo ng emerhensiya.\n\nMakikita ng dispatcher na hindi pa nasusuri ang pagkakakilanlan ninyo. Matatapos ninyo ito anumang oras sa inyong profile.';

  @override
  String get regSkipLink => 'Kailangan ko ng tulong ngayon - laktawan ito';

  @override
  String get profilePersonalInfo => 'Personal na Impormasyon';

  @override
  String get labelNameProfile => 'Pangalan';

  @override
  String get labelEmailProfile => 'Email';

  @override
  String get labelPhone => 'Telepono';

  @override
  String get profileAddress => 'Tirahan';

  @override
  String get labelBarangayProfile => 'Barangay';

  @override
  String get labelMunicipalityProfile => 'Munisipalidad';

  @override
  String get profileAccount => 'Account';

  @override
  String get labelRole => 'Tungkulin';

  @override
  String get labelStatus => 'Katayuan';

  @override
  String get profileEmergencyContact => 'Emergency Contact';

  @override
  String get labelNumber => 'Numero';

  @override
  String get profileNotSet => 'Wala pang naitakda';

  @override
  String get labelEmergencyContactName => 'Pangalan ng contact';

  @override
  String get labelEmergencyContactNumber => 'Numero ng contact';

  @override
  String get profileAccountVerified => 'Verified na ang account mo';

  @override
  String get profileAccountVerifiedBody => 'Na-confirm na ang identity mo. May priority support ka tuwing may emergency.';

  @override
  String get profileVerifyLearnMore => 'Alamin pa';

  @override
  String profileStaleWarning(String message) {
    return 'Maaaring luma na ang mga detalye sa ibaba.';
  }

  @override
  String get actionRetryProfile => 'Subukan ulit';

  @override
  String get settingsProfile => 'Profile';

  @override
  String get fieldFullName => 'Buong Pangalan';

  @override
  String get fieldMobileNumber => 'Numero ng Cellphone';

  @override
  String get hintMobileShort => '09xxxxxxxxx';

  @override
  String get settingsAddress => 'Tirahan';

  @override
  String get fieldBarangaySettings => 'Barangay';

  @override
  String get hintBarangayExample => 'hal. Brgy. Caraycaray';

  @override
  String get fieldMunicipalitySettings => 'Munisipalidad';

  @override
  String get hintMunicipalityExample => 'hal. Naval';

  @override
  String get settingsPreferences => 'Mga Kagustuhan';

  @override
  String get settingsEmergencyContact => 'Emergency Contact';

  @override
  String get fieldContactName => 'Pangalan ng taong tatawagan';

  @override
  String get hintContactName => 'Buong pangalan nila, hal. Maria Santos';

  @override
  String get fieldContactNumber => 'Numero ng taong tatawagan';

  @override
  String get verifyWhichId => 'Aling ID ang ipapakita ninyo?';

  @override
  String get verifyIdPhoto => 'Larawan ng ID';

  @override
  String get verifyIdNumber => 'ID number';

  @override
  String get verifySelfie => 'Selfie';

  @override
  String get verifySubmit => 'Ipasa para suriin';

  @override
  String get actionDone => 'Tapos na';

  @override
  String get verifyTitle => 'I-verify ang inyong account';

  @override
  String get verifyChooseId => 'Pumili ng ID';

  @override
  String get verifyTakeIdPhoto => 'Kunan ng larawan ang inyong ID';

  @override
  String get verifyTakeSelfie => 'Kumuha ng selfie';

  @override
  String get verifySentTitle => 'Naipasa na para suriin';

  @override
  String get verifyNotSignedIn => 'Hindi kayo naka-sign in.';

  @override
  String get verifyIntro => 'Ang mga residenteng na-verify ng administrator lang ang makakapagpadala ng report. Ipakita ang valid ID na may pangalan mo at kumuha ng selfie - pinaghahambing ito ng administrator.';

  @override
  String get verifySentBody => 'Susuriin ng administrator ang ID mo. Makakapagpadala ka na ng report kapag naaprubahan ito. Kung may emergency ngayon, tumawag sa hotline.';

  @override
  String get verifyPrivacyNote => 'Pribado ang mga larawan ninyo at hindi ipinapakita sa mga responder. Buburahin ang larawan ng ID kapag nasuri na ng administrator; itatago ang selfie bilang larawan sa inyong Ziren ID.';

  @override
  String get bannerInReview => 'Sinusuri ang beripikasyon';

  @override
  String get bannerFinishVerifying => 'Tapusin ang beripikasyon ng account';

  @override
  String get bannerVerifyNow => 'Mag-verify na';

  @override
  String get bannerNotNow => 'Mamaya na lang';

  @override
  String get bannerInReviewBody => 'Sinusuri ng administrator ang iyong ID. Makakapag-ulat ka kapag naaprubahan na ito. Kung may emergency, tumawag agad sa hotline.';

  @override
  String get bannerFinishBody => 'Idagdag ang iyong balidong ID at selfie. Makakapag-ulat ka kapag na-verify na ng administrator ang account mo. Kung may emergency, tumawag agad sa hotline.';

  @override
  String get badgeRequired => 'KAILANGAN';

  @override
  String get badgeOptional => 'OPSYONAL';

  @override
  String get badgeAuto => 'AUTO';

  @override
  String get reportTitle => 'I-ulat ang Emergency';

  @override
  String get reportSectionWhat => 'ANO - Uri ng Emergency';

  @override
  String get reportExtraDetails => 'Dagdag na detalye';

  @override
  String get reportSectionHow => 'PAANO - Mga Detalye';

  @override
  String get reportOverlapQuestion => 'May kasama pa bang alalahanin?';

  @override
  String get reportSelectAllApply => 'Piliin lahat ng naaangkop';

  @override
  String get reportLocation => 'Lokasyon';

  @override
  String get reportNoGps => 'Walang GPS - maipapadala nang wala ito';

  @override
  String get reportFindingLocation => 'Hinahanap ang lokasyon...';

  @override
  String get reportGpsAcquired => 'GPS nakuha';

  @override
  String get reportFindingAddress => 'Hinahanap ang address...';

  @override
  String get reviewTitle => 'I-review ang ulat';

  @override
  String get reviewTypeOfEmergency => 'URI NG EMERGENCY';

  @override
  String get reviewDetails => 'MGA DETALYE';

  @override
  String get reviewAlsoInvolved => 'KASAMA RING ALALAHANIN';

  @override
  String get reviewLocation => 'LOKASYON';

  @override
  String get reviewRelationship => 'RELASYON SA BIKTIMA';

  @override
  String get reviewExtraDetails => 'DAGDAG NA DETALYE';

  @override
  String get reviewNoGps => 'GPS hindi available';

  @override
  String get reviewFalseReportWarning => 'Ang pag-file ng maling ulat ay may kasamang legal na parusa. Tiyakin na tama ang lahat ng impormasyon.';

  @override
  String get reviewSubmit => 'Isumite ang Ulat';

  @override
  String get actionEdit => 'Baguhin';

  @override
  String get reviewTakePhoto => 'Kumuha ng larawan';

  @override
  String get quickIncident => 'Insidente';

  @override
  String get quickReport => 'Mag-ulat';

  @override
  String get quickYourLocation => 'Lokasyon mo';

  @override
  String quickSentTo(String station) {
    return 'Naipadala ang ulat sa $station.';
  }

  @override
  String quickGpsPrecise(int meters) {
    return 'Tumpak ang GPS (±$meters m)';
  }

  @override
  String quickGpsVague(int meters) {
    return 'Malabo ang GPS (±$meters m) — maaaring hindi ito ang eksaktong kinaroroonan mo.';
  }

  @override
  String get quickNoteHint => 'Hal. may naipit sa loob';

  @override
  String get quickSendReport => 'Ipadala ang ulat';

  @override
  String get quickSendWarning => 'Padadalhan nito ng tunay na tawag ang istasyon. Ang pekeng ulat ay may kaukulang parusa.';

  @override
  String get quickLocationOff => 'Naka-off ang location. Ipapadala pa rin ang ulat, pero kailangang tanungin ka ng dispatcher kung nasaan ka.';

  @override
  String get quickSearching => 'Hinahanap...';

  @override
  String get quickCoordinatesFound => 'Nakuha ang koordinasyon';

  @override
  String get quickReceivingStation => 'Istasyong tatanggap';

  @override
  String get quickLoadingStations => 'Kinukuha ang listahan...';

  @override
  String get quickStationUnknown => 'Hindi pa matukoy - kailangan ng lokasyon.';

  @override
  String get quickStationAuto => 'Awtomatikong itatalaga batay sa iyong lokasyon';

  @override
  String get quickLandmark => 'Landmark (opsyonal)';

  @override
  String get quickLandmarkHelp => 'Ano ang katabi o malapit? Ito ang hahanapin ng responder.';

  @override
  String get quickLandmarkHint => 'Hal. katabi ng barangay hall';

  @override
  String quickVoiceOnlyReportText(String category) {
    return '$category — iniulat sa pamamagitan ng boses';
  }

  @override
  String quickNoDetailsReportText(String category) {
    return '$category — walang karagdagang detalye';
  }

  @override
  String quickFlowTitle(String category) {
    return 'Mag-ulat ng $category';
  }

  @override
  String get quickHelpSubtitle => 'Tutulong ito para makarating ang tamang koponan sa tamang lugar.';

  @override
  String get quickYourLocationAuto => 'Lokasyon mo (auto-detect)';

  @override
  String quickAccuracy(int meters) {
    return 'Katumpakan: ±$meters m';
  }

  @override
  String get quickDescribeWhatHappened => 'Ilarawan ang nangyari';

  @override
  String get quickOrTypeMessage => 'O i-type ang mensahe mo (opsyonal)';

  @override
  String get quickAttachPhotoVideo => 'Maglagay ng larawan o video (opsyonal)';

  @override
  String get quickMediaHint => 'Litrato o video bilang ebidensya: hanggang 5 file, 50 MB bawat isa, video na hanggang 2 minuto.';

  @override
  String get quickTakePhoto => 'Kumuha ng litrato';

  @override
  String get quickRecordVideo => 'Mag-record ng video';

  @override
  String get quickChooseFromGallery => 'Pumili mula sa gallery';

  @override
  String get quickAddPhoto => 'Maglagay ng litrato o video';

  @override
  String get quickReviewReportAction => 'I-review ang ulat';

  @override
  String get quickReviewWarning => 'Sa pagpapadala nito, gumagawa ka ng tunay na emergency report. Maging seryoso at tumpak.';

  @override
  String get quickReviewTitle => 'I-review ang ulat';

  @override
  String get quickReviewCareful => 'Pakisuri mabuti ang iyong ulat.';

  @override
  String quickReviewWillSendTo(String agency) {
    return 'Ipapadala ito sa pinakamalapit na istasyon ng $agency.';
  }

  @override
  String get quickReviewDescription => 'Paglalarawan';

  @override
  String get quickReviewPhoto => 'Litrato';

  @override
  String quickReviewAttachedCount(int count) {
    return '$count nakalakip';
  }

  @override
  String get quickReviewReceivingAgency => 'Tatanggap na ahensya';

  @override
  String quickReviewAway(String km) {
    return '$km km ang layo';
  }

  @override
  String get quickReviewVoiceRecording => 'Recording ng boses';

  @override
  String get quickReviewAttached => 'Nakalakip';

  @override
  String get categoryQuestion => 'Anong uri ng emergency?';

  @override
  String get categoryHelp => 'Piliin ang pinakamalapit na kategorya';

  @override
  String get whoTitle => 'Sino at saan?';

  @override
  String get whoRelationship => 'Ano ang relasyon mo sa biktima?';

  @override
  String get whoLocation => 'Lokasyon';

  @override
  String get whoLandmark => 'Landmark o tanda ng lugar (opsyonal)';

  @override
  String get whoLandmarkHint => 'Halimbawa: Malapit sa simbahan, katabi ng palengke...';

  @override
  String get overlapTitle => 'May kasama pa bang...';

  @override
  String get overlapHelp => 'Piliin lahat ng naaangkop - makakatulong ito para maabisuhan ang tamang ahensya.';

  @override
  String get stationPickTitle => 'Pumili ng Istasyon';

  @override
  String get actionTryAgainStation => 'Subukan ulit';

  @override
  String get stationNoneAvailable => 'Walang available na istasyon.';

  @override
  String get stationPickHelp => 'I-tap ang istasyon na tatanggap ng iyong ulat.';

  @override
  String get qFireMaterial => 'Ano ang nasusunog?';

  @override
  String get qFireSpreading => 'Kumakalat pa ba?';

  @override
  String get qFireInjured => 'May nasugatan o nakulong?';

  @override
  String get qFireRoadBlocked => 'Nakaharang sa daan ang sunog?';

  @override
  String get qMedType => 'Uri ng emergency?';

  @override
  String get qMedVictimCount => 'Ilang biktima?';

  @override
  String get qMedBleeding => 'May dugo o matinding sugat?';

  @override
  String get qMedConscious => 'Gising ba ang biktima?';

  @override
  String get qVehType => 'Anong sasakyan?';

  @override
  String get qVehInjured => 'May nasugatan?';

  @override
  String get qVehRoadBlocked => 'Nakaharang ba sa daan?';

  @override
  String get qCalType => 'Uri ng kalamidad?';

  @override
  String get qCalAffected => 'Ilang pamilya ang apektado?';

  @override
  String get qCalRoadCut => 'Naputol ba ang daan?';

  @override
  String get qCalEvacuation => 'Kailangan ng evacuation?';

  @override
  String get qCrimeType => 'Uri ng insidente?';

  @override
  String get qCrimeWeapon => 'May armas?';

  @override
  String get qCrimeOngoing => 'Nangyayari pa ba ngayon?';

  @override
  String get ansYes => 'Oo';

  @override
  String get ansNo => 'Hindi';

  @override
  String get ansNone => 'Wala';

  @override
  String get ansDontKnow => 'Hindi ko alam';

  @override
  String get ansOther => 'Iba pa';

  @override
  String get ansHouse => 'Bahay';

  @override
  String get ansVehicle => 'Sasakyan';

  @override
  String get ansForestField => 'Kagubatan / Bukid';

  @override
  String get ansBuildingWarehouse => 'Gusali / Bodega';

  @override
  String get ansYesSpreading => 'Oo, kumakalat';

  @override
  String get ansNoControlled => 'Hindi, kontrolado na';

  @override
  String get ansAccident => 'Aksidente';

  @override
  String get ansHeartAttackStroke => 'Atake sa puso / Stroke';

  @override
  String get ansSeizure => 'Pagtatayo / Seizure';

  @override
  String get ansTroubleBreathing => 'Hirap huminga';

  @override
  String get ansOne => '1';

  @override
  String get ansTwoToFive => '2–5';

  @override
  String get ansMoreThanFive => 'Higit sa 5';

  @override
  String get ansYesConscious => 'Oo, gising';

  @override
  String get ansNoUnconscious => 'Hindi, nawalan ng malay';

  @override
  String get ansMotorcycle => 'Motor';

  @override
  String get ansCarSuv => 'Sasakyan / SUV';

  @override
  String get ansBusTruck => 'Bus / Truck';

  @override
  String get ansTricycleEbike => 'Tatlong-gulong / E-bike';

  @override
  String get ansYesBlocked => 'Oo, nakabara';

  @override
  String get ansPartly => 'Bahagya';

  @override
  String get ansFlood => 'Baha';

  @override
  String get ansLandslide => 'Landslide';

  @override
  String get ansStorm => 'Bagyo';

  @override
  String get ansEarthquake => 'Lindol';

  @override
  String get ansOneToFive => '1–5';

  @override
  String get ansSixToTwenty => '6–20';

  @override
  String get ansMoreThanTwenty => 'Higit sa 20';

  @override
  String get ansYesUrgent => 'Oo, urgent';

  @override
  String get ansPossibly => 'Posible';

  @override
  String get ansNotYetNeeded => 'Hindi pa kailangan';

  @override
  String get ansFightDisturbance => 'Awayan / Kaguluhan';

  @override
  String get ansTheftHoldup => 'Pagnanakaw / Holdap';

  @override
  String get ansPhysicalAssault => 'Pambubugbog';

  @override
  String get ansArmed => 'May armas';

  @override
  String get ansYesOngoing => 'Oo, nangyayari pa';

  @override
  String get ansItIsOver => 'Tapos na';

  @override
  String get qExtraDetails => 'Dagdag na detalye (opsyonal)';

  @override
  String get sosAppBarTitle => 'SOS - Ulat ng Emerhensiya';

  @override
  String get sosHeading => 'Emergency SOS';

  @override
  String get sosIntro => 'Ipapadala ang inyong pagkakakilanlan at lokasyon sa pinakamalapit na istasyon.';

  @override
  String get sosLocating => 'Tinutukoy ang lokasyon ninyo...';

  @override
  String get sosStationAuto => 'Awtomatikong matutukoy ang pinakamalapit na istasyon.';

  @override
  String get sosLocationUnavailable => 'Walang makuhang lokasyon';

  @override
  String get sosNoGpsBody => 'Ipapadala ang SOS ninyo nang walang GPS. Iruruta ito ng server sa pinakamalapit na istasyon sa Naval.';

  @override
  String get sosLocationCaptured => 'Nakuha ang lokasyon';

  @override
  String get sosBriefDescription => 'Maikling paglalarawan (opsyonal)';

  @override
  String get sosLegalWarning => 'Babala sa Batas';

  @override
  String get sosLegalBody => 'Ang pagpapadala ng pekeng ulat ng emerhensiya ay may kaukulang parusa sa ilalim ng batas ng Pilipinas (RA 10175, mga lokal na ordinansa). Ang buo mong pagkakakilanlan at lokasyon ay permanenteng nakakabit sa ulat na ito. Ang paulit-ulit na pekeng ulat ay magreresulta sa pagsuspinde ng iyong SOS at pag-endorso sa mga lokal na awtoridad.';

  @override
  String get sosTruthConfirm => 'Nauunawaan ko na tunay ang emerhensiyang ito at kinukumpirma kong totoo ang aking ulat.';

  @override
  String get sosSendNow => 'Ipadala ang SOS Ngayon';

  @override
  String sosCooldownWarning(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'May naipadala kang SOS kamakailan. Maghintay ng $minutes minuto bago magpadala ulit. Kung tuloy-tuloy ang emerhensiya, tumawag agad sa 911.',
      one: 'May naipadala kang SOS kamakailan. Maghintay ng 1 minuto bago magpadala ulit. Kung tuloy-tuloy ang emerhensiya, tumawag agad sa 911.',
    );
    return '$_temp0';
  }

  @override
  String get sosSentTitle => 'Naipadala ang SOS';

  @override
  String get sosSentBody => 'Natanggap na ang inyong ulat at sinusuri na ito ng dispatcher.';

  @override
  String get actionBackToHome => 'Bumalik sa Home';

  @override
  String get sosWorsensNote => 'Kung lumala ang emerhensiya, tumawag agad sa 911.\nKokontakin kayo ng dispatcher kung kailangan.';

  @override
  String get sosDispatchedTo => 'Ipinadala sa';

  @override
  String get sosAddDetails => 'Magdagdag ng detalye (opsyonal)';

  @override
  String get sosAddDetailsHelp => 'Naipadala na ang SOS ninyo. Kung ligtas kayong makapagbigay ng dagdag na impormasyon (ano ang nangyari, ilang tao ang sangkot, atbp.), makakatulong ito sa dispatcher.';

  @override
  String get actionSkip => 'Laktawan';

  @override
  String get sosSendDetails => 'Ipadala ang Detalye';

  @override
  String get sosDetailsSent => 'Naipadala ang dagdag na detalye. Na-update na ang dispatcher.';

  @override
  String get formSubmittedTitle => 'Naipasa ang Ulat';

  @override
  String get formTrackReport => 'Subaybayan ang Ulat';

  @override
  String get formReportEmergency => 'Mag-ulat ng Emerhensiya';

  @override
  String get formMyReports => 'Mga Ulat Ko';

  @override
  String get actionLogOutForm => 'Mag-log out';

  @override
  String get formDescribe => 'Ilarawan ang emerhensiya';

  @override
  String get formDescribeHint => 'Halimbawa: Sunog sa Brgy. Caraycaray Naval, may nasusunog na bahay, may dalawang tao na nagtatakas...';

  @override
  String get formDescribeRequired => 'Pakilarawan ang emerhensiya.';

  @override
  String get formDescribeTooShort => 'Magbigay ng mas maraming detalye (hindi bababa sa 10 karakter).';

  @override
  String get formSubmit => 'Ipasa ang Ulat ng Emerhensiya';

  @override
  String get formSubmitNote => 'Susuriin ng dispatcher ang ulat na ito. Para sa nakamamatay na emerhensiya, tumawag din sa 911.';

  @override
  String get actionChangeForm => 'Palitan';

  @override
  String get formNoLocation => 'Walang makuhang lokasyon - ipapadala ang ulat nang walang GPS';

  @override
  String get withdrawReport => 'Ilipat sa Basura';

  @override
  String get withdrawConfirmTitle => 'Ilipat ang ulat na ito sa Basura?';

  @override
  String get withdrawConfirmBody => 'Ililipat ito sa Basura at aalisin sa listahan ng dispatcher. Awtomatiko itong buburahin nang tuluyan pagkalipas ng 30 araw sa Basura. Gawin lang ito kung hindi na kailangan ng tulong.';

  @override
  String get withdrawConfirmAction => 'Ilipat sa Basura';

  @override
  String get withdrawCancelAction => 'Huwag bawiin';

  @override
  String get withdrawDone => 'Inilipat sa Basura. Buburahin ito nang tuluyan pagkalipas ng 30 araw.';

  @override
  String get filterTrash => 'Basura';

  @override
  String get noTrashedReports => 'Walang binawi';

  @override
  String get noTrashedReportsBody => 'Ang mga ulat na binawi mo ay lalabas dito. Nananatili silang nakatala, pero walang tumutugon sa mga ito.';

  @override
  String trashDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Mabubura sa loob ng $days na araw',
      one: 'Mabubura sa loob ng 1 araw',
      zero: 'Mabubura ngayong araw',
    );
    return '$_temp0';
  }

  @override
  String get reportDetailsTitle => 'Detalye ng Ulat';

  @override
  String get respTabHome => 'Home';

  @override
  String get respTabStats => 'Stats';

  @override
  String get respTabReports => 'Mga Report';

  @override
  String get respStatToday => 'Ngayon';

  @override
  String get respStatTypical => 'Tugon';

  @override
  String get respTabMap => 'Mapa';

  @override
  String get respTabProfile => 'Profile';

  @override
  String get respStatAssigned => 'Nakatalaga';

  @override
  String get respStatCritical => 'Kritikal';

  @override
  String get respStatOldest => 'Pinakamatagal';

  @override
  String get respHomeGreetingSubtitle => 'Ito ang nasa iyong queue ngayon.';

  @override
  String get respHomeRecentActivity => 'Kamakailang Aktibidad';

  @override
  String get respHomeViewAll => 'Tingnan lahat';

  @override
  String get respHomeQueueTitle => 'Mga nakatalaga sa iyo';

  @override
  String get respHomeAwaitingDispatch => 'Naghihintay ng Dispatch';

  @override
  String get respHomeNoAssignmentsTitle => 'Walang nakatalaga';

  @override
  String get respHomeOffDutyTitle => 'Wala sa duty';

  @override
  String get respHomeQueueClear => 'Malinaw ang queue';

  @override
  String get respHomeNotAccepting => 'Hindi ka tumatanggap';

  @override
  String get respHomeQueueClearBody => 'Wala pang naka-assign sa iyo. Dito lalabas ang bagong tawag.';

  @override
  String get respHomeOffDutyBody => 'Walang ipapadalang assignment habang naka-off duty ka. I-on ang switch sa itaas.';

  @override
  String get respDashTitle => 'Aking dashboard';

  @override
  String get respDashAssigned => 'Nakatalaga';

  @override
  String get respDashCritical => 'Kritikal';

  @override
  String get respDashEnRoute => 'Papunta na';

  @override
  String get respDashOnScene => 'Nasa lugar';

  @override
  String get respDashClosedToday => 'Naisara ngayon';

  @override
  String get respDashTypicalTime => 'Karaniwang oras bago maisara';

  @override
  String get respDashTypicalBody => 'Mula nang ipadala ka, hanggang sa maisara.';

  @override
  String get respHistoryTitle => 'Mga naisara kong insidente';

  @override
  String get respHistoryError => 'Hindi makuha ang iyong history';

  @override
  String get respHistoryEmpty => 'Wala pang naisasara';

  @override
  String get respAccept => 'TATANGGAPIN KO';

  @override
  String get respDecline => 'HINDI KAYA';

  @override
  String get respDeclineLong => 'HINDI MAKAKARESPONDE';

  @override
  String get respAccepted => 'Natanggap mo na ito. Alam na ng dispatcher.';

  @override
  String get respSeconds => 'segundo';

  @override
  String get respOverdue => 'LAGPAS NA';

  @override
  String get respUntriaged => 'HINDI PA NASUSURI';

  @override
  String get respDeclineTitle => 'Hindi makakaresponde?';

  @override
  String get respDeclineSubtitle => 'Babalik ito sa dispatcher kasama ang dahilan mo, para may maipadala silang iba agad.';

  @override
  String get respDeclineNote => 'Dagdag na paliwanag (opsyonal)';

  @override
  String get respDeclineNoteHint => 'Halimbawa: naka-jack ang truck, 30 minuto pa';

  @override
  String get respDeclineSubmit => 'Ibalik sa dispatcher';

  @override
  String get respCloseTitle => 'Ano ang natagpuan ninyo?';

  @override
  String get respCloseCasualties => 'Bilang ng tao';

  @override
  String get respCloseCasualtiesHint => 'Iwanang blangko kung hindi nabilang. Hindi ito kapareho ng zero.';

  @override
  String get respCloseInjured => 'Sugatan';

  @override
  String get respCloseFatal => 'Namatay';

  @override
  String get respCloseTransported => 'Dinala sa ospital';

  @override
  String get respCloseNarrative => 'Maikling salaysay (opsyonal)';

  @override
  String get respCloseNarrativeHint => 'Ano ang nangyari, ano ang ginawa ninyo';

  @override
  String get respCloseSubmit => 'Isara ang insidente';

  @override
  String get respCloseLater => 'Hindi pa — babalikan ko';

  @override
  String get respCount => 'Bilangin';

  @override
  String get respNotCounted => 'Hindi nabilang';

  @override
  String get respClosed => 'Naisara ang insidente. Salamat!';

  @override
  String get respBackupTitle => 'Humingi ng saklolo';

  @override
  String get respBackupSubtitle => 'Gagawa ito ng bagong insidente para sa kanilang dispatcher, naka-ugnay sa tawag na ito. Hindi lang ito mensahe.';

  @override
  String get respBackupNeed => 'Ano ang kailangan? *';

  @override
  String get respBackupNeedHint => 'Halimbawa: 2 sugatan, kailangan ng ambulansya';

  @override
  String get respBackupSubmit => 'Ipadala ang hiling';

  @override
  String get respBackupAction => 'Humingi ng saklolo sa ibang ahensya';

  @override
  String get respDistressTitle => 'Ikaw ba ay nasa panganib?';

  @override
  String get respDistressBody => 'Aalertuhin nito agad ang dispatcher kasama ang kinaroroonan mo.\n\nGamitin ito kung ikaw mismo ang nangangailangan ng tulong.';

  @override
  String get respDistressNo => 'Hindi';

  @override
  String get respDistressYes => 'OO, TULONG';

  @override
  String get respDistressHold => 'PINDUTIN NANG MATAGAL KUNG NASA PANGANIB KA';

  @override
  String get respDistressHoldBody => 'Para sa sarili mong kaligtasan, hindi sa insidente';

  @override
  String get respDistressSemantics => 'Distress signal. Pindutin nang matagal para ipadala.';

  @override
  String get respNavTitle => 'Papunta sa lugar';

  @override
  String get respNavLocating => 'Hinahanap ang kinaroroonan mo...';

  @override
  String get respNavStraightLine => 'Diretsong linya ito, hindi daan. Sundin pa rin ang aktwal na kalsada.';

  @override
  String get respNavExternal => 'Buksan sa Google Maps para sa daan';

  @override
  String get respNavNoMapsApp => 'Walang mabuksang maps app sa telepono na ito.';

  @override
  String get respNavStraightDistance => 'diretsong distansya';

  @override
  String get respNavClose => 'malapit na';

  @override
  String get respIncident => 'Insidente';

  @override
  String get respSectionReport => 'ULAT NG INSIDENTE';

  @override
  String get respSectionLocation => 'LOKASYON';

  @override
  String get respSectionReporter => 'NAG-ULAT';

  @override
  String get respSectionStation => 'ISTASYON';

  @override
  String get respFieldCategory => 'Kategorya';

  @override
  String get respFieldAddress => 'Address';

  @override
  String get respFieldLandmark => 'Palatandaan';

  @override
  String get respFieldGps => 'GPS';

  @override
  String get respFieldName => 'Pangalan';

  @override
  String get respFieldPhone => 'Numero';

  @override
  String get respFieldStation => 'Istasyon';

  @override
  String get respFieldEmergencyContact => 'Emergency Contact';

  @override
  String get respFieldContactNumber => 'Numero ng Contact';

  @override
  String get respNavigate => 'Puntahan';

  @override
  String get respGoBack => 'Bumalik';

  @override
  String get respSosFlagged => 'Naka-flag ang SOS account';

  @override
  String get respTranscriptWarning => 'Ang mga salita sa itaas ay transcribed at puwedeng mali.';

  @override
  String get respSceneOnlyWhenOnScene => 'Pwede lang kumuha ng larawan kapag nasa lugar ka na.';

  @override
  String get respSceneUploading => 'Ina-upload...';

  @override
  String get respSceneTakePhoto => 'Kumuha ng larawan sa lugar';

  @override
  String respSceneAddMore(int count) {
    return 'Magdagdag pa ($count naidagdag)';
  }

  @override
  String get respSceneNotSignedIn => 'Hindi ka naka-sign in.';

  @override
  String get respScenePhotoAdded => 'Naidagdag ang larawan.';

  @override
  String get respScenePhotoNotAdded => 'Hindi naidagdag ang larawan.';

  @override
  String get respScenePhotoUploadFailed => 'Hindi na-upload ang larawan. Subukan ulit kapag may signal.';

  @override
  String get respActionAccept => 'Pagtanggap ng tawag';

  @override
  String get respActionDecline => 'Pagtanggi sa tawag';

  @override
  String get respActionStatusUpdate => 'Update ng status';

  @override
  String get respActionClose => 'Pagsasara ng insidente';

  @override
  String get respActionSceneMedia => 'Mga larawan sa lugar';

  @override
  String get respActionDistress => 'Distress signal';

  @override
  String get respProfileTitle => 'Profile';

  @override
  String get respProfileSaved => 'Naisave ang profile.';

  @override
  String get respProfileCancel => 'Ikansela';

  @override
  String get respProfileEdit => 'Baguhin';

  @override
  String get respProfileSave => 'I-save';

  @override
  String get respProfileContact => 'Contact';

  @override
  String get respProfileAssignment => 'Destino';

  @override
  String get respProfileShift => 'Ngayong shift';

  @override
  String get respProfileBadge => 'Badge ID';

  @override
  String get respProfileAgency => 'Ahensya';

  @override
  String get respProfileMunicipality => 'Munisipyo';

  @override
  String get respProfileStatus => 'Katayuan';

  @override
  String get respProfileAssignedNow => 'Nakatalaga ngayon';

  @override
  String get respProfileWaitingToSend => 'Naka-antabay na ipadala';

  @override
  String get respProfileResolvedPeriod => 'Naresolba ngayong panahon';

  @override
  String get respProfileTypicalResponse => 'Karaniwang oras ng pagtugon';

  @override
  String get respProfileNameRequired => 'Kailangan ang pangalan.';

  @override
  String get respLogout => 'Mag-log out';

  @override
  String get respLogoutConfirm => 'Mag-log out?';

  @override
  String get respLogoutBody => 'Hihinto ang pagtanggap mo ng dispatch alerts sa telepono na ito hangga\'t hindi ka muling naka-sign in.';

  @override
  String get respOnDuty => 'NAKA-DUTY';

  @override
  String get respOffDuty => 'WALA SA DUTY';

  @override
  String get respApproved => 'Aprubado';

  @override
  String get respRejected => 'Hindi aprubado';

  @override
  String get respPending => 'Naghihintay ng aprubal';

  @override
  String get respPendingTitle => 'Naghihintay pa ng aprubal';

  @override
  String get respPendingBody => 'Hindi ka pa makakatanggap ng dispatch hangga\'t hindi na-verify ng Agency Admin ang badge ID mo.';

  @override
  String get respRejectedTitle => 'Hindi aprubado ang account mo';

  @override
  String get respRejectedBody => 'Hindi ka makakatanggap ng dispatch. Kausapin ang iyong Agency Admin.';

  @override
  String get respCancel => 'Ikansela';

  @override
  String respHazardBanner(int count) {
    return 'BABALA SA DAAN ($count)';
  }

  @override
  String respDeclinedTimes(int count) {
    return 'Tinanggihan ${count}x';
  }

  @override
  String respPriorWarnings(int count) {
    return '$count naunang babala';
  }

  @override
  String respSyncPending(int count) {
    return '$count naka-antabay — ipapadala kapag may signal';
  }

  @override
  String respTellingResident(String eta) {
    return 'Sinasabi sa residente: $eta';
  }

  @override
  String respLandmarkPrefix(String landmark) {
    return 'Palatandaan: $landmark';
  }

  @override
  String respStatsPeriod(int days) {
    return 'Huling $days araw';
  }

  @override
  String respAnswerWithin(String time) {
    return 'Sagutin sa loob ng $time';
  }

  @override
  String respEtaMinutes(int minutes) {
    return 'mga $minutes min';
  }

  @override
  String get respReasonVehicleDown => 'Sirang sasakyan';

  @override
  String get respReasonVehicleDownHint => 'Hindi makaandar ang truck o ambulansya';

  @override
  String get respReasonCommitted => 'May hinaharap na tawag';

  @override
  String get respReasonCommittedHint => 'May kasalukuyang insidente na hindi pa tapos';

  @override
  String get respReasonOutOfArea => 'Wala sa aming lugar';

  @override
  String get respReasonOutOfAreaHint => 'Mali ang munisipyo para sa unit na ito';

  @override
  String get respReasonCrew => 'Kulang ang tauhan';

  @override
  String get respReasonCrewHint => 'Kulang ang tao para ligtas na makaresponde';

  @override
  String get respReasonRoad => 'Hindi madaanan';

  @override
  String get respReasonRoadHint => 'Baha, landslide o putol na tulay';

  @override
  String get respReasonOther => 'Iba pang dahilan';

  @override
  String get respReasonOtherHint => 'Ipaliwanag sa note';

  @override
  String get respOutcomeHandled => 'Naayos sa lugar';

  @override
  String get respOutcomeHandledHint => 'Naayos, walang inilipat';

  @override
  String get respOutcomeTransported => 'May dinala sa ospital';

  @override
  String get respOutcomeTransportedHint => 'May dinalang biktima sa pasilidad';

  @override
  String get respOutcomeTurnedOver => 'Isinalin sa ibang ahensya';

  @override
  String get respOutcomeTurnedOverHint => 'Isinalin sa PNP, BFP, MDRRMO o ospital';

  @override
  String get respOutcomeFalseAlarm => 'Walang totoong emergency';

  @override
  String get respOutcomeFalseAlarmHint => 'Walang nangyayari';

  @override
  String get respOutcomeNobodyFound => 'Walang natagpuan';

  @override
  String get respOutcomeNobodyFoundHint => 'Nakarating, walang insidente at walang nag-ulat';

  @override
  String get respOutcomeRefused => 'Tumangging tumanggap ng tulong';

  @override
  String get respOutcomeRefusedHint => 'Naroon sila pero tumanggi sa tulong';

  @override
  String get respOutcomeNoAccess => 'Hindi naabot ang lugar';

  @override
  String get respOutcomeNoAccessHint => 'Hindi talaga naabot ang lugar';

  @override
  String get respOutcomeOther => 'Iba pa';

  @override
  String get respOutcomeOtherHint => 'Ipaliwanag sa salaysay';

  @override
  String get respHazardRoad => 'Hindi madaanan';

  @override
  String get respHazardAccess => 'Mahirap puntahan';

  @override
  String get respHazardSecurity => 'Delikado';

  @override
  String get respHazardAnimal => 'May hayop';

  @override
  String get respHazardStructural => 'Delikadong gusali';

  @override
  String get respHazardOther => 'Babala';

  @override
  String get respNoAnswerSeen => 'Walang sagot — nakikita na ito ng dispatcher';

  @override
  String get respUpdateStatus => 'I-update ang Status';

  @override
  String get respAnswerSendFailed => 'Hindi naipadala. Subukan ulit.';

  @override
  String get respCloseFailed => 'Hindi naisara.';

  @override
  String get respDeclineSent => 'Naibalik sa dispatcher. Maghahanap sila ng ibang unit.';

  @override
  String respBackupSentTo(String station) {
    return 'Naipadala sa $station. Nasa queue na nila ito.';
  }

  @override
  String get respEscalateSent => 'Naipadala. Alam na ng Agency Admin.';

  @override
  String get respEscalateAction => 'I-escalate ang insidente';

  @override
  String get respEscalateBody => 'Sabihin sa Agency Admin kung ano ang nagbago. Aabisuhan sila para muling suriin — hindi mo mismo binabago ang opisyal na severity.';

  @override
  String get respEscalateWhat => 'Ano ang nagbago?';

  @override
  String get respEscalateHint => 'hal. Mabilis kumakalat ang sunog, maraming sugatan, kailangan ng isa pang ahensya…';

  @override
  String get respEscalateSubmit => 'Ipadala ang escalation';

  @override
  String get respDistressSentLive => 'NAIPADALA. Nakikita ka na ng dispatcher.';

  @override
  String get respDistressSentQueued => 'Walang signal — naka-queue ito. TAWAGAN ANG STATION SA RADYO NGAYON.';

  @override
  String get respConfirmResolve => 'I-mark ba itong insidente bilang Natapos? Makikita ito ng dispatcher at ng nag-ulat.';

  @override
  String get respConfirmStatusUpdate => 'I-update ba ang status ng insidente?';

  @override
  String get respNoLocationRecorded => 'Walang lokasyon na naitala sa ulat na ito. Tanungin ang dispatcher.';

  @override
  String get mapNearbyStationsTitle => 'Mga Malapit na Istasyon ng Emergency';

  @override
  String get mapResponderTitle => 'Mapa ng mga Insidente';

  @override
  String get mapReportLocationTitle => 'Lokasyon ng Ulat';

  @override
  String get mapLocationOff => 'Naka-off ang lokasyon';

  @override
  String get mapLocationSearching => 'Hinahanap ang lokasyon…';

  @override
  String mapLocationPrecise(int accuracy) {
    return 'Nandito ka · ±$accuracy m';
  }

  @override
  String mapLocationImprecise(int accuracy) {
    return 'Malabo · ±$accuracy m';
  }

  @override
  String get mapNoLocationYet => 'Wala pang lokasyon. Tingnan kung naka-on ang GPS.';

  @override
  String get mapYouLabel => 'Ikaw';

  @override
  String get mapLoading => 'Naglo-load ng mapa…';

  @override
  String get mapGetDirections => 'Kunin ang direksyon';

  @override
  String mapStationDistance(String distanceKm, String agency) {
    return '$distanceKm km ang layo · $agency';
  }

  @override
  String mapStationDistanceShort(String distanceKm) {
    return '$distanceKm km';
  }

  @override
  String get settingsScreenTitle => 'Mga Setting at Profile';

  @override
  String get settingsEditPersonalInfo => 'I-edit ang personal na impormasyon';

  @override
  String get settingsChangePassword => 'Palitan ang password';

  @override
  String get settingsNotificationPreferences => 'Mga preference sa notification';

  @override
  String get settingsAppSettingsSection => 'Mga Setting ng App';

  @override
  String get settingsDarkMode => 'Madilim na mode';

  @override
  String get settingsLocationServices => 'Serbisyo ng lokasyon';

  @override
  String get settingsLocationDenied => 'Hindi na-grant ang permiso sa lokasyon.';

  @override
  String get settingsLocationOffTitle => 'I-off ang location services?';

  @override
  String get settingsLocationOffBody => 'Sa Settings app lang ng iyong telepono (hindi sa loob ng Ziren) puwedeng baguhin ito, para sa Android at iOS.';

  @override
  String get settingsOpenSystemSettings => 'Buksan ang Settings';

  @override
  String get settingsCancel => 'Kanselahin';

  @override
  String get settingsOfflineMaps => 'Offline na mapa';

  @override
  String get settingsOfflineMapsComingSoon => 'Darating pa ang offline maps sa susunod na update.';

  @override
  String get settingsSupportSection => 'Suporta';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsSectionLocation => 'Location';

  @override
  String get settingsSectionLanguage => 'Wika';

  @override
  String get settingsSectionHelpSupport => 'Tulong at Suporta';

  @override
  String get settingsSectionAbout => 'Tungkol';

  @override
  String get settingsHelpFaq => 'Tulong at Mga Tanong';

  @override
  String get settingsFaqReportQ => 'Paano mag-report ng emergency?';

  @override
  String get settingsFaqReportA => 'Sa Home, pindutin ang uri ng emergency (Sunog, Medikal, Aksidente, Krimen, Kalamidad o Iba pa). Tingnan ang landmark, sabihin o i-type ang nangyari, i-review, saka ipadala. Ipapadala ito ng Ziren sa pinakamalapit na station na humahawak nito.';

  @override
  String get settingsFaqOfflineQ => 'Ano ang mangyayari kung walang internet?';

  @override
  String get settingsFaqOfflineA => 'Kailangan ng internet para maipadala ang report. Kung walang data, pindutin pa rin ang uri ng emergency sa Home: ipapakita ng Ziren ang opisyal na hotline ng mga station, at signal lang ang kailangan sa tawag. Puwede ring tumawag sa 911.';

  @override
  String get settingsFaqAgencyQ => 'Aling ahensya ang tutugon sa report ko?';

  @override
  String get settingsFaqAgencyA => 'Depende sa emergency: BFP sa sunog, PNP sa krimen, MDRRMO sa medikal, aksidente at kalamidad. Ang station sa bayan kung nasaan ang insidente ang tatanggap nito.';

  @override
  String get settingsFaqAccountQ => 'Paano i-update ang emergency contact ko?';

  @override
  String get settingsFaqAccountA => 'Sa Settings, buksan ang \"I-edit ang personal na impormasyon\", palitan ang pangalan o numero ng contact, at pindutin ang \"I-save ang mga pagbabago\".';

  @override
  String get settingsAboutZiren => 'Tungkol sa Ziren';

  @override
  String get settingsAboutTagline => 'Emergency Response, Simplified. Ginawa para sa mga residente ng Biliran.';

  @override
  String settingsAboutVersion(String version) {
    return 'Bersyon $version';
  }

  @override
  String get settingsAboutTerms => 'Mga Tuntunin sa Paggamit';

  @override
  String get settingsAboutPrivacy => 'Paunawa sa Privacy ng Data';

  @override
  String get settingsLogOut => 'Mag-log out';

  @override
  String get settingsLogOutConfirmTitle => 'Mag-log out?';

  @override
  String get settingsLogOutConfirmBody => 'Kailangan mo ulit mag-sign in para magamit ang Ziren.';

  @override
  String get settingsSectionAccessibility => 'Aksesibilidad';

  @override
  String get settingsAccessibilityAppearance => 'Hitsura';

  @override
  String get appearanceSystem => 'Sistema';

  @override
  String get appearanceLight => 'Maliwanag';

  @override
  String get appearanceDark => 'Madilim';

  @override
  String get settingsAccessibilityTextSize => 'Sukat ng Teksto';

  @override
  String get textSizeSmall => 'Maliit';

  @override
  String get textSizeDefault => 'Karaniwan';

  @override
  String get textSizeLarge => 'Malaki';

  @override
  String get textSizeExtraLarge => 'Sobrang Laki';

  @override
  String get textSizePreview => 'Ganito rin ang makikita ng responder sa iyong ulat.';

  @override
  String get settingsReduceMotion => 'Bawasan ang animation';

  @override
  String get settingsHighContrast => 'Mas malinaw na kulay';

  @override
  String get notifMoreOptions => 'Iba pang opsyon';

  @override
  String get notifClearAll => 'I-clear lahat';

  @override
  String get notifCategoryEmergencyUpdate => 'Update sa Emergency';

  @override
  String get notifCategoryReportConfirmed => 'Nakumpirma ang Ulat';

  @override
  String get notifCategorySafetyAdvisory => 'Paalala sa Kaligtasan';

  @override
  String get notifCategorySystemMessage => 'Mensahe ng Sistema';

  @override
  String get notifReportPrefix => 'Ulat #';

  @override
  String get notifEmptyTitle => 'Wala pang abiso';

  @override
  String get notifEmptySubtitle => 'Dito lalabas ang mga update sa status ng iyong mga ulat.';

  @override
  String get voiceTapToRecord => 'I-tap para mag-record';

  @override
  String get voiceTapToStop => 'I-tap para itigil';

  @override
  String voiceUpToMinutes(int minutes) {
    return '(hanggang $minutes minuto)';
  }

  @override
  String get voiceRecordingHint => 'Sabihin ang nangyari sa sarili mong salita. Diretso itong maririnig ng istasyon.';

  @override
  String get voicePlay => 'Pakinggan';

  @override
  String get voicePause => 'Itigil';

  @override
  String voiceRecorded(String clock) {
    return 'Naka-record · $clock';
  }

  @override
  String get voiceWillSend => 'Ipapadala ito sa istasyon.';

  @override
  String get voiceDeleteTooltip => 'Burahin ang recording';

  @override
  String get voiceCaptureFailedMsg => 'Hindi na-record ang boses. Pakisulat na lang sa itaas ang nangyari — maipapadala pa rin ang ulat mo.';

  @override
  String get voiceUploadFailedMsg => 'Naipadala ang ulat, pero hindi naabot ng istasyon ang recording. Kung mahina ang signal, subukang muli.';

  @override
  String get voicePeopleCountQuestion => 'Ilan ang sangkot na tao? (opsyonal)';

  @override
  String get voicePeopleCountHint => 'Madalas hindi ito nakukuha sa recording.';

  @override
  String get voicePeopleCountNotSure => 'Hindi sigurado';

  @override
  String get homeLocating => 'Hinahanap ang lokasyon…';

  @override
  String reportsLocationDistance(String location, String km) {
    return '$location · $km km';
  }

  @override
  String get reportsViewOnMap => 'Tingnan sa Mapa';

  @override
  String get safetyGuideTitle => 'Gabay sa Kaligtasan';

  @override
  String get safetyFireTitle => 'Sunog';

  @override
  String get safetyFireStep1 => 'Lumabas agad sa gusali. Huwag balikan ang mga gamit.';

  @override
  String get safetyFireStep2 => 'Kung may usok, dumapa at gumapang papunta sa exit.';

  @override
  String get safetyFireStep3 => 'Huwag gamitin ang elevator — hagdan lamang.';

  @override
  String get safetyFireStep4 => 'I-touch lang ang doorknob gamit ang likod ng kamay bago buksan — kung mainit, huwag buksan.';

  @override
  String get safetyFireStep5 => 'Pagkalabas, tumawag agad sa BFP o mag-ulat gamit ang Ziren.';

  @override
  String get safetyFireStep6 => 'Huwag na bumalik sa loob hangga\'t hindi sinasabing ligtas na.';

  @override
  String get safetyEarthquakeTitle => 'Lindol';

  @override
  String get safetyEarthquakeStep1 => 'Duck, Cover, Hold — dumapa, magtago sa ilalim ng matibay na mesa, at humawak.';

  @override
  String get safetyEarthquakeStep2 => 'Layuan ang mga bintana, salamin, at mabibigat na kagamitan.';

  @override
  String get safetyEarthquakeStep3 => 'Kung nasa labas, lumayo sa mga gusali, poste, at kable.';

  @override
  String get safetyEarthquakeStep4 => 'Kung nagmamaneho, huminto sa ligtas na lugar at manatili sa loob ng sasakyan.';

  @override
  String get safetyEarthquakeStep5 => 'Pagkatapos ng pagyanig, maghanda sa aftershocks.';

  @override
  String get safetyEarthquakeStep6 => 'Suriin ang paligid para sa mga sira na linya ng gas o kuryente bago gumalaw.';

  @override
  String get safetyFloodTitle => 'Baha';

  @override
  String get safetyFloodStep1 => 'Lumipat agad sa mas mataas na lugar kung sakop ng flood warning ang inyong barangay.';

  @override
  String get safetyFloodStep2 => 'Iwasan ang paglakad o pagmaneho sa baha — anim na pulgada ng tubig ay kayang tumumba sa tao.';

  @override
  String get safetyFloodStep3 => 'Patayin ang de-kuryenteng gamit at i-off ang main breaker kung may oras pa.';

  @override
  String get safetyFloodStep4 => 'Ihanda ang mga mahahalagang dokumento sa waterproof na lalagyan.';

  @override
  String get safetyFloodStep5 => 'Sundin ang mga tagubilin ng MDRRMO tungkol sa evacuation.';

  @override
  String get safetyFloodStep6 => 'Huwag uminom ng baha na tubig o tubig-gripo hangga\'t hindi pa na-declare na safe.';

  @override
  String get safetyTyphoonTitle => 'Bagyo';

  @override
  String get safetyTyphoonStep1 => 'Panoorin ang PAGASA advisories at ang mga anunsyo mula sa Ziren.';

  @override
  String get safetyTyphoonStep2 => 'Ihanda ang emergency kit: tubig, pagkain, flashlight, first aid, at power bank.';

  @override
  String get safetyTyphoonStep3 => 'I-secure o ilagay sa loob ang mga bagay na maaaring lumipad sa hangin.';

  @override
  String get safetyTyphoonStep4 => 'Manatili sa loob ng bahay maliban na lang kung inutusan mag-evacuate.';

  @override
  String get safetyTyphoonStep5 => 'Iwasan ang mga puno at poste ng kuryente kapag may malakas na hangin.';

  @override
  String get safetyTyphoonStep6 => 'Alamin kung saan ang pinakamalapit na evacuation center bago pa dumating ang bagyo.';

  @override
  String get safetyRoadAccidentTitle => 'Aksidente sa Kalsada';

  @override
  String get safetyRoadAccidentStep1 => 'Siguraduhing ligtas ka muna bago tumulong sa iba.';

  @override
  String get safetyRoadAccidentStep2 => 'Ilagay ang hazard/warning lights at maglagay ng marker kung mayroon.';

  @override
  String get safetyRoadAccidentStep3 => 'Huwag galawin ang biktima maliban na lang kung may agarang panganib (hal. sunog).';

  @override
  String get safetyRoadAccidentStep4 => 'Tumawag agad sa PNP at/o MDRRMO, o mag-ulat gamit ang Ziren.';

  @override
  String get safetyRoadAccidentStep5 => 'Bantayan ang paghinga at pulso ng biktima habang naghihintay ng tulong.';

  @override
  String get safetyRoadAccidentStep6 => 'Kung may dumadaloy na dugo, pindutin ito gamit ng malinis na tela.';

  @override
  String get safetyMedicalTitle => 'Medical Emergency';

  @override
  String get safetyMedicalStep1 => 'Suriin kung malay pa ang pasyente at kung humihinga nang normal.';

  @override
  String get safetyMedicalStep2 => 'Tumawag agad ng tulong — huwag hintayin na lumala ang sitwasyon.';

  @override
  String get safetyMedicalStep3 => 'Kung hindi humihinga at walang malay, simulan ang CPR kung marunong.';

  @override
  String get safetyMedicalStep4 => 'Huwag bigyan ng pagkain o inumin ang taong nahihirapang huminga o nawalan ng malay.';

  @override
  String get safetyMedicalStep5 => 'Panatilihing kalmado at komportable ang pasyente habang naghihintay.';

  @override
  String get safetyMedicalStep6 => 'Ihanda ang impormasyon ng pasyente (edad, kondisyon, gamot) para sa responder.';

  @override
  String get safetyCrimeTitle => 'Krimen';

  @override
  String get safetyCrimeStep1 => 'Unahin ang sariling kaligtasan — lumayo sa panganib kung kaya.';

  @override
  String get safetyCrimeStep2 => 'Huwag hawakan o galawin ang eksena ng krimen kung ligtas namang lumayo.';

  @override
  String get safetyCrimeStep3 => 'Tumawag agad sa PNP o mag-ulat gamit ang Ziren.';

  @override
  String get safetyCrimeStep4 => 'Tandaan ang detalye: hitsura, plaka, direksyon — kung kaya nang ligtas.';

  @override
  String get safetyCrimeStep5 => 'Manatili sa ligtas na lugar hanggang dumating ang responder.';

  @override
  String get safetyCrimeStep6 => 'Sundin ang mga tagubilin ng pulis pagdating nila sa eksena.';

  @override
  String get contactsTitle => 'Emergency Contacts';

  @override
  String get contactsNationalTitle => 'National Emergency Hotline';

  @override
  String get contactsNationalSubtitle => 'Para sa anumang emergency, kahit saan sa Pilipinas';

  @override
  String get contactsLocalAgencies => 'MGA LOCAL NA AHENSYA';

  @override
  String get contactsNoneListed => 'Wala pang naka-listang numero. Gamitin ang 911 o mag-ulat sa pamamagitan ng Ziren.';

  @override
  String get contactsHospitalsSection => 'OSPITAL AT EVACUATION CENTER';

  @override
  String get contactsFindOnMap => 'Hanapin sa Mapa';

  @override
  String get contactsFindOnMapBody => 'Tingnan ang pinakamalapit na himpilan sa mapa.';

  @override
  String get contactsOpen => 'Buksan';

  @override
  String get announcementsTitle => 'Mga Anunsyo';

  @override
  String get announcementsLoadError => 'Hindi ma-load ang mga anunsyo.';

  @override
  String get announcementsRetry => 'Subukan Ulit';

  @override
  String get announcementsEmptyTitle => 'Walang anunsyo sa ngayon';

  @override
  String get announcementsEmptyBody => 'Ipapakita dito ang mga opisyal na paalala mula sa Ziren.';

  @override
  String get announceCategoryMaintenance => 'Pagpapanatili';

  @override
  String get announceCategoryEmergency => 'Abiso ng Emerhensiya';

  @override
  String get announceCategoryServiceInterruption => 'Paghinto ng Serbisyo';

  @override
  String get announceCategoryFeature => 'Bagong Feature';

  @override
  String get announceCategoryReminder => 'Paalala';

  @override
  String get announceCategoryGeneral => 'Anunsyo';

  @override
  String get profileSafetySection => 'Kaligtasan';

  @override
  String get aiScreenBody => 'Tutulungan ka nitong buuin ang ulat mo — itatanong kung ano, saan, at sino ang nasaktan, para kumpleto na ang impormasyong natatanggap ng istasyon.';

  @override
  String get aiNotAvailable => 'Hindi pa ito available';

  @override
  String get aiNotAvailableBody => 'Habang hinihintay ito, gamitin ang mabilisang ulat sa Home o ang SOS kung kailangan mo ng agarang tulong.';

  @override
  String get voiceConfirmAppBarTitle => 'Naipadala na ang ulat';

  @override
  String get voiceConfirmSkip => 'Laktawan';

  @override
  String get voiceConfirmSaveError => 'Hindi naisave ang pagbabago. Naipadala na pa rin ang ulat.';

  @override
  String get voiceConfirmSentTitle => 'Naipadala na ang ulat mo.';

  @override
  String get voiceConfirmSentBodyStation => 'Naririnig na ito ng istasyon.';

  @override
  String voiceConfirmSentBodyStationNamed(String station) {
    return 'Naririnig na ito ng $station.';
  }

  @override
  String get voiceConfirmGaveUpTitle => 'Pakikinggan ng istasyon ang recording mo.';

  @override
  String get voiceConfirmGaveUpBody => 'Hindi namin naisulat agad ang sinabi mo, pero nasa kanila na ang boses mo mismo.';

  @override
  String get voiceConfirmOk => 'Sige';

  @override
  String get voiceConfirmListeningTitle => 'Pinapakinggan namin ang boses mo…';

  @override
  String get voiceConfirmListeningBody => 'Sandali lang. Ipapakita namin kung tama ang naintindihan namin.';

  @override
  String get voiceConfirmEditTitle => 'Ano ang totoong sinabi mo?';

  @override
  String get voiceConfirmBack => 'Balik';

  @override
  String get voiceConfirmSave => 'I-save';

  @override
  String get voiceConfirmHeardTitle => 'Ito ang narinig namin:';

  @override
  String get voiceConfirmWrongFix => 'Mali — ayusin';

  @override
  String get voiceConfirmCorrect => 'Tama';

  @override
  String get feedbackThanks => 'Salamat sa iyong feedback!';

  @override
  String get feedbackClose => 'Sarado';

  @override
  String get feedbackHowWasIt => 'Kumusta ang iyong karanasan?';

  @override
  String get feedbackNoImpact => 'Hindi ito makaka-apekto sa priyoridad ng iyong susunod na ulat.';

  @override
  String get feedbackCommentHint => 'Karagdagang puna (opsyonal)…';

  @override
  String get feedbackSubmit => 'Ipadala';

  @override
  String get feedbackMaybeLater => 'Balang araw na lang';

  @override
  String get threadTitle => 'Mga Update sa Ulat';

  @override
  String get threadLoadError => 'Hindi ma-load ang mga mensahe.';

  @override
  String get threadEmptyTitle => 'Wala pang mensahe';

  @override
  String get threadEmptyBody => 'Dito lalabas ang dagdag na detalye mo at ang tugon ng ahensya.';

  @override
  String get threadComposerHint => 'Magdagdag ng detalye…';

  @override
  String get threadClosedNotice => 'Sarado na ang ulat na ito — hindi na maaaring magdagdag ng mensahe.';

  @override
  String get reportsAskConfirmVoice => 'Tama ba ang narinig namin?';

  @override
  String reportsAlreadyRated(String rating) {
    return 'Na-rate mo na ito · $rating/5';
  }

  @override
  String get reportsRateService => 'I-rate ang Serbisyo';

  @override
  String get incidentStatusReceived => 'Natanggap ang ulat';

  @override
  String get incidentStatusProcessing => 'Sinusuri ng dispatcher';

  @override
  String get incidentStatusDispatched => 'May responder na papunta';

  @override
  String get incidentStatusResolved => 'Nalutas';

  @override
  String get incidentStatusCancelled => 'Kinansela';

  @override
  String incidentEtaMinutes(int minutes) {
    return 'mga $minutes minuto';
  }

  @override
  String get threadAuthorYou => 'Ikaw';

  @override
  String activeReportAgencyEnRoute(String agency, String eta) {
    return 'Papunta na ang $agency — $eta';
  }

  @override
  String activeReportResponderEnRoute(String eta) {
    return 'Papunta na ang responder — $eta';
  }

  @override
  String get activeReportNotFollowedUp => 'Hindi na ipinagpatuloy ang ulat na ito.';

  @override
  String get activeReportStale => 'Matagal nang naghihintay. I-tap para tingnan.';

  @override
  String activeReportStep(int step, int total) {
    return 'Hakbang $step sa $total';
  }

  @override
  String get readyPanelFalseReportWarning => 'Ang maling ulat ay may kaakibat na parusa.';

  @override
  String get reviewRecordVideo => 'Mag-record ng video';

  @override
  String get reviewChooseFromGallery => 'Pumili mula sa gallery';

  @override
  String get reviewAttachmentsSection => 'MGA ATTACHMENT';

  @override
  String get reviewAddAttachment => 'Magdagdag';

  @override
  String get reviewAttachmentsHint => 'Opsyonal: magdagdag ng litrato o video bilang ebidensya. Hanggang 5 file, 50 MB bawat isa, video na hanggang 2 minuto.';

  @override
  String get sosAddDetailsExample => 'hal. \"May 3 na tao na nagtatakas, sunog sa ground floor, wala nang nakikitang apoy sa labas…\"';

  @override
  String get reportsAddInformation => 'Chat';

  @override
  String get avatarSheetTitle => 'Larawan sa Profile';

  @override
  String get avatarRemovePhoto => 'Alisin ang larawan';

  @override
  String get avatarUploadFailed => 'Hindi na-update ang larawan sa profile. Subukan ulit.';

  @override
  String get respDutyCardBusy => 'Sandali lang...';

  @override
  String get respDutyCardOn => 'Kasalukuyang On-Duty';

  @override
  String get respDutyCardOff => 'Wala sa Duty';

  @override
  String respDutyCardStation(String station) {
    return '(Istasyon: $station)';
  }

  @override
  String get respDutyToggleOff => 'Mag-off duty';

  @override
  String get respDutyToggleOn => 'Mag-on duty';

  @override
  String get statusRejected => 'Tinanggihan';

  @override
  String get statusNeedsReply => 'Kailangan ng sagot mo';

  @override
  String get reportRejectedTitle => 'Hindi tinanggap ng ahensya ang ulat na ito';

  @override
  String reportRejectedReason(String reason) {
    return 'Dahilan: $reason';
  }

  @override
  String get reportRejectedHelp => 'Kung totoong emergency ito, tumawag agad sa istasyon, o magpadala ng bagong ulat na may mas maraming detalye.';

  @override
  String get reportRejectedCall => 'Tawagan ang mga emergency contact';

  @override
  String get reportFileAgain => 'Magpadala ng bagong ulat';

  @override
  String get clarificationTitle => 'Kailangan ng ahensya ng karagdagang impormasyon';

  @override
  String get clarificationAsked => 'Tanong nila:';

  @override
  String get clarificationReply => 'Sagutin';

  @override
  String get clarificationReplyHint => 'Sagutin dito. Hinihintay ng ahensya ang sagot mo bago sila magpasya.';

  @override
  String get notifRejectedTitle => 'Hindi tinanggap ang ulat';

  @override
  String get notifClarificationTitle => 'Kailangan ng ahensya ng karagdagang impormasyon';

  @override
  String get notifViewReport => 'Tingnan ang ulat';

  @override
  String get notifReplyNow => 'Sagutin ngayon';

  @override
  String get idCheckTitle => 'Hindi pa namin matatanggap ang larawang ito';

  @override
  String get idCheckNoText => 'Wala kaming mabasang teksto. Kunan sa maliwanag, patag, at kita ang buong ID.';

  @override
  String get idCheckNotAnIdTitle => 'Hindi namin ito matatanggap — hindi ito ID';

  @override
  String idCheckNotAnId(String chosen) {
    return 'Hindi namin matatanggap ang larawang ito dahil hindi ito ID. Mag-upload muli at siguraduhing larawan ito ng inyong $chosen — ang mismong card, hindi ang mukha ninyo o ibang larawan.';
  }

  @override
  String idCheckWrongTypeTitle(String chosen) {
    return 'Hindi ito $chosen';
  }

  @override
  String idCheckWrongType(String chosen, String found) {
    return 'Hindi namin ito matatanggap. $chosen ang pinili ninyo, pero mukhang $found ang larawang ito. I-upload ang inyong $chosen — o bumalik at piliin ang ID type na tugma sa inyong card.';
  }

  @override
  String idCheckTypeUnconfirmed(String chosen) {
    return 'Hindi namin makumpirma na $chosen ito. Kunan nang malinaw ang HARAP ng inyong $chosen, patag at maliwanag, at nababasa ang mga nakalimbag na salita.';
  }

  @override
  String get idCheckNoFace => 'Hindi namin makita ang larawan mo sa ID. Gamitin ang HARAP ng ID.';

  @override
  String get idCheckNoNumber => 'Wala kaming makitang ID number. Siguraduhing malinaw ang numero at walang glare.';

  @override
  String get idCheckNumberMismatch => 'Hindi tugma ang numerong tinype mo sa nasa larawan ng ID. Ayusin, o kunan muli.';

  @override
  String get idCheckRetakeHint => 'Kunan muli ang larawan, o i-skip ang verification at gawin mamaya sa Settings.';

  @override
  String get idCheckRetakeOnly => 'Kunan muli ang larawan para makapagpatuloy.';

  @override
  String get idCheckPassed => 'Tinanggap ang larawan ng ID';

  @override
  String get idCheckChecking => 'Sinusuri ang larawan…';

  @override
  String regLocationBarangaySet(String barangay, String municipality) {
    return 'Nakita ang barangay mo: $barangay, $municipality. Tiyaking tama ito.';
  }

  @override
  String regLocationBarangayNear(String barangay, String municipality) {
    return 'Pinakamalapit na barangay: $barangay, $municipality. Hindi kami sigurado, kaya kumpirmahin o palitan.';
  }

  @override
  String regLocationMunicipalityOnly(String municipality) {
    return 'Nakita ang $municipality, pero hindi matukoy ang barangay. Pumili sa ibaba.';
  }

  @override
  String get selfieCapture => 'Kumuha ng larawan';

  @override
  String get selfieCapturing => 'Kumukuha…';

  @override
  String get statusArrived => 'Dumating na ang responder';

  @override
  String get statusCancelledByAgency => 'Kinansela ng ahensya';

  @override
  String get notifAcceptedTitle => 'Tinanggap ang ulat';

  @override
  String get notifAcceptedBody => 'Kinumpirma ng ahensya na totoo ang iyong ulat at naghahanda na ito ng tugon.';

  @override
  String get notifEnRouteBody => 'Papunta na sa iyong lokasyon ang responder.';

  @override
  String get notifArrivedBody => 'Dumating na ang responder sa iyong lokasyon.';

  @override
  String get notifResolvedHelp => 'Maaari mong i-rate ang tugon sa My Reports.';

  @override
  String get notifCancelledTitle => 'Kinansela ng ahensya ang ulat';

  @override
  String get notifCancelledBody => 'Kinansela ng ahensya ang iyong ulat.';

  @override
  String notifCancelledReason(String reason) {
    return 'Dahilan: $reason';
  }

  @override
  String get notifCancelledHelp => 'Kung kailangan mo pa rin ng tulong, tawagan ang istasyon o magpadala ng bagong ulat.';

  @override
  String get notifMessageTitle => 'Bagong mensahe mula sa ahensya';

  @override
  String get notifMessageHelp => 'Sumagot sa chat ng ulat na ito.';

  @override
  String get notifOpenChat => 'Buksan ang chat';

  @override
  String get notifMessageFromResponder => 'Bagong mensahe mula sa responder';

  @override
  String get notifFeedTitleAccepted => 'Tinanggap ang ulat';

  @override
  String get notifFeedTitleCancelled => 'Kinansela ang ulat';

  @override
  String get notifFeedTitleMessage => 'Bagong mensahe';

  @override
  String get respEnRouteDone => 'Naka-mark ka nang papunta. Nakikita ito ng dispatcher at ng residente.';

  @override
  String get respArrivedDone => 'Naka-mark ka nang nasa lugar. Nakikita ito ng dispatcher at ng residente.';

  @override
  String get settingsProfileSaved => 'Na-save ang iyong profile.';

  @override
  String get welcomeResumeTitle => 'Ipagpatuloy kung saan ka huminto?';

  @override
  String get welcomeResumeBody => 'Sinimulan mo nang gumawa ng account sa telepono na ito pero hindi mo pa natatapos.';

  @override
  String get welcomeResumeContinue => 'Ipagpatuloy';

  @override
  String get welcomeResumeStartOver => 'Magsimula muli';

  @override
  String get respActiveAssignmentTitle => 'May Aktibong Assignment';

  @override
  String get respActiveAssignmentBody => 'May aktibo kang assignment na insidente ngayon. Kapag nag-log out ka, maaaring hindi mo matanggap ang mahahalagang update.';

  @override
  String get respStaySignedIn => 'Manatiling Naka-sign In';

  @override
  String get respNearbyTitle => 'May insidenteng malapit sa iyo';

  @override
  String get respNearbyAlertEyebrow => 'INSIDENTE MALAPIT SA IYO';

  @override
  String get respNearbySubtitle => 'Wala pang ipinadalang responder. Puwede mong sabihin kung kaya mong pumunta — ang dispatcher ang magpapasya kung sino ang isasagot.';

  @override
  String get respNearbyDistanceUnknown => 'Hindi malaman ang distansya';

  @override
  String respNearbyAlreadyOn(String category) {
    return 'Nasa $category ka na';
  }

  @override
  String get respNearbyNotAvailable => 'Hindi kaya';

  @override
  String get respNearbyCanRespond => 'Kaya kong pumunta';

  @override
  String get respNearbyAnsweredYes => 'Sinabi mong kaya mong pumunta';

  @override
  String get respNearbyAnsweredNo => 'Sinabi mong hindi ka pwede';

  @override
  String get respNearbySosChip => 'SOS';

  @override
  String get hotlinesTitle => 'Mga emergency hotline';

  @override
  String hotlinesForCategory(String category) {
    return 'Mga hotline para sa $category';
  }

  @override
  String get hotlinesSheetSubtitle => 'I-tap ang numero para buksan ang dialer ng phone mo. Nauuna ang pinakamalapit na bayan.';

  @override
  String get hotlinesOfflineTitle => 'Walang internet — tumawag nang direkta sa station';

  @override
  String get hotlinesOfflineBody => 'Hindi maipadala ang report ngayon. Gumagana pa rin ang tawag kahit signal lang ang meron ka.';

  @override
  String get hotlinesNearest => 'Pinakamalapit';

  @override
  String get hotlinesCallNow => 'Tumawag';

  @override
  String hotlinesCallSemantics(String number) {
    return 'Tawagan ang $number';
  }

  @override
  String hotlinesCallFailed(String number) {
    return 'Hindi mabuksan ang dialer. I-dial nang manual ang $number.';
  }

  @override
  String get hotlinesNational => 'National Emergency Hotline';

  @override
  String get hotlinesNationalScope => 'Kahit saan sa Pilipinas';

  @override
  String get hotlinesRhu => 'Rural Health Unit';

  @override
  String get hotlinesSeeAll => 'Tingnan lahat ng hotline';

  @override
  String get hotlinesScreenIntro => 'Opisyal na numero ng bawat BFP, PNP at MDRRMO station sa Biliran. Gumagana kahit walang internet — signal lang ang kailangan.';

  @override
  String get hotlinesFilterAll => 'Lahat';

  @override
  String get hotlinesHomeCardTitle => 'Hotline ng mga station';

  @override
  String get hotlinesHomeCardBody => 'Tawagan nang direkta ang BFP, PNP o MDRRMO — gumagana kahit walang internet.';

  @override
  String get hotlinesCallInstead => 'Tumawag na lang sa station';

  @override
  String get hotlinesStationCall => 'Tawagan';

  @override
  String get homeOfflineCallHint => 'Walang internet. Pindutin ang category sa ibaba para makita ang mga numero ng station na tatawagan.';

  @override
  String get locWhereTitle => 'Nasaan ang insidente?';

  @override
  String get locHere => 'Nandito ako mismo';

  @override
  String get locElsewhere => 'Sa ibang lugar';

  @override
  String get locPickedPoint => 'Lokasyong pinili sa mapa';

  @override
  String get locElsewhereNote => 'Sasabihin sa station na nasa ibang lugar ka habang nagre-report.';

  @override
  String locElsewhereNoteFrom(String place) {
    return 'Sasabihin sa station na nagre-report ka mula sa $place.';
  }

  @override
  String get locChange => 'Baguhin';

  @override
  String get locRefresh => 'I-refresh ang lokasyon';

  @override
  String get locDeniedPickHint => 'Walang GPS? Piliin ang \"Sa ibang lugar\" at ilagay ang insidente sa mapa.';

  @override
  String get locLandmarkRequired => 'Landmark (kailangan)';

  @override
  String get locLandmarkMissing => 'Maglagay ng landmark para mahanap ng responder ang lugar.';

  @override
  String get locLandmarkAutoFilled => 'Kinuha sa pinakamalapit na landmark sa mapa — pakitiyak kung tama.';

  @override
  String get locPickTitle => 'Nasaan ang insidente?';

  @override
  String get locPickHint => 'Igalaw ang mapa hanggang nasa insidente ang pin, o maghanap ng barangay o landmark.';

  @override
  String get locPickConfirm => 'Gamitin ang lokasyong ito';

  @override
  String get locSearchHint => 'Maghanap ng barangay o landmark';

  @override
  String get locSearchClear => 'I-clear ang search';

  @override
  String get locKindLandmark => 'Landmark';

  @override
  String get locKindPlace => 'Barangay / lugar';

  @override
  String locNearLandmark(String landmark) {
    return 'Malapit sa $landmark';
  }

  @override
  String get locReviewReporterLabel => 'Nagre-report ka mula sa';

  @override
  String get locReviewReporterUnknown => 'Hindi alam ang lokasyon mo';

  @override
  String get helpTitle => 'Paano gamitin ang Ziren';

  @override
  String get helpIntroResident => 'Maiikling gabay sa mga gagawin mo sa Ziren. Pindutin ang topic para makita ang mga hakbang.';

  @override
  String get helpIntroResponder => 'Maiikling gabay para sa responder: duty, assignment, pag-update ng status at kaligtasan mo. Pindutin ang topic para makita ang mga hakbang.';

  @override
  String get helpStillStuck => 'Kailangan pa ng tulong? Tawagan ang station';

  @override
  String get helpHomeLink => 'Paano gamitin ang Ziren?';

  @override
  String get mascotName => 'Hi! Ako si Ziren';

  @override
  String mascotResidentIntro(String name) {
    return '$name, kapag may emergency, pindutin ang malaking button sa ibaba at dadalhin ko ang ulat mo sa pinakamalapit na station.';
  }

  @override
  String mascotResidentOpen(String count, String name) {
    return 'May $count ulat kang inaasikaso pa. Nandito lang ako, $name.';
  }

  @override
  String mascotResidentThanks(String count, String name) {
    return 'Nakapagpadala ka na ng $count ulat. Salamat sa pagmamalasakit sa komunidad, $name!';
  }

  @override
  String get mascotResidentOffline => 'Wala kang koneksyon ngayon. Pindutin ang uri ng emergency sa ibaba para makita ang numero ng station na matatawagan.';

  @override
  String mascotResponderOffDuty(String name) {
    return 'Off duty ka ngayon, $name. I-on ang Duty Status sa ibaba para makatanggap ng dispatch.';
  }

  @override
  String mascotResponderQueue(String count, String critical, String name) {
    return 'May $count incident na naka-assign sa iyo, $critical ang critical. Mag-ingat ka, $name!';
  }

  @override
  String mascotResponderReady(String name) {
    return 'On duty ka at handa, $name. Wala pang naka-assign sa iyo ngayon.';
  }

  @override
  String get helpButtonLabel => 'Magpatulong kay Ziren';

  @override
  String get helpSheetClose => 'Isara';

  @override
  String get homeProfileButtonLabel => 'Buksan ang iyong profile';

  @override
  String get respStatusNew => 'Bago';

  @override
  String get respStatusAccepted => 'Tinanggap';

  @override
  String get respStatusEnRoute => 'Papunta';

  @override
  String get respStatusOnScene => 'Nasa lugar';

  @override
  String get respStatusResolved => 'Natapos';

  @override
  String get respStatusCancelled => 'Kinansela';

  @override
  String get respStepAssigned => 'Na-assign';

  @override
  String get respDutyOnTitle => 'Naka-duty';

  @override
  String get respDutyOffTitle => 'Hindi naka-duty';

  @override
  String respDutyOnBody(String station) {
    return 'Tumatanggap ng dispatch · $station';
  }

  @override
  String get respDutyOnBodyPlain => 'Tumatanggap ng dispatch';

  @override
  String get respDutyOffBody => 'Hindi ka makakatanggap ng dispatch. I-on para simulan ang shift.';

  @override
  String get respNextUpTitle => 'Unahin mo ito';

  @override
  String respNextUpCount(String count) {
    return '1 sa $count';
  }

  @override
  String respOtherAssignments(String count) {
    return 'Iba pang assignment ($count)';
  }

  @override
  String get respOpenAssignment => 'Buksan';

  @override
  String get respAnswerNow => 'Sagutin ngayon';

  @override
  String respWaitingFor(String time) {
    return 'Naghihintay $time';
  }

  @override
  String respAssignedAgo(String time) {
    return 'Na-assign $time na';
  }

  @override
  String respClosedAgo(String time) {
    return 'Naisara $time na';
  }

  @override
  String respReportedAgo(String time) {
    return 'Na-report $time na';
  }

  @override
  String get respRecentClosedTitle => 'Kamakailang naisara';

  @override
  String get respNoLocation => 'Walang lokasyon';

  @override
  String get respReportsTitle => 'Aking mga report';

  @override
  String get respReportsSubtitle => 'Lahat ng ipinadala sa iyo ng dispatcher.';

  @override
  String get respViewList => 'Listahan';

  @override
  String get respViewRecord => 'Rekord';

  @override
  String get respFilterAll => 'Lahat';

  @override
  String get respFilterOpen => 'Bukas';

  @override
  String get respFilterClosed => 'Sarado';

  @override
  String get respSearchHint => 'Hanapin: barangay, INC o salita';

  @override
  String respSearchEmpty(String query) {
    return 'Walang tugma sa \"$query\".';
  }

  @override
  String respSectionOpen(String count) {
    return 'Bukas, kailangan ka ($count)';
  }

  @override
  String get respSectionThisWeek => 'Naisara ngayong linggo';

  @override
  String get respSectionLastWeek => 'Naisara noong nakaraang linggo';

  @override
  String get respSectionOlder => 'Naisara noon pa';

  @override
  String get respHistoryCapNote => 'Ipinapakita ang 50 pinakabagong naisara mo.';

  @override
  String get respEmptyOpenTitle => 'Walang bukas';

  @override
  String get respEmptyOpenBody => 'Walang assignment na naghihintay sa iyo ngayon.';

  @override
  String get respEmptyClosedTitle => 'Wala pang naisara';

  @override
  String get respEmptyClosedBody => 'Dito mapupunta ang mga insidenteng natapos mo.';

  @override
  String get respEmptyAllTitle => 'Wala pang report';

  @override
  String get respEmptyAllBody => 'Dito lalabas ang lahat ng ipapadala sa iyo ng dispatcher, bukas man o sarado.';

  @override
  String get respRecTotalClosed => 'Kabuuang naisara';

  @override
  String get respRecThisWeek => 'Naisara ngayong linggo';

  @override
  String get respRecCritical => 'Critical na nahawakan';

  @override
  String get respRecTypical => 'Karaniwang tugon';

  @override
  String get respRecChartTitle => 'Mga naisarang insidente';

  @override
  String get respRec7Days => '7 araw';

  @override
  String get respRec8Weeks => '8 linggo';

  @override
  String respRecNoneInRange(String time) {
    return 'Walang naisara sa panahong ito. Ang huli mong naisara ay $time na ang nakalipas.';
  }

  @override
  String get respRecNoneEver => 'Walang naisara sa panahong ito.';

  @override
  String get respRecMixTitle => 'Tindi ng mga naisara mo';

  @override
  String get respRecCategoryTitle => 'Uri ng insidente';

  @override
  String respRecTotal(String count) {
    return '$count lahat';
  }

  @override
  String get respRecReports => 'report';

  @override
  String get respRecEmptyTitle => 'Wala pang maipapakita';

  @override
  String get respRecEmptyBody => 'Kapag may naisara ka nang insidente, lalabas dito ang iyong rekord.';

  @override
  String get respRecTruncated => 'Hanggang 50 insidente lang ang history mo, kaya maaaring kulang ang pinakaunang bahagi ng chart na ito.';

  @override
  String get respRecWeekOf => 'lg';

  @override
  String get respStepsTitle => 'Takbo ng assignment';

  @override
  String get respNextStep => 'Susunod na hakbang';

  @override
  String get respCall => 'Tawagan';

  @override
  String get respCopy => 'Kopyahin';

  @override
  String get respGpsCopied => 'Nakopya ang coordinates.';

  @override
  String get respVerified => 'Verified';

  @override
  String get respUnverified => 'Hindi pa verified';

  @override
  String get respReporterUnknown => 'Hindi kilala ang nag-ulat';

  @override
  String get respCardReport => 'Ano ang nangyari';

  @override
  String get respCardLocation => 'Saan';

  @override
  String get respCardReporter => 'Sino ang nag-ulat';

  @override
  String get respCardStation => 'Iyong istasyon';

  @override
  String get respClosedBanner => 'Sarado na ang insidenteng ito. Wala nang kailangang gawin dito.';

  @override
  String get respEmergencyContactShort => 'Emergency contact';

  @override
  String get profileChipVerified => 'Beripikado';

  @override
  String get profileChipInReview => 'Sinusuri';

  @override
  String get profileChipNotVerified => 'Hindi pa beripikado';

  @override
  String get profileSafetyHelp => 'Kaligtasan at tulong';

  @override
  String get profileStationContact => 'Numero ng istasyon';

  @override
  String get profileStationSection => 'Istasyon';

  @override
  String get profileSettings => 'Mga setting';

  @override
  String get profileCallStation => 'Tawagan ang istasyon';

  @override
  String get settingsAccountCardHint => 'Tingnan at baguhin ang detalye mo';

  @override
  String get settingsNotifDesc => 'Mga update sa report mo at mga alerto';

  @override
  String get settingsLocationDesc => 'Ipinapadala ang lokasyon mo kasama ng report';

  @override
  String get settingsReduceMotionDesc => 'Mas kaunting gumagalaw na animation';

  @override
  String get settingsHighContrastDesc => 'Mas malinaw na text at border';

  @override
  String get settingsSaveChanges => 'I-save ang mga pagbabago';

  @override
  String get settingsDiscardTitle => 'Itapon ang mga binago?';

  @override
  String get settingsDiscardBody => 'May binago ka na hindi pa naka-save.';

  @override
  String get settingsDiscard => 'Itapon';

  @override
  String get settingsKeepEditing => 'Ituloy ang pag-edit';

  @override
  String get settingsEditorIntro => 'Nakikita ng station ang mga detalyeng ito kapag nag-report ka.';

  @override
  String get cpIntro => 'Ilagay ang kasalukuyang password mo, saka pumili ng bago.';

  @override
  String get cpCurrent => 'Kasalukuyang password';

  @override
  String get cpNew => 'Bagong password';

  @override
  String get cpConfirm => 'Ulitin ang bagong password';

  @override
  String get cpEnterCurrent => 'Ilagay ang kasalukuyang password mo.';

  @override
  String get cpMismatch => 'Hindi magkapareho ang dalawang bagong password.';

  @override
  String get cpSameAsOld => 'Dapat iba ang bagong password sa kasalukuyan.';

  @override
  String get cpWrongCurrent => 'Mali ang kasalukuyang password.';

  @override
  String get cpFailed => 'Hindi napalitan ang password. Tingnan ang koneksyon at subukan ulit.';

  @override
  String get cpDone => 'Napalitan na ang password mo.';

  @override
  String get cpForgot => 'Nakalimutan ang kasalukuyang password?';

  @override
  String get faqIntro => 'Mabilis na sagot sa mga karaniwang tanong.';

  @override
  String get faqStillNeedHelp => 'Kailangan pa ng tulong?';

  @override
  String get settingsFaqLandmarkQ => 'Bakit kailangan ang landmark?';

  @override
  String get settingsFaqLandmarkA => 'Puwedeng magkamali ang GPS nang ilang sampung metro. Sa landmark (tindahan, kapilya, court) mabilis mahahanap ng responder ang lugar. Pinupunan ito ng Ziren ng pinakamalapit; itama kung mali.';

  @override
  String get settingsFaqElsewhereQ => 'Wala ako sa lugar ng emergency. Ano ang gagawin ko?';

  @override
  String get settingsFaqElsewhereA => 'Sa report, piliin ang \"Sa ibang lugar\" at ilipat ang pin sa mapa sa mismong lugar ng insidente. Sa pin pupunta ang responder, hindi sa iyo, at sasabihin sa station na nasa ibang lugar ka.';

  @override
  String get settingsFaqTrackQ => 'Paano ko malalaman na may darating na tulong?';

  @override
  String get settingsFaqTrackA => 'Buksan ang Mga Ulat Ko. Makikita sa bawat report kung nasaan na ito — natanggap, na-dispatch, papunta, nasa lugar, natapos — at may notification tuwing nagbabago ito.';

  @override
  String get settingsFaqVerifyQ => 'Kailangan ko bang i-verify ang account ko?';

  @override
  String get settingsFaqVerifyA => 'Hindi, opsyonal ito. Ang verified na account (litrato ng valid na ID) ay nakakatulong para mas mabilis pagkatiwalaan ng station ang report mo.';

  @override
  String get safetyGuideIntro => 'Ano ang gagawin habang hinihintay ang tulong. Gumagana kahit walang internet.';

  @override
  String safetyGuideSteps(String count) {
    return '$count hakbang';
  }

  @override
  String get safetyGuideCallHotline => 'Tumawag sa hotline';

  @override
  String get aboutAgencies => 'Nag-uugnay sa mga residente at sa mga istasyon ng BFP, PNP at MDRRMO sa Biliran.';

  @override
  String get sosWhereSection => 'Nasaan ka (awtomatiko)';

  @override
  String get sosLandmarkFinding => 'Hinahanap ang pinakamalapit na landmark…';

  @override
  String sosLandmarkNear(String landmark) {
    return 'Malapit sa $landmark';
  }

  @override
  String get sosLandmarkAuto => 'Pinakamalapit na landmark sa mapa · pindutin para palitan';

  @override
  String get sosLandmarkTyped => 'Landmark na inilagay mo · pindutin para palitan';

  @override
  String get sosLandmarkNone => 'Walang nakitang landmark sa malapit';

  @override
  String get sosLandmarkNoneHint => 'Pindutin para maglagay — hindi kailangan';

  @override
  String get sosLandmarkEditTitle => 'Landmark malapit sa iyo';

  @override
  String get sosLandmarkEditBody => 'Ano ang puwedeng hanapin ng mga responder? Iwanang blangko para gamitin ang nakita sa mapa.';

  @override
  String get sosLandmarkEditHint => 'hal. tabi ng barangay hall';

  @override
  String get sosLandmarkEditSave => 'Gamitin ito';

  @override
  String get sosLandmarkEditCancel => 'Kanselahin';

  @override
  String mapStationsOnMap(String count) {
    return 'Mga istasyon sa mapa: $count';
  }

  @override
  String get mapRecenter => 'Pumunta sa lokasyon ko';

  @override
  String get mapNearestStation => 'Pinakamalapit na istasyon';

  @override
  String get mapSelectedStation => 'Napiling istasyon';

  @override
  String mapOtherStations(String count) {
    return 'Iba pang istasyon ($count)';
  }

  @override
  String get stageShortReceived => 'Natanggap';

  @override
  String get stageShortChecking => 'Sinusuri';

  @override
  String get stageShortOnTheWay => 'Papunta na';

  @override
  String get stageShortResolved => 'Tapos na';

  @override
  String reportSentAt(String when) {
    return 'Ipinadala $when';
  }

  @override
  String get reportSectionYourReport => 'Ang iniulat mo';

  @override
  String get reportSectionProgress => 'Takbo ng report';

  @override
  String get reportSectionLocation => 'Lokasyon';

  @override
  String get reportSectionDetails => 'Mga detalye';

  @override
  String get reportFactId => 'Numero ng report';

  @override
  String get reportFactVia => 'Ipinadala sa pamamagitan ng';

  @override
  String get reportFactAddress => 'Address';

  @override
  String get reportFactDistance => 'Mula sa kinaroroonan mo ngayon';

  @override
  String reportDistanceKm(String km) {
    return '$km km ang layo';
  }

  @override
  String get reportViaApp => 'Ziren app';

  @override
  String get reportViaSos => 'Emergency SOS';

  @override
  String get reportViaSms => 'Text (SMS)';

  @override
  String reportNextStep(String step) {
    return 'Susunod: $step';
  }

  @override
  String get mapYourReportLabel => 'Ang report mo';

  @override
  String onbStep(String step, String total) {
    return 'Hakbang $step sa $total';
  }

  @override
  String get onbLangGreeting => 'Kumusta, ako si Ziren! Anong wika ang gusto mong gamitin ko?';

  @override
  String get onbLangTitle => 'Piliin ang inyong wika';

  @override
  String get onbLangSubtitle => 'Ito ang gagamitin ng buong app. Maaari itong palitan kahit kailan sa Settings.';

  @override
  String get onbLangMoreSoon => 'Darating ang Waray at Bisaya kapag nasuri na ng katutubong nagsasalita.';

  @override
  String get onbLangContinue => 'Magpatuloy';

  @override
  String get onbLangSelected => 'Napili';

  @override
  String consentAgreedCount(String done) {
    return '$done sa 2 ang sinang-ayunan';
  }

  @override
  String get consentNeedsReading => 'Buksan para basahin';

  @override
  String get consentAgreed => 'Sinang-ayunan';

  @override
  String get welcomeHeadline => 'Tulong, isang pindot lang.';

  @override
  String get welcomeFeatureReport => 'Mag-report ng sunog, aksidente o medikal na emergency sa loob ng ilang segundo';

  @override
  String get welcomeFeatureStation => 'Diretso sa pinakamalapit na istasyon ng BFP, PNP o MDRRMO ang report mo';

  @override
  String get welcomeFeatureTrack => 'Makikita mo kung papunta na ang responder';

  @override
  String get welcomeNewHere => 'Bago sa Ziren?';

  @override
  String legalMeta(String sections, String minutes) {
    return '$sections na bahagi · mga $minutes minutong basahin';
  }

  @override
  String legalProgress(String percent) {
    return '$percent% ang nabasa';
  }

  @override
  String get legalReachedEnd => 'Naabot mo na ang dulo';

  @override
  String get legalBackToTop => 'Bumalik sa itaas';

  @override
  String get welcomeMascotLine => 'Handa na tayo! Gumawa ng account, o mag-sign in kung mayroon ka na.';

  @override
  String get categoryMissingPerson => 'Nawawalang Tao';

  @override
  String get categoryEmergency => 'Emerhensiya';

  @override
  String get respStatusDispatchedRespond => 'Na-dispatch — Tumugon Na';

  @override
  String get respNextEnRoute => 'Papunta Na (En Route)';

  @override
  String get respNextOnScene => 'Nakarating Na (On Scene)';

  @override
  String get respNextResolved => 'Natapos Na (Resolved)';

  @override
  String get respNoAddress => 'Walang address na naitala';

  @override
  String get respAlertOverdueNote => 'Nakikita na ito ng dispatcher bilang walang sagot. Puwede mo pa ring tanggapin.';

  @override
  String get respAlertTimeoutNote => 'Kapag walang sagot, babalik ito sa dispatcher para may maipadala silang iba.';

  @override
  String get respNoMapApp => 'Walang mabuksang mapa sa telepono na ito.';

  @override
  String get respJustNow => 'ngayon lang';

  @override
  String get wizardSpeakDetails => 'Sabihin ang detalye';

  @override
  String get wizardListening => 'Nakikinig… (pindutin para itigil)';

  @override
  String get wizardNext => 'Susunod →';

  @override
  String get respNavByRoad => 'sa daan';

  @override
  String get respNavRoadNote => 'Sinusundan ng ruta ang mga daan sa mapa. Mag-ingat sa sarado o bahang daan.';

  @override
  String get respNavNearbyNote => 'Malapit ka na. Ilang hakbang na lang ang lugar sa direksyon ng arrow; maglakad na kung hindi na makalapit ang sasakyan.';

  @override
  String get accountNoticeEyebrow => 'Abiso sa account';

  @override
  String get accountWarnedTitle => 'Nakatanggap ka ng babala';

  @override
  String accountWarnedBody(String reason) {
    return 'Dahilan: $reason.';
  }

  @override
  String accountWarnedLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pang babala at masususpinde ang iyong account sa pag-uulat.',
      one: 'Isa pang babala at masususpinde ang iyong account sa pag-uulat.',
    );
    return '$_temp0';
  }

  @override
  String get accountSuspendedTitle => 'Suspendido ang pag-uulat';

  @override
  String accountSuspendedUntil(String date) {
    return 'Hindi ka makakapagpadala ng ulat hanggang $date.';
  }

  @override
  String get accountSuspendedIndefinite => 'Hindi ka makakapagpadala ng ulat hangga\'t walang bagong abiso.';

  @override
  String get accountSuspendedHelp => 'Sa totoong emergency, tumawag sa 911 o sa hotline. Para umapela, makipag-ugnayan sa MDRRMO ng inyong munisipyo.';

  @override
  String get accountOpenHotlines => 'Mga emergency hotline';

  @override
  String get accountReinstatedTitle => 'Maaari ka nang mag-ulat muli';

  @override
  String get accountReinstatedBody => 'Inalis na ang iyong suspensyon.';

  @override
  String get accountWarningsClearedBody => 'Binura na ang iyong mga babala.';

  @override
  String get violationFalseReport => 'Pagpapadala ng mali o birong ulat';

  @override
  String get violationFalseSos => 'Maling paggamit ng SOS button';

  @override
  String get violationSpam => 'Paulit-ulit o dobleng ulat';

  @override
  String get violationAbusive => 'Mapang-abuso o nagbabantang mensahe';

  @override
  String get violationFakeIdentity => 'Paggamit ng peke o hiram na pagkakakilanlan';

  @override
  String get violationOther => 'Paglabag sa mga patakaran sa pag-uulat';

  @override
  String get annWholeProvince => 'Buong probinsya';

  @override
  String get annKindEvacuation => 'Utos na paglikas';

  @override
  String get annKindWeather => 'Abiso sa panahon';

  @override
  String get annKindHazard => 'Babala sa panganib';

  @override
  String get annKindRoadClosure => 'Saradong daan';

  @override
  String get annKindMissingPerson => 'Nawawalang tao';

  @override
  String get annKindAllClear => 'Ligtas na';

  @override
  String get annKindRelief => 'Pamamahagi ng tulong';

  @override
  String get annKindHealth => 'Abiso sa kalusugan';

  @override
  String get annKindDrill => 'Drill';

  @override
  String get annKindUtility => 'Pagkawala ng kuryente / tubig';

  @override
  String get annHazardFlood => 'Baha';

  @override
  String get annHazardLandslide => 'Pagguho ng lupa';

  @override
  String get annHazardStormSurge => 'Daluyong (storm surge)';

  @override
  String get annHazardEarthquake => 'Lindol';

  @override
  String get annHazardTsunami => 'Tsunami';

  @override
  String get annHazardVolcanic => 'Aktibidad ng bulkan';

  @override
  String get annHazardFire => 'Sunog';

  @override
  String get annHazardOther => 'Ibang panganib';

  @override
  String get annRainfallYellow => 'Yellow na babala sa ulan';

  @override
  String get annRainfallOrange => 'Orange na babala sa ulan';

  @override
  String get annRainfallRed => 'Red na babala sa ulan';

  @override
  String annSignal(int n) {
    return 'Signal No. $n';
  }

  @override
  String get annEvacForced => 'Sapilitan';

  @override
  String get annEvacPreemptive => 'Pre-emptive';

  @override
  String annReopens(String when) {
    return 'Bubuksan: $when';
  }

  @override
  String annAge(int age) {
    return 'Edad $age';
  }

  @override
  String get annGoTo => 'Pumunta sa';

  @override
  String get annBring => 'Dalhin';

  @override
  String get annArea => 'Lugar';

  @override
  String get annClosed => 'Sarado';

  @override
  String get annUseInstead => 'Gamitin sa halip';

  @override
  String get annName => 'Pangalan';

  @override
  String get annLastSeen => 'Huling nakita';

  @override
  String get annLooksLike => 'Itsura';

  @override
  String get annCall => 'Tawagan';

  @override
  String get annWhere => 'Saan';

  @override
  String get annFrom => 'Mula sa';

  @override
  String get annNeedHelpTitle => 'Humingi ng tulong';

  @override
  String get annNeedHelpBody => 'Agad na maaabisuhan ang mga istasyon ng inyong bayan, kasama kung nasaan ang cellphone mo. Magdagdag ng isang linya kung kaya - ilan kayo, ano ang nangyayari.';

  @override
  String get annNeedHelpHint => 'hal. Tatlo kami sa bubong, tumataas ang tubig';

  @override
  String get annNeedHelpSend => 'Ipadala: Kailangan ko ng tulong';

  @override
  String get annCancel => 'Kanselahin';

  @override
  String get annSentSafe => 'Naipadala: ligtas ka. Salamat.';

  @override
  String get annSentHelp => 'Naipadala. Naabisuhan na ang mga istasyon ng inyong bayan.';

  @override
  String get annEndedTitle => 'Tapos na ang alertong ito';

  @override
  String get annEndedBody => 'May ipinadalang “ligtas na” o nag-expire na ito, kaya hindi na ito tumatanggap ng sagot. Kung kailangan mo pa ng tulong, tumawag sa hotline.';

  @override
  String get annNotSentTitle => 'Hindi naipadala ang sagot mo';

  @override
  String get annNotSentHelpBody => 'Hindi maabot ng Ziren ang server. Kung kailangan mo ng tulong ngayon, tumawag sa hotline - signal lang ang kailangan ng tawag.';

  @override
  String get annNotSentBody => 'Hindi maabot ng Ziren ang server. Subukan ulit kapag may koneksyon ka na.';

  @override
  String get annAreYouSafe => 'Ligtas ka ba?';

  @override
  String get annImSafe => 'Ligtas ako';

  @override
  String get annINeedHelp => 'Kailangan ko ng tulong';

  @override
  String get annYouSaidSafe => 'Sinabi mong ligtas ka.';

  @override
  String get annYouAskedHelp => 'Humingi ka ng tulong. Naabisuhan na ang mga istasyon.';

  @override
  String get annHelpReached => 'Natanggap ng istasyon ang tawag mo at tumutugon na sila.';

  @override
  String get annHelpWhileWaiting => 'Manatili sa pinakaligtas na lugar. Kung lumala, tumawag sa hotline.';

  @override
  String get annChange => 'Palitan';

  @override
  String get annSafetyAlerts => 'Mga babala';

  @override
  String get annUpdates => 'Iba pang abiso';

  @override
  String annIssuedBy(String office) {
    return 'Mula sa $office';
  }

  @override
  String annUntil(String date) {
    return 'Hanggang $date';
  }

  @override
  String get annEnded => 'Tapos na';

  @override
  String annEndsTitle(String title) {
    return 'Tinatapos: $title';
  }

  @override
  String annEndedBy(String title) {
    return 'Tinapos ng: $title';
  }

  @override
  String get annNotFoundTitle => 'Hindi available';

  @override
  String get annNotFoundBody => 'Inalis na ang abisong ito, o hindi ito para sa inyong lugar.';

  @override
  String annHomeMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pang alerto',
      one: '1 pang alerto',
    );
    return '$_temp0';
  }

  @override
  String get annSeeDetails => 'Tingnan ang detalye';

  @override
  String get annNoticeEyebrow => 'Babala';

  @override
  String get annNoticeEyebrowInfo => 'Abiso';

  @override
  String get annRespondNow => 'Sagutin: ligtas ka ba?';

  @override
  String get annOpen => 'Buksan';

  @override
  String get annHelpAckTitle => 'Natanggap ang tawag mo para sa tulong';

  @override
  String annHelpAckBody(String station) {
    return 'Natanggap ng $station ang hiling mo at tumutugon na sila. Manatili sa pinakaligtas na lugar.';
  }

  @override
  String welcomeDemoTitle(String name) {
    return 'Hi, $name!';
  }

  @override
  String get welcomeDemoTitleNoName => 'Hi!';

  @override
  String get welcomeDemoBodyResident => 'Maligayang pagdating sa Ziren! Gusto mo bang ipakita ko muna sa iyo ang app? Sandali lang ito, at walang maipapadala habang nagpapakita ako.';

  @override
  String get welcomeDemoBodyResponder => 'Maligayang pagdating sa team! Gusto mo bang ipakita ko muna sa iyo ang mga screen mo? Sandali lang ito, at walang mababago habang nagpapakita ako.';

  @override
  String get welcomeDemoStart => 'Oo, ipakita mo';

  @override
  String get welcomeDemoLater => 'Mamaya na lang';

  @override
  String welcomeDemoHint(String button) {
    return 'Mapapanood mo ito anumang oras: pindutin ang \"$button\" sa Home, tapos Demo.';
  }

  @override
  String get respAttachmentsTitle => 'Mga larawan at video mula sa nag-report';

  @override
  String get respAttachmentsLoadFailed => 'Hindi ma-load ang mga attachment. Hilahin pababa para subukan ulit.';

  @override
  String get respAttachmentUnavailable => 'Hindi mabuksan ang file na ito.';

  @override
  String get respAttachmentPlayVideo => 'I-play ang video';

  @override
  String get respAttachmentVideoFailed => 'Hindi mabuksan ang video na ito sa phone na ito.';

  @override
  String get respPhotoViewerClose => 'Isara';

  @override
  String mediaTooLarge(String size, String max) {
    return 'Ang file na ito ay $size MB. Hanggang $max MB lang bawat litrato o video. Mag-record ng mas maikling video o pumili ng mas maliit na file.';
  }

  @override
  String get mediaMaxFiles => 'Hanggang 5 file lang ang puwedeng ilagay.';

  @override
  String speakingLanguageLabel(String language) {
    return 'Wika: $language';
  }

  @override
  String get speakingLanguageTitle => 'Anong wika ang gagamitin mo sa pagsasalita?';

  @override
  String get speakingLanguageMessage => 'Sinasabi nito sa phone kung anong wika ang pakikinggan. Hindi nito binabago ang wika ng app.';

  @override
  String speakingLanguageFallback(String language, String fallback) {
    return 'Walang $language recogniser ang phone na ito. $fallback ang gagamitin sa pakikinig.';
  }

  @override
  String get speakingLanguageNone => 'Walang speech recogniser ang phone para dito. Mag-type na lang.';

  @override
  String speakingLanguageCheck(String language) {
    return 'Tingnan ang mga salita: puwedeng mali ang dinig ng phone sa $language. Ayusin bago ipadala.';
  }

  @override
  String weatherHeadThunderSoon(String time, String name) {
    return 'Malamang may kulog at kidlat bandang $time, $name. Manatili sa loob ng bahay pag nagsimula na.';
  }

  @override
  String weatherHeadHeavyRainSoon(String time, String name) {
    return 'Inaasahan ang malakas na ulan bandang $time, $name. Lumayo sa bahang kalsada at ilog.';
  }

  @override
  String weatherHeadRainingNow(String name) {
    return 'Umuulan ngayon, $name. Mag-ingat kung kailangan mong lumabas.';
  }

  @override
  String weatherHeadRainSoon(String time, String name) {
    return 'Posibleng umulan bandang $time, $name. Magdala ng payong kung aalis ka.';
  }

  @override
  String weatherHeadHeatDanger(String temp, String time, String name) {
    return 'Delikado ang init ngayon, $name: ramdam na $temp bandang $time. Magpalamig at uminom ng tubig.';
  }

  @override
  String weatherHeadHeatHigh(String temp, String time, String name) {
    return 'Mainit mamaya, $name: ramdam na $temp bandang $time. Uminom ng maraming tubig.';
  }

  @override
  String weatherHeadFairDay(String temp, String name) {
    return 'Maayos ang panahon ngayon, $name. $temp sa ngayon.';
  }

  @override
  String weatherHeadFairNight(String temp, String name) {
    return 'Kalmado ang panahon ngayong gabi, $name. $temp sa ngayon.';
  }

  @override
  String get weatherTipThunderIndoors => 'Manatili sa loob habang may kulog at kidlat. Lumayo sa bukid at matataas na puno, at i-unplug ang mga appliance.';

  @override
  String get weatherTipHeavyRainFlood => 'Huwag tumawid sa ilog o bahang kalsada. Kung madaling bahain sa inyo, iakyat ang mahahalagang gamit at ihanda ang go-bag.';

  @override
  String get weatherTipLandslideWatch => 'Malapit sa bundok o dalisdis? Bantayan ang bitak, gumuguhong bato o maputik na tubig, at lumikas agad kapag may nakita.';

  @override
  String get weatherTipUmbrella => 'Magdala ng payong o kapote kung lalabas ka.';

  @override
  String get weatherTipRoadSlippery => 'Madulas ang kalsada. Magmaneho nang dahan-dahan at buksan ang ilaw.';

  @override
  String get weatherTipHeatDangerWork => 'Iwasan ang mabigat na trabaho sa labas mula 10 AM hanggang 4 PM, at bantayan ang matatanda at mga bata.';

  @override
  String get weatherTipHeatStrokeSigns => 'Senyales ng heat stroke: hilo, pagkalito, mainit at tuyong balat. Palamigin ang tao at i-report agad.';

  @override
  String get weatherTipHeatWater => 'Uminom ng tubig nang madalas, kahit hindi nauuhaw.';

  @override
  String get weatherTipHeatShade => 'Sumilong sa tanghali at magsuot ng magaan at maluwag na damit.';

  @override
  String get weatherTipUvStrong => 'Napakatindi ng sikat ng araw. Gumamit ng sombrero o payong sa labas.';

  @override
  String get weatherTipWindStrong => 'Malakas ang hangin. Itali ang maluwag na bubong at lumayo sa puno at kawad ng kuryente.';

  @override
  String get weatherTipGoBagCheck => 'Magandang pagkakataon ang maayos na panahon para i-check ang go-bag at i-save ang mga hotline.';

  @override
  String get weatherCondClear => 'Maaliwalas';

  @override
  String get weatherCondMostlyClear => 'Halos maaliwalas';

  @override
  String get weatherCondPartlyCloudy => 'Bahagyang maulap';

  @override
  String get weatherCondCloudy => 'Maulap';

  @override
  String get weatherCondFog => 'Mahamog';

  @override
  String get weatherCondDrizzle => 'Ambon';

  @override
  String get weatherCondRain => 'Ulan';

  @override
  String get weatherCondHeavyRain => 'Malakas na ulan';

  @override
  String get weatherCondThunderstorm => 'Kulog at kidlat';

  @override
  String get weatherHeatCaution => 'Mag-ingat';

  @override
  String get weatherHeatExtremeCaution => 'Labis na pag-iingat';

  @override
  String get weatherHeatDanger => 'Delikado';

  @override
  String get weatherHeatExtremeDanger => 'Labis na delikado';

  @override
  String get weatherCardTitle => 'Panahon';

  @override
  String weatherFeelsLike(String temp) {
    return 'Ramdam ay $temp';
  }

  @override
  String get weatherTipsTitle => 'Paalala ni Ziren';

  @override
  String get weatherNow => 'Ngayon';

  @override
  String get weatherToday => 'Ngayong araw';

  @override
  String get weatherTomorrow => 'Bukas';

  @override
  String weatherSourceNote(String time) {
    return 'Forecast mula sa Open-Meteo, na-update $time. Para sa opisyal na babala, sundan ang PAGASA at ang MDRRMO.';
  }

  @override
  String weatherOldNote(String time) {
    return 'Forecast mula $time ang ipinapakita. Mag-a-update ito pagbalik ng internet.';
  }

  @override
  String get weatherRemindersToggle => 'Paalalahanan ako bago ang malakas na ulan o delikadong init';

  @override
  String get weatherRemindersHint => 'Mga isang oras bago, kahit nakasara ang app.';

  @override
  String get weatherLoading => 'Tinitingnan ang panahon…';

  @override
  String get weatherUnavailable => 'Hindi makuha ang forecast sa ngayon. Hilahin pababa para subukan ulit.';

  @override
  String weatherRainChanceLabel(String chance) {
    return '$chance tsansa ng ulan';
  }

  @override
  String get weatherNotifRainTitle => 'Uulan sa loob ng mga isang oras';

  @override
  String get weatherNotifHeavyRainTitle => 'Malakas na ulan sa loob ng mga isang oras';

  @override
  String get weatherNotifThunderTitle => 'Kulog at kidlat sa loob ng mga isang oras';

  @override
  String weatherNotifHeatTitle(String time) {
    return 'Delikadong init mula $time';
  }

  @override
  String get weatherChannelName => 'Paalala sa panahon';

  @override
  String get weatherChannelDescription => 'Paalala mga isang oras bago ang malakas na ulan, kulog at kidlat, o delikadong init.';

  @override
  String get regNameMismatchTitle => 'Hindi tugma ang pangalan sa ID mo';

  @override
  String regNameMismatchBody(String parts) {
    return 'Hindi namin makita sa ID mo ang: $parts. I-type ang pangalan mo nang eksakto gaya ng nakalimbag sa ID, o kumuha ng mas malinaw na litrato nito.';
  }

  @override
  String regNamePartFirst(String value) {
    return 'pangalan na \"$value\"';
  }

  @override
  String regNamePartMiddle(String value) {
    return 'gitnang pangalan na \"$value\"';
  }

  @override
  String regNamePartLast(String value) {
    return 'apelyido na \"$value\"';
  }

  @override
  String get regFixName => 'Itama ang pangalan ko';

  @override
  String get regRetakeId => 'Kunan ulit ang ID';

  @override
  String get regAgencyIdNeeded => 'Kunan ng litrato ang agency ID mo para makapagpatuloy.';

  @override
  String get regAgencyIdReading => 'Binabasa ang ID mo...';

  @override
  String get regAgencyIdNameOk => 'Tugma ang pangalan sa ID mo.';

  @override
  String get regVerificationRequired => 'Kailangan ang ID at selfie mo para matapos ang pag-register. Sinusuri ng Ziren ang bawat account para galing sa totoong tao ang bawat ulat.';

  @override
  String get reportNeedsVerificationTitle => 'I-verify ang account para makapag-ulat';

  @override
  String get reportNeedsVerificationBody => 'Para maiwasan ang maling ulat, ang mga residenteng na-verify ng administrator lang ang makakapagpadala ng ulat. Idagdag ang balidong ID at selfie mo. Kung may emergency ngayon, tumawag sa hotline.';

  @override
  String get reportPendingVerificationTitle => 'Hinihintay ang administrator';

  @override
  String get reportPendingVerificationBody => 'Sinusuri pa ang ID mo. Makakapagpadala ka ng ulat kapag naaprubahan na ito ng administrator. Kung may emergency ngayon, tumawag sa hotline.';

  @override
  String get reportVerifyNow => 'I-verify ang account ko';

  @override
  String get meetCodeTitleReporter => 'Ang Ziren code mo';

  @override
  String get meetCodeBodyReporter => 'Pagdating ng mga responder, itatanong nila ang code na ito. Sabihin ito sa kanila para malaman nilang ikaw ang nag-report. Huwag muna itong ibigay sa iba.';

  @override
  String get meetCodeTitleResponder => 'Itanong sa nag-report ang Ziren code niya';

  @override
  String get meetCodeBodyResponder => 'Sasabihin sa iyo ng nag-report ang code na ito. Kilalanin sila sa code, hindi sa itsura o kasarian nila.';

  @override
  String meetCodeSemantics(String digits) {
    return 'Ziren code $digits';
  }

  @override
  String get sosWhatKind => 'Anong klaseng emergency?';

  @override
  String get sosWhatKindHelp => 'Para maipadala ang tamang koponan sa tamang lugar.';

  @override
  String get sosChooseKindHint => 'Piliin muna sa itaas kung anong klaseng emergency';

  @override
  String get sosConfirmHint => 'I-check muna ang kahon sa itaas para magpatuloy';

  @override
  String get sosFallbackReminder => 'Kung buhay ang nakataya, tumawag din agad sa 911. Isang tunay na dispatcher ang sumusuri sa report na ito — hindi AI.';

  @override
  String get respNotesTitle => 'Mga update mula sa lugar';

  @override
  String get respNotesEmpty => 'Wala pang update. Idagdag ang mga nakikita mo habang tumutugon.';

  @override
  String get respNotesHint => 'Hal. Umabot na ang apoy sa ikalawang palapag.';

  @override
  String get respNotesLoadError => 'Hindi ma-load ang mga update.';

  @override
  String get regMiddleNameHelp => 'Isulat ang buong gitnang pangalan gaya ng nasa ID - halimbawa Santos, hindi S. Inisyal lang kung inisyal lang ang nakasulat sa ID.';

  @override
  String regMiddleInitialBody(String value) {
    return 'Inisyal lang ang \"$value\" ng gitnang pangalan mo. Buo ito sa ID mo, kaya i-type ang buong gitnang pangalan (halimbawa Santos, hindi S.).';
  }

  @override
  String get verifyNameLabel => 'Pangalan mo, gaya ng nakasulat sa ID';

  @override
  String get verifyNameHelp => 'Pangalan, gitnang pangalan at apelyido. Isulat nang buo ang gitnang pangalan (halimbawa Santos, hindi S.) maliban kung inisyal lang ang nasa ID.';

  @override
  String get verifyNameSaveError => 'Hindi ma-save ang pangalan mo. Subukan ulit.';

  @override
  String get accountVerifiedTitle => 'Verified na ang account mo';

  @override
  String get accountVerifiedBody => 'Nasuri na ng administrator ang ID mo. Makakapagpadala ka na ng emergency report sa Ziren.';

  @override
  String get accountVerifyRejectedTitle => 'Hindi na-verify ang ID mo';

  @override
  String get accountVerifyRejectedBody => 'Hindi makumpirma ng administrator kung sino ka mula sa mga litrato. Magpadala ng malinaw na litrato ng ID mo, kasama ang pangalan mo gaya ng nakasulat dito, at bagong selfie.';

  @override
  String get accountVerifyAgain => 'Mag-verify ulit';

  @override
  String get homeChooseIncidentTitle => 'Pumili ng insidente';

  @override
  String get homeChooseIncidentBody => 'I-tap kung ano ang nangyayari para i-report: sunog, medikal, aksidente, krimen, kalamidad o iba pa.';

  @override
  String weatherMoodStorm(String time) {
    return 'May kidlat at ulan mula $time';
  }

  @override
  String weatherMoodHeavyRain(String time) {
    return 'Malakas na ulan mula $time';
  }

  @override
  String get weatherMoodRainingNow => 'Umuulan ngayon';

  @override
  String weatherMoodRainSoon(String time) {
    return 'Uulan mula $time';
  }

  @override
  String get weatherMoodHeatDanger => 'Delikadong init';

  @override
  String get weatherMoodHeat => 'Mainit ngayon';

  @override
  String get weatherMoodFair => 'Maaliwalas ang panahon';

  @override
  String get weatherMoodFairNight => 'Payapang gabi';

  @override
  String get weatherMeterRain => 'Ulan';

  @override
  String get weatherMeterHeat => 'Init';

  @override
  String get weatherRainNone => 'Walang ulan';

  @override
  String get weatherRainLight => 'Mahina';

  @override
  String get weatherRainModerate => 'Katamtaman';

  @override
  String get weatherRainHeavy => 'Malakas';

  @override
  String get weatherRainIntense => 'Napakalakas';

  @override
  String get weatherRainTorrential => 'Bumubuhos';

  @override
  String get weatherHeatNormal => 'Normal';

  @override
  String weatherMeterFrom(String time) {
    return 'mula $time';
  }

  @override
  String weatherMeterPeak(String temp, String time) {
    return '$temp bandang $time';
  }

  @override
  String get weatherMeterToday => 'ngayong araw';
}
