// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get regIdTypeTitle => 'Choose an ID';

  @override
  String get regIdTypeSubtitle => 'We use it once, to confirm you are a real person in Biliran.';

  @override
  String get actionTakePhoto => 'Take a photo';

  @override
  String get regTakeIdPhoto => 'Take a photo of your ID';

  @override
  String get regIdPhotoTips => 'Flat, well lit, all four corners visible';

  @override
  String get regIdReadable => 'Your ID looks readable.';

  @override
  String get reportReceivedTitle => 'Report Received';

  @override
  String get reportReceivedBody => 'Your report is now with the dispatcher.';

  @override
  String get recordedAs => 'Recorded as';

  @override
  String get sentTo => 'Sent to';

  @override
  String get locationAttached => 'Location attached';

  @override
  String mediaAttached(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos or videos',
      one: '1 photo or video',
    );
    return '$_temp0';
  }

  @override
  String get reportIdLabel => 'Report ID';

  @override
  String get trackReport => 'Track Report';

  @override
  String get backToHome => 'Back to Home';

  @override
  String get myReportsTitle => 'My Reports';

  @override
  String get filterAll => 'All';

  @override
  String get filterOpen => 'Active';

  @override
  String get filterDone => 'Resolved';

  @override
  String get statusReceived => 'Received';

  @override
  String get statusProcessing => 'Being reviewed';

  @override
  String get statusDispatched => 'Responder on the way';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get notifStatusTitle => 'Report update';

  @override
  String get notifStatusProcessing => 'Your report is being reviewed.';

  @override
  String get notifStatusDispatched => 'A responder is on the way.';

  @override
  String get notifStatusResolved => 'Your report has been marked resolved.';

  @override
  String get notifStatusCancelled => 'Your report was cancelled.';

  @override
  String get notifStatusOk => 'Got it';

  @override
  String get noReportsYet => 'No reports yet';

  @override
  String get noReportsYetBody => 'Reports you submit will appear here.';

  @override
  String get noOpenReports => 'No open reports';

  @override
  String get noOpenReportsBody => 'All your reports are closed.';

  @override
  String get noResolvedYet => 'Nothing resolved yet';

  @override
  String get noResolvedYetBody => 'Resolved reports will appear here.';

  @override
  String get noDetails => 'No details';

  @override
  String get retry => 'Try again';

  @override
  String get groupToday => 'Today';

  @override
  String get groupYesterday => 'Yesterday';

  @override
  String get groupThisWeek => 'This week';

  @override
  String get groupThisMonth => 'This month';

  @override
  String get groupOlder => 'Older';

  @override
  String get categoryFire => 'Fire';

  @override
  String get categoryMedicalTrauma => 'Medical / Trauma';

  @override
  String get categoryVehicular => 'Road Accident';

  @override
  String get categoryFloodLandslideCalamity => 'Flood / Landslide / Calamity';

  @override
  String get categoryDomesticDisputeCrime => 'Disturbance / Crime';

  @override
  String get categoryOther => 'Other';

  @override
  String get preferredLanguage => 'Language';

  @override
  String reportsOpenCount(int open, int total) {
    return '$open open · $total total';
  }

  @override
  String reportsAllDone(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total reports · all closed',
      one: '1 report · closed',
    );
    return '$_temp0';
  }

  @override
  String get noReportsYetLong => 'When you report an emergency, every step of the response will show up here.';

  @override
  String get consentTitle => 'Before you start';

  @override
  String get consentSubtitle => 'Please read and agree to both documents below.';

  @override
  String get consentSummaryTitle => 'The short version';

  @override
  String get consentSummaryLocation => 'We use your location and contact details so responders can find you.';

  @override
  String get consentSummaryReporting => 'You can always report an emergency, verified or not.';

  @override
  String get consentSummaryPhotos => 'Your ID and face photos are private, and deleted once checked.';

  @override
  String get consentSummaryNotHotline => 'Ziren does not replace 911. Call directly if the app cannot reach the network.';

  @override
  String get consentPrivacyTitle => 'Data Privacy Notice';

  @override
  String get consentPrivacySubtitle => 'What we collect and why';

  @override
  String get consentTermsTitle => 'Terms of Use';

  @override
  String get consentTermsSubtitle => 'What Ziren does, and what it does not do';

  @override
  String get consentActionRead => 'Read';

  @override
  String get consentBadgeRead => 'Read';

  @override
  String get consentAgreePrivacy => 'I agree to the Data Privacy Notice';

  @override
  String get consentAgreeTerms => 'I agree to the Terms of Use';

  @override
  String get consentMustReadFirst => 'Open each document first.';

  @override
  String get consentContinue => 'Agree and continue';

  @override
  String get legalReadConfirm => 'I have read this';

  @override
  String get legalScrollHint => 'Scroll to the end to continue';

  @override
  String get legalClose => 'Close';

  @override
  String get legalLoadError => 'This document could not be opened. Please update the app or contact your MDRRMO office.';

  @override
  String get welcomeTagline => 'Emergency response for Biliran.';

  @override
  String get welcomeSignIn => 'Sign in';

  @override
  String get welcomeCreateAccount => 'Create an account';

  @override
  String get welcomeHasAccount => 'Already registered?';

  @override
  String get homeOnline => 'Online';

  @override
  String get homeOffline => 'Offline';

  @override
  String get homeConnecting => 'Connecting';

  @override
  String get homeEmergency => 'EMERGENCY';

  @override
  String get categoryFireShort => 'Fire';

  @override
  String get categoryMedicalShort => 'Medical';

  @override
  String get categoryCrimeShort => 'Crime';

  @override
  String get categoryCalamityShort => 'Calamity';

  @override
  String get categoryAccidentShort => 'Accident';

  @override
  String get categoryOtherShort => 'Other';

  @override
  String get homeLocation => 'Location';

  @override
  String get homeTimeNow => 'Time now';

  @override
  String get homeRouting => 'Routing';

  @override
  String homeBarangay(String name) {
    return 'Brgy. $name';
  }

  @override
  String get homeLocationUnknown => 'Not known yet';

  @override
  String get homeRoutingAuto => 'Automatic';

  @override
  String get homeSosHint => 'Not sure? Press this';

  @override
  String get homeResidentFallbackName => 'Resident';

  @override
  String get homeMapAction => 'Map';

  @override
  String get homeDeliveryOnlineTitle => 'Connected';

  @override
  String get homeDeliveryOnlineDetail => 'Your report goes straight to the nearest station.';

  @override
  String get homeDeliveryOfflineTitle => 'No internet';

  @override
  String get homeDeliveryOfflineDetail => 'Reports can\'t be sent right now. If this is an emergency, call 911 directly.';

  @override
  String get homeDeliveryCheckingTitle => 'Checking connection';

  @override
  String get homeDeliveryCheckingDetail => 'Checking whether the server can be reached.';

  @override
  String get homeBellLabel => 'Notifications';

  @override
  String get homeBellLabelUnread => 'Notifications, new items';

  @override
  String homeReportAction(String category) {
    return 'Report $category';
  }

  @override
  String get homeAlerts => 'Alerts';

  @override
  String get homeAlertsEmpty => 'No new alerts. Updates on your reports will appear here.';

  @override
  String get homeTapToView => 'Tap to view';

  @override
  String get homeSafePlaces => 'Safe places';

  @override
  String get homeStationsUnavailable => 'Could not load the station list.';

  @override
  String homeStationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stations',
      one: '1 station',
    );
    return '$_temp0';
  }

  @override
  String get agencyMdrrmo => 'MDRRMO';

  @override
  String get agencyPnp => 'Police';

  @override
  String get agencyBfp => 'Fire';

  @override
  String get homeMyReports => 'Your reports';

  @override
  String get homeSeeAll => 'All';

  @override
  String get homeNoReportsTitle => 'Nothing yet';

  @override
  String get homeNoReportsBody => 'When you report an incident, you will see its status here.';

  @override
  String get homeUntitledReport => 'Report';

  @override
  String homeGreetingMorning(String name) {
    return 'Good morning, $name!';
  }

  @override
  String homeGreetingAfternoon(String name) {
    return 'Good afternoon, $name!';
  }

  @override
  String homeGreetingEvening(String name) {
    return 'Good evening, $name!';
  }

  @override
  String get homeStayAlertBody => 'Stay alert. Help is always near.';

  @override
  String get homeReportCtaTitle => 'Report an Emergency';

  @override
  String get homeReportCtaSubtitle => 'The fastest way to reach a station — pick what\'s wrong, hold to send';

  @override
  String get homeReportCtaBadge => 'FASTEST';

  @override
  String get homeRecentActivity => 'Recent activity';

  @override
  String get timeAgoJustNow => 'just now';

  @override
  String timeAgoMinutes(int count) {
    return '${count}m ago';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h ago';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}d ago';
  }

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitle => 'Report an emergency, or respond to one.';

  @override
  String get fieldEmail => 'Email address';

  @override
  String get hintEmail => 'you@example.com';

  @override
  String get fieldPassword => 'Password';

  @override
  String get hintPassword => 'Enter your password';

  @override
  String get validationPasswordRequired => 'Password is required.';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginButton => 'Sign in';

  @override
  String get loginNewToZiren => 'New to Ziren?';

  @override
  String get loginCreateAccount => 'Create an account';

  @override
  String get regHaveAccount => 'Already have an account?';

  @override
  String get authLegalIntro => 'By continuing, you agree to Ziren\'s';

  @override
  String get authLegalAnd => 'and';

  @override
  String get actionClose => 'Close';

  @override
  String get forgotSendLink => 'Send reset link';

  @override
  String get forgotBackToSignIn => 'Back to sign in';

  @override
  String get forgotSentBody => 'If an account exists for that email, a password reset link has been sent.';

  @override
  String get pendingTitle => 'Account pending approval';

  @override
  String get pendingBody => 'Your Responder account has been created and is waiting for verification by your Agency Admin.';

  @override
  String get pendingStep1 => 'Your Agency Admin reviews your badge ID';

  @override
  String get pendingStep2 => 'They confirm it against agency records';

  @override
  String get pendingStep3 => 'You are notified as soon as the account is approved';

  @override
  String get rejectedTitle => 'Account not approved';

  @override
  String get rejectedBody => 'Your Responder account was not approved by your Agency Admin. The most common reason is a badge ID that could not be matched to agency records.';

  @override
  String get rejectedStep1 => 'Contact your agency directly to confirm your badge ID';

  @override
  String get rejectedStep2 => 'Ask your Agency Admin to review the account again';

  @override
  String get pendingWhatNext => 'What happens next';

  @override
  String get actionLogOut => 'Log out';

  @override
  String get navHome => 'Home';

  @override
  String get navReports => 'Reports';

  @override
  String get navZirenAi => 'Ziren AI';

  @override
  String get navMap => 'Map';

  @override
  String get navProfile => 'Profile';

  @override
  String get forgotTitle => 'Reset password';

  @override
  String get forgotSentTitle => 'Check your email';

  @override
  String get forgotSubtitle => 'Enter your email address and we will send you a link to set a new one.';

  @override
  String get regRoleTitle => 'Create account';

  @override
  String get regRoleSubtitle => 'Which of these are you?';

  @override
  String get roleResident => 'Resident';

  @override
  String get roleResponder => 'Responder';

  @override
  String get regRoleResidentBody => 'Report emergencies where you live, and follow what happens to your report.';

  @override
  String get regRoleResponderBody => 'BFP, PNP or MDRRMO. Your Agency Admin approves the account before you can use it.';

  @override
  String get regNameTitle => 'Your name';

  @override
  String get regNameSubtitle => 'Enter it exactly as it appears on your ID.';

  @override
  String get fieldFirstName => 'First name';

  @override
  String get hintFirstName => 'Juan';

  @override
  String get fieldMiddleName => 'Middle name';

  @override
  String get hintMiddleName => 'Santos';

  @override
  String get fieldLastName => 'Last name';

  @override
  String get hintLastName => 'dela Cruz';

  @override
  String get fieldSuffix => 'Suffix';

  @override
  String get hintSuffix => 'Jr, Sr, III';

  @override
  String get fieldDateOfBirth => 'Date of birth';

  @override
  String get regChooseDob => 'Choose your date of birth';

  @override
  String get regDobWhy => 'A responding crew treats a 3-year-old and a 40-year-old differently for the same symptoms.';

  @override
  String get fieldSex => 'Sex';

  @override
  String get sexMale => 'Male';

  @override
  String get sexFemale => 'Female';

  @override
  String get sexPreferNotToSay => 'Prefer not to say';

  @override
  String get regAddressTitle => 'Where you live';

  @override
  String get regAddressSubtitle => 'This decides which station responds to you.';

  @override
  String get fieldMunicipality => 'Municipality';

  @override
  String get hintMunicipality => 'Choose your municipality';

  @override
  String get fieldBarangay => 'Barangay';

  @override
  String get fieldPurok => 'Purok or sitio';

  @override
  String get hintPurok => 'Purok 3';

  @override
  String get fieldStreet => 'Street or landmark';

  @override
  String get hintStreet => 'Rizal St, beside the chapel';

  @override
  String get regStreetHelp => 'What helps a crew find your door';

  @override
  String get regChooseMunicipalityFirst => 'Choose a municipality first';

  @override
  String get hintBarangay => 'Choose your barangay';

  @override
  String get regUseMyLocation => 'Use my location';

  @override
  String get regFindingYou => 'Finding you...';

  @override
  String get regLocationDenied => 'Location permission was declined.';

  @override
  String get regLocationSet => 'Municipality set from your location.';

  @override
  String get regLocationFailed => 'Could not read your location. Choose it below.';

  @override
  String get regNotInBiliran => 'You do not appear to be in Biliran right now. Choose your home municipality below.';

  @override
  String get regBarangayListFailed => 'Could not load the barangay list. Check your connection.';

  @override
  String get actionRetry => 'Retry';

  @override
  String get regContactTitle => 'How we reach you';

  @override
  String get regContactSubtitle => 'A responder may need to call you on the way.';

  @override
  String get fieldMobile => 'Mobile number';

  @override
  String get hintMobile => '09XX XXX XXXX';

  @override
  String get hintCreatePassword => 'Create a password';

  @override
  String get passwordRule => 'Min 8 characters, 1 uppercase, 1 number';

  @override
  String get passwordReqTitle => 'Your password must have:';

  @override
  String passwordReqLength(int count) {
    return 'At least $count characters';
  }

  @override
  String get passwordReqUpper => '1 uppercase letter (A-Z)';

  @override
  String get passwordReqNumber => '1 number (0-9)';

  @override
  String get passwordConfirmHint => 'Type the same password again.';

  @override
  String get fieldConfirmPassword => 'Confirm password';

  @override
  String get hintConfirmPassword => 'Re-enter your password';

  @override
  String get fieldEmergencyContact => 'Emergency contact';

  @override
  String get hintName => 'Name';

  @override
  String get hintTheirMobile => 'Their mobile number';

  @override
  String get regEmergencyWhoTitle => 'Emergency contact person';

  @override
  String get regEmergencyWhoBody => 'Add ONE other person we can call if something happens to YOU — for example a parent, spouse, sibling or close friend. Enter THEIR name and number, not your own. You can skip this.';

  @override
  String get hintEmergencyName => 'Their full name (not yours)';

  @override
  String get hintEmergencyNumber => 'Their mobile number (not yours)';

  @override
  String get regEmergencyNeedsNumber => 'Add their mobile number too, or clear their name.';

  @override
  String get regEmergencyNeedsName => 'Add their name too, or clear the number.';

  @override
  String get regEmergencySameAsYours => 'That is your own number. Enter the number of someone else — the person we should call about you.';

  @override
  String get emergencyWhoShort => 'The person we should call if something happens to YOU — a family member, a friend or someone you trust. Enter THEIR name and number, not your own.';

  @override
  String get hintPwdId => 'PWD ID number';

  @override
  String get pwdIdHelp => 'Issued by your MSWDO or PDAO - also proves residency';

  @override
  String get hintAccessibilityNotes => 'Anything else that would help (optional)';

  @override
  String get contactModeAny => 'Any way';

  @override
  String get contactModeSms => 'Text only';

  @override
  String get contactModeApp => 'In-app only';

  @override
  String get contactModeVoice => 'Calling is fine';

  @override
  String get regIsPwd => 'I am a person with disability';

  @override
  String get regAccessibility => 'Accessibility';

  @override
  String get regAccessibilityWhy => 'So a crew arrives prepared. Optional.';

  @override
  String get regAccessibilityAsk => 'What should a crew know before they arrive?';

  @override
  String get regContactModeAsk => 'How should we contact you?';

  @override
  String get regAgencyTitle => 'Your agency';

  @override
  String get regAgencySubtitle => 'Your Agency Admin checks these before approving you.';

  @override
  String get fieldAgency => 'Agency';

  @override
  String get fieldBadgeId => 'Badge or employee ID';

  @override
  String get hintBadgeId => 'As issued by your agency';

  @override
  String get fieldRank => 'Rank or position';

  @override
  String get hintRank => 'SFO1, PCpl, Rescue Team Leader';

  @override
  String get fieldUnit => 'Unit or station';

  @override
  String get hintUnit => 'Naval Fire Station';

  @override
  String get fieldDateJoined => 'Date you joined';

  @override
  String get fieldAgencyIdPhoto => 'Photo of your agency ID';

  @override
  String get regTakeAgencyIdPhoto => 'Take a photo of your agency ID';

  @override
  String get regChooseDate => 'Choose a date';

  @override
  String get regAgencyIdWhy => 'Speeds up approval considerably - your admin can check the badge number without calling your station.';

  @override
  String get regIdBestChoice => 'Best choice';

  @override
  String get regIdProvesResidency => 'Also proves you live in Biliran';

  @override
  String get regIdAlsoAccepted => 'Also accepted';

  @override
  String get regIdIdentityOnly => 'Proves who you are, but not where you live';

  @override
  String get actionChooseFromGallery => 'Choose from gallery';

  @override
  String get regIdCaptureTitle => 'Photograph your ID';

  @override
  String get fieldIdNumber => 'ID number';

  @override
  String get hintIdNumber => 'As printed on the card';

  @override
  String get regReadingId => 'Reading your ID...';

  @override
  String get regOcrFilled => 'Filled in from your photo - correct it if it is wrong';

  @override
  String get regIdPrivacyNote => 'This photo is private. It is never shown publicly, never seen by responders, and is deleted once an administrator has checked it.';

  @override
  String get regIdUnreadable => 'We could not read much from that photo. You can still continue - just type the number below. A clearer photo helps the reviewer.';

  @override
  String get actionRetake => 'Retake';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionTakePhotoShort => 'Take photo';

  @override
  String get selfieFramingNone => 'Put your face inside the circle';

  @override
  String get selfieFramingMultiple => 'Only one face, please';

  @override
  String get selfieFramingTooFar => 'Move a little closer';

  @override
  String get selfieFramingTooClose => 'Move a little further back';

  @override
  String get selfieFramingOffCentre => 'Centre your face';

  @override
  String get selfieAutoCapture => 'We take the photo automatically once you do.';

  @override
  String get selfieOrManual => 'Or take the photo yourself.';

  @override
  String get selfieTitle => 'Take a selfie';

  @override
  String get selfieReviewTitle => 'How does this look?';

  @override
  String get selfieSubtitle => 'So an administrator can match your face to your ID.';

  @override
  String get selfieReviewSubtitle => 'Make sure your face is clear and well lit.';

  @override
  String get selfieCameraError => 'Could not open the camera. Check that Ziren has camera permission in your phone settings.';

  @override
  String get selfieCaptureError => 'Could not take the photo. Please try again.';

  @override
  String get regReviewTitle => 'Check your details';

  @override
  String get regReviewSubtitle => 'Tap anything to change it.';

  @override
  String get regGroupAboutYou => 'About you';

  @override
  String get regGroupAddress => 'Where you live';

  @override
  String get regGroupContact => 'Contact';

  @override
  String get regGroupAgency => 'Agency';

  @override
  String get regGroupIdentity => 'Identity';

  @override
  String get actionChange => 'Change';

  @override
  String get regReenterPassword => 'Re-enter your password';

  @override
  String get hintYourPassword => 'Your password';

  @override
  String get regVerifyNowInstead => 'Verify now instead';

  @override
  String get regVerificationSkipped => 'Verification skipped';

  @override
  String get valueNotGiven => 'Not given';

  @override
  String get valueAttached => 'Attached';

  @override
  String get labelName => 'Name';

  @override
  String get labelDateOfBirth => 'Date of birth';

  @override
  String get labelSex => 'Sex';

  @override
  String get labelMunicipality => 'Municipality';

  @override
  String get labelBarangay => 'Barangay';

  @override
  String get labelPurok => 'Purok or sitio';

  @override
  String get labelStreet => 'Street';

  @override
  String get labelEmail => 'Email';

  @override
  String get labelMobile => 'Mobile';

  @override
  String get labelEmergencyContact => 'Emergency contact';

  @override
  String get labelAccessibility => 'Accessibility';

  @override
  String get labelBadgeId => 'Badge ID';

  @override
  String get labelRank => 'Rank';

  @override
  String get labelUnit => 'Unit';

  @override
  String get labelAgencyIdPhoto => 'Agency ID photo';

  @override
  String get labelIdType => 'ID type';

  @override
  String get labelIdNumber => 'ID number';

  @override
  String get labelIdPhoto => 'ID photo';

  @override
  String get regSelfieAttached => 'Selfie attached for identity checking.';

  @override
  String get regSkippedNotice => 'Your account will work straight away and you can report emergencies. Finish verification later from your profile.';

  @override
  String get regSkipDialogTitle => 'Skip verification for now?';

  @override
  String get actionGoBack => 'Go back';

  @override
  String get actionSkipForNow => 'Skip for now';

  @override
  String get regSkipDialogBody => 'Your account will be created and you can report emergencies straight away.\n\nA dispatcher will see that your identity has not been checked yet. You can finish this any time from your profile.';

  @override
  String get regSkipLink => 'I need help right now - skip this';

  @override
  String get profilePersonalInfo => 'Personal Info';

  @override
  String get labelNameProfile => 'Name';

  @override
  String get labelEmailProfile => 'Email';

  @override
  String get labelPhone => 'Phone';

  @override
  String get profileAddress => 'Address';

  @override
  String get labelBarangayProfile => 'Barangay';

  @override
  String get labelMunicipalityProfile => 'Municipality';

  @override
  String get profileAccount => 'Account';

  @override
  String get labelRole => 'Role';

  @override
  String get labelStatus => 'Status';

  @override
  String get profileEmergencyContact => 'Emergency Contact';

  @override
  String get labelNumber => 'Number';

  @override
  String get profileNotSet => 'Not set';

  @override
  String get labelEmergencyContactName => 'Contact name';

  @override
  String get labelEmergencyContactNumber => 'Contact number';

  @override
  String get profileAccountVerified => 'Account verified';

  @override
  String get profileAccountVerifiedBody => 'Your identity is confirmed. You get priority support during emergencies.';

  @override
  String get profileVerifyLearnMore => 'Learn more';

  @override
  String profileStaleWarning(String message) {
    return 'Details below may be out of date.';
  }

  @override
  String get actionRetryProfile => 'Retry';

  @override
  String get settingsProfile => 'Profile';

  @override
  String get fieldFullName => 'Full Name';

  @override
  String get fieldMobileNumber => 'Mobile Number';

  @override
  String get hintMobileShort => '09xxxxxxxxx';

  @override
  String get settingsAddress => 'Address';

  @override
  String get fieldBarangaySettings => 'Barangay';

  @override
  String get hintBarangayExample => 'e.g. Brgy. Caraycaray';

  @override
  String get fieldMunicipalitySettings => 'Municipality';

  @override
  String get hintMunicipalityExample => 'e.g. Naval';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get settingsEmergencyContact => 'Emergency Contact';

  @override
  String get fieldContactName => 'Contact person\'s name';

  @override
  String get hintContactName => 'Their full name, e.g. Maria Santos';

  @override
  String get fieldContactNumber => 'Contact person\'s number';

  @override
  String get verifyWhichId => 'Which ID will you show?';

  @override
  String get verifyIdPhoto => 'Photo of the ID';

  @override
  String get verifyIdNumber => 'ID number';

  @override
  String get verifySelfie => 'Selfie (optional but helps)';

  @override
  String get verifySubmit => 'Submit for review';

  @override
  String get actionDone => 'Done';

  @override
  String get verifyTitle => 'Verify your account';

  @override
  String get verifyChooseId => 'Choose an ID';

  @override
  String get verifyTakeIdPhoto => 'Take a photo of your ID';

  @override
  String get verifyTakeSelfie => 'Take a selfie';

  @override
  String get verifySentTitle => 'Sent for review';

  @override
  String get verifyNotSignedIn => 'You are not signed in.';

  @override
  String get verifyIntro => 'This is optional. You can already report emergencies without it - verifying just tells a dispatcher your reports come from a confirmed resident.';

  @override
  String get verifySentBody => 'An administrator will check your ID. Nothing changes for you in the meantime - keep using Ziren exactly as before.';

  @override
  String get verifyPrivacyNote => 'Your photos are private, never shown to responders, and deleted once an administrator has checked them.';

  @override
  String get bannerInReview => 'Verification in review';

  @override
  String get bannerFinishVerifying => 'Finish verifying your account';

  @override
  String get bannerVerifyNow => 'Verify now';

  @override
  String get bannerNotNow => 'Not now';

  @override
  String get bannerInReviewBody => 'An administrator is checking your ID. You can keep using Ziren normally in the meantime.';

  @override
  String get bannerFinishBody => 'Add a valid ID so a dispatcher knows your reports come from a real resident. You can report emergencies either way.';

  @override
  String get badgeRequired => 'REQUIRED';

  @override
  String get badgeOptional => 'OPTIONAL';

  @override
  String get badgeAuto => 'AUTO';

  @override
  String get reportTitle => 'Report an Emergency';

  @override
  String get reportSectionWhat => 'WHAT - Type of Emergency';

  @override
  String get reportExtraDetails => 'More details';

  @override
  String get reportSectionHow => 'HOW - Details';

  @override
  String get reportOverlapQuestion => 'Anything else to worry about?';

  @override
  String get reportSelectAllApply => 'Select all that apply';

  @override
  String get reportLocation => 'Location';

  @override
  String get reportNoGps => 'No GPS - it can still be sent without it';

  @override
  String get reportFindingLocation => 'Finding your location...';

  @override
  String get reportGpsAcquired => 'GPS acquired';

  @override
  String get reportFindingAddress => 'Finding the address...';

  @override
  String get reviewTitle => 'Review your report';

  @override
  String get reviewTypeOfEmergency => 'TYPE OF EMERGENCY';

  @override
  String get reviewDetails => 'DETAILS';

  @override
  String get reviewAlsoInvolved => 'ALSO INVOLVED';

  @override
  String get reviewLocation => 'LOCATION';

  @override
  String get reviewRelationship => 'RELATIONSHIP TO THE VICTIM';

  @override
  String get reviewExtraDetails => 'MORE DETAILS';

  @override
  String get reviewNoGps => 'GPS not available';

  @override
  String get reviewFalseReportWarning => 'Filing a false report carries legal penalties. Make sure all the information is correct.';

  @override
  String get reviewSubmit => 'Submit Report';

  @override
  String get actionEdit => 'Edit';

  @override
  String get reviewTakePhoto => 'Take a photo';

  @override
  String get quickIncident => 'Incident';

  @override
  String get quickReport => 'Report';

  @override
  String get quickYourLocation => 'Your location';

  @override
  String quickSentTo(String station) {
    return 'Report sent to $station.';
  }

  @override
  String quickGpsPrecise(int meters) {
    return 'GPS is accurate (±$meters m)';
  }

  @override
  String quickGpsVague(int meters) {
    return 'GPS is imprecise (±$meters m) — this may not be exactly where you are.';
  }

  @override
  String get quickNoteHint => 'e.g. someone is trapped inside';

  @override
  String get quickSendReport => 'Send report';

  @override
  String get quickSendWarning => 'This sends a real call-out to the station. A false report carries a penalty.';

  @override
  String get quickLocationOff => 'Location is off. The report will still be sent, but a dispatcher will have to ask where you are.';

  @override
  String get quickSearching => 'Searching...';

  @override
  String get quickCoordinatesFound => 'Coordinates acquired';

  @override
  String get quickReceivingStation => 'Receiving station';

  @override
  String get quickLoadingStations => 'Loading the list...';

  @override
  String get quickStationUnknown => 'Cannot be determined yet - your location is needed.';

  @override
  String get quickStationAuto => 'Assigned automatically from your location';

  @override
  String get quickLandmark => 'Landmark (optional)';

  @override
  String get quickLandmarkHelp => 'What is next to it or nearby? This is what a responder will look for.';

  @override
  String get quickLandmarkHint => 'e.g. next to the barangay hall';

  @override
  String quickVoiceOnlyReportText(String category) {
    return '$category — reported by voice recording';
  }

  @override
  String quickNoDetailsReportText(String category) {
    return '$category — no additional details provided';
  }

  @override
  String quickFlowTitle(String category) {
    return 'Report a $category';
  }

  @override
  String get quickHelpSubtitle => 'Help us get the right team to the right place.';

  @override
  String get quickYourLocationAuto => 'Your location (auto-detected)';

  @override
  String quickAccuracy(int meters) {
    return 'Accuracy: ±$meters m';
  }

  @override
  String get quickDescribeWhatHappened => 'Describe what happened';

  @override
  String get quickOrTypeMessage => 'Or type your message (optional)';

  @override
  String get quickAttachPhotoVideo => 'Attach photo or video (optional)';

  @override
  String get quickMediaHint => 'Add photos or videos as evidence (max 5, 50MB each)';

  @override
  String get quickTakePhoto => 'Take a photo';

  @override
  String get quickRecordVideo => 'Record a video';

  @override
  String get quickChooseFromGallery => 'Choose from gallery';

  @override
  String get quickAddPhoto => 'Add photo or video';

  @override
  String get quickReviewReportAction => 'Review report';

  @override
  String get quickReviewWarning => 'By sending this, you are creating a real emergency report. Please be serious and accurate.';

  @override
  String get quickReviewTitle => 'Review report';

  @override
  String get quickReviewCareful => 'Please review your report carefully.';

  @override
  String quickReviewWillSendTo(String agency) {
    return 'This will be sent to the nearest $agency station.';
  }

  @override
  String get quickReviewDescription => 'Description';

  @override
  String get quickReviewPhoto => 'Photo';

  @override
  String quickReviewAttachedCount(int count) {
    return '$count attached';
  }

  @override
  String get quickReviewReceivingAgency => 'Receiving agency';

  @override
  String quickReviewAway(String km) {
    return '$km km away';
  }

  @override
  String get quickReviewVoiceRecording => 'Voice recording';

  @override
  String get quickReviewAttached => 'Attached';

  @override
  String get categoryQuestion => 'What kind of emergency?';

  @override
  String get categoryHelp => 'Choose the closest category';

  @override
  String get whoTitle => 'Who and where?';

  @override
  String get whoRelationship => 'What is your relationship to the victim?';

  @override
  String get whoLocation => 'Location';

  @override
  String get whoLandmark => 'Landmark or nearby marker (optional)';

  @override
  String get whoLandmarkHint => 'For example: near the church, beside the market...';

  @override
  String get overlapTitle => 'Anything else involved...';

  @override
  String get overlapHelp => 'Select all that apply - this helps alert the right agency.';

  @override
  String get stationPickTitle => 'Choose a Station';

  @override
  String get actionTryAgainStation => 'Try again';

  @override
  String get stationNoneAvailable => 'No stations available.';

  @override
  String get stationPickHelp => 'Tap the station that should receive your report.';

  @override
  String get qFireMaterial => 'What is burning?';

  @override
  String get qFireSpreading => 'Is it still spreading?';

  @override
  String get qFireInjured => 'Anyone hurt or trapped?';

  @override
  String get qFireRoadBlocked => 'Is the fire blocking the road?';

  @override
  String get qMedType => 'Type of emergency?';

  @override
  String get qMedVictimCount => 'How many victims?';

  @override
  String get qMedBleeding => 'Bleeding or serious wounds?';

  @override
  String get qMedConscious => 'Is the victim conscious?';

  @override
  String get qVehType => 'What vehicle?';

  @override
  String get qVehInjured => 'Anyone hurt?';

  @override
  String get qVehRoadBlocked => 'Is the road blocked?';

  @override
  String get qCalType => 'Type of calamity?';

  @override
  String get qCalAffected => 'How many families affected?';

  @override
  String get qCalRoadCut => 'Is the road cut off?';

  @override
  String get qCalEvacuation => 'Is evacuation needed?';

  @override
  String get qCrimeType => 'Type of incident?';

  @override
  String get qCrimeWeapon => 'Any weapons?';

  @override
  String get qCrimeOngoing => 'Is it still happening now?';

  @override
  String get ansYes => 'Yes';

  @override
  String get ansNo => 'No';

  @override
  String get ansNone => 'None';

  @override
  String get ansDontKnow => 'I do not know';

  @override
  String get ansOther => 'Other';

  @override
  String get ansHouse => 'House';

  @override
  String get ansVehicle => 'Vehicle';

  @override
  String get ansForestField => 'Forest / Field';

  @override
  String get ansBuildingWarehouse => 'Building / Warehouse';

  @override
  String get ansYesSpreading => 'Yes, spreading';

  @override
  String get ansNoControlled => 'No, under control';

  @override
  String get ansAccident => 'Accident';

  @override
  String get ansHeartAttackStroke => 'Heart attack / Stroke';

  @override
  String get ansSeizure => 'Seizure';

  @override
  String get ansTroubleBreathing => 'Trouble breathing';

  @override
  String get ansOne => '1';

  @override
  String get ansTwoToFive => '2-5';

  @override
  String get ansMoreThanFive => 'More than 5';

  @override
  String get ansYesConscious => 'Yes, conscious';

  @override
  String get ansNoUnconscious => 'No, unconscious';

  @override
  String get ansMotorcycle => 'Motorcycle';

  @override
  String get ansCarSuv => 'Car / SUV';

  @override
  String get ansBusTruck => 'Bus / Truck';

  @override
  String get ansTricycleEbike => 'Tricycle / E-bike';

  @override
  String get ansYesBlocked => 'Yes, blocked';

  @override
  String get ansPartly => 'Partly';

  @override
  String get ansFlood => 'Flood';

  @override
  String get ansLandslide => 'Landslide';

  @override
  String get ansStorm => 'Storm';

  @override
  String get ansEarthquake => 'Earthquake';

  @override
  String get ansOneToFive => '1-5';

  @override
  String get ansSixToTwenty => '6-20';

  @override
  String get ansMoreThanTwenty => 'More than 20';

  @override
  String get ansYesUrgent => 'Yes, urgent';

  @override
  String get ansPossibly => 'Possibly';

  @override
  String get ansNotYetNeeded => 'Not needed yet';

  @override
  String get ansFightDisturbance => 'Fight / Disturbance';

  @override
  String get ansTheftHoldup => 'Theft / Hold-up';

  @override
  String get ansPhysicalAssault => 'Physical assault';

  @override
  String get ansArmed => 'Weapon involved';

  @override
  String get ansYesOngoing => 'Yes, still happening';

  @override
  String get ansItIsOver => 'It is over';

  @override
  String get qExtraDetails => 'More details (optional)';

  @override
  String get sosAppBarTitle => 'SOS - Emergency Report';

  @override
  String get sosHeading => 'Emergency SOS';

  @override
  String get sosIntro => 'Your identity and location will be sent to the nearest emergency station.';

  @override
  String get sosLocating => 'Determining your location...';

  @override
  String get sosStationAuto => 'Nearest station will be identified automatically.';

  @override
  String get sosLocationUnavailable => 'Location unavailable';

  @override
  String get sosNoGpsBody => 'Your SOS will be sent without GPS. The server will route to the nearest Naval station.';

  @override
  String get sosLocationCaptured => 'Location captured';

  @override
  String get sosBriefDescription => 'Brief description (optional)';

  @override
  String get sosLegalWarning => 'Legal Warning';

  @override
  String get sosLegalBody => 'Submitting a false emergency report is a punishable offense under Philippine law (RA 10175, local ordinances). Your full identity and location are permanently attached to this report. Repeated false reports will result in suspension of your SOS access and referral to local authorities.';

  @override
  String get sosTruthConfirm => 'I understand this is a real emergency and confirm my report is truthful.';

  @override
  String get sosSendNow => 'Send SOS Now';

  @override
  String sosCooldownWarning(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'You submitted an SOS recently. Please wait $minutes more minutes before sending another. If this is an ongoing emergency, call 911 directly.',
      one: 'You submitted an SOS recently. Please wait 1 more minute before sending another. If this is an ongoing emergency, call 911 directly.',
    );
    return '$_temp0';
  }

  @override
  String get sosSentTitle => 'SOS Sent';

  @override
  String get sosSentBody => 'Your emergency report has been received and is being reviewed by a dispatcher.';

  @override
  String get actionBackToHome => 'Back to Home';

  @override
  String get sosWorsensNote => 'If the emergency worsens, call 911 directly.\nA dispatcher will contact you if needed.';

  @override
  String get sosDispatchedTo => 'Dispatched to';

  @override
  String get sosAddDetails => 'Add more details (optional)';

  @override
  String get sosAddDetailsHelp => 'Your SOS is already sent. If you can safely provide more information (what happened, number of people involved, etc.), the dispatcher will find it helpful.';

  @override
  String get actionSkip => 'Skip';

  @override
  String get sosSendDetails => 'Send Details';

  @override
  String get sosDetailsSent => 'Additional details sent. The dispatcher has been updated.';

  @override
  String get formSubmittedTitle => 'Report Submitted';

  @override
  String get formTrackReport => 'Track My Report';

  @override
  String get formReportEmergency => 'Report Emergency';

  @override
  String get formMyReports => 'My Reports';

  @override
  String get actionLogOutForm => 'Log out';

  @override
  String get formDescribe => 'Describe the emergency';

  @override
  String get formDescribeHint => 'For example: Fire in Brgy. Caraycaray Naval, a house is burning, two people are escaping...';

  @override
  String get formDescribeRequired => 'Please describe the emergency.';

  @override
  String get formDescribeTooShort => 'Please provide more detail (at least 10 characters).';

  @override
  String get formSubmit => 'Submit Emergency Report';

  @override
  String get formSubmitNote => 'This report will be reviewed by a dispatcher. For life-threatening emergencies, also call 911.';

  @override
  String get actionChangeForm => 'Change';

  @override
  String get formNoLocation => 'Location not available - report will be sent without GPS';

  @override
  String get withdrawReport => 'Move to Trash';

  @override
  String get withdrawConfirmTitle => 'Move this report to Trash?';

  @override
  String get withdrawConfirmBody => 'It will be moved to Trash and taken off the dispatcher\'s list. Reports in Trash are permanently deleted after 30 days. Do this only if help is no longer needed.';

  @override
  String get withdrawConfirmAction => 'Move to Trash';

  @override
  String get withdrawCancelAction => 'Keep report';

  @override
  String get withdrawDone => 'Moved to Trash. It will be permanently deleted in 30 days.';

  @override
  String get filterTrash => 'Trash';

  @override
  String get noTrashedReports => 'Nothing withdrawn';

  @override
  String get noTrashedReportsBody => 'Reports you take back appear here. They stay on record, but nobody is working on them.';

  @override
  String trashDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Deletes in $days days',
      one: 'Deletes in 1 day',
      zero: 'Deletes today',
    );
    return '$_temp0';
  }

  @override
  String get reportDetailsTitle => 'Report Details';

  @override
  String get respTabHome => 'Home';

  @override
  String get respTabStats => 'Stats';

  @override
  String get respTabReports => 'Reports';

  @override
  String get respStatToday => 'Today';

  @override
  String get respStatTypical => 'Typical';

  @override
  String get respTabMap => 'Map';

  @override
  String get respTabProfile => 'Profile';

  @override
  String get respStatAssigned => 'Assigned';

  @override
  String get respStatCritical => 'Critical';

  @override
  String get respStatOldest => 'Longest waiting';

  @override
  String get respHomeGreetingSubtitle => 'Here\'s what\'s on your queue today.';

  @override
  String get respHomeRecentActivity => 'Recent Activity';

  @override
  String get respHomeViewAll => 'View all';

  @override
  String get respHomeQueueTitle => 'Assigned to you';

  @override
  String get respHomeAwaitingDispatch => 'Awaiting Dispatch';

  @override
  String get respHomeNoAssignmentsTitle => 'No assignments';

  @override
  String get respHomeOffDutyTitle => 'Off duty';

  @override
  String get respHomeQueueClear => 'Queue clear';

  @override
  String get respHomeNotAccepting => 'Not accepting calls';

  @override
  String get respHomeQueueClearBody => 'Nothing assigned to you yet. New calls will show up here.';

  @override
  String get respHomeOffDutyBody => 'No assignments will be sent while you are off duty. Flip the switch above.';

  @override
  String get respDashTitle => 'My dashboard';

  @override
  String get respDashAssigned => 'Assigned';

  @override
  String get respDashCritical => 'Critical';

  @override
  String get respDashEnRoute => 'En route';

  @override
  String get respDashOnScene => 'On scene';

  @override
  String get respDashClosedToday => 'Closed today';

  @override
  String get respDashTypicalTime => 'Typical time to close';

  @override
  String get respDashTypicalBody => 'From the moment you were sent, to resolved.';

  @override
  String get respHistoryTitle => 'My closed incidents';

  @override
  String get respHistoryError => 'Could not load your history';

  @override
  String get respHistoryEmpty => 'Nothing closed yet';

  @override
  String get respAccept => 'I WILL RESPOND';

  @override
  String get respDecline => 'CAN\'T RESPOND';

  @override
  String get respDeclineLong => 'CAN\'T RESPOND';

  @override
  String get respAccepted => 'You have accepted this. The dispatcher knows.';

  @override
  String get respSeconds => 'seconds';

  @override
  String get respOverdue => 'NO ANSWER YET';

  @override
  String get respUntriaged => 'NOT YET TRIAGED';

  @override
  String get respDeclineTitle => 'Can\'t respond?';

  @override
  String get respDeclineSubtitle => 'This goes back to the dispatcher with your reason, so they can send someone else right away.';

  @override
  String get respDeclineNote => 'Extra detail (optional)';

  @override
  String get respDeclineNoteHint => 'For example: truck is on a jack, 30 more minutes';

  @override
  String get respDeclineSubmit => 'Send back to dispatcher';

  @override
  String get respCloseTitle => 'What did you find?';

  @override
  String get respCloseCasualties => 'Number of people';

  @override
  String get respCloseCasualtiesHint => 'Leave blank if not counted. That is not the same as zero.';

  @override
  String get respCloseInjured => 'Injured';

  @override
  String get respCloseFatal => 'Died';

  @override
  String get respCloseTransported => 'Taken to hospital';

  @override
  String get respCloseNarrative => 'Short account (optional)';

  @override
  String get respCloseNarrativeHint => 'What happened, and what you did';

  @override
  String get respCloseSubmit => 'Close incident';

  @override
  String get respCloseLater => 'Not yet — I\'ll come back';

  @override
  String get respCount => 'Count';

  @override
  String get respNotCounted => 'Not counted';

  @override
  String get respClosed => 'Incident closed. Thank you!';

  @override
  String get respBackupTitle => 'Request assistance';

  @override
  String get respBackupSubtitle => 'This creates a new incident for their dispatcher, linked to this call. It is not just a message.';

  @override
  String get respBackupNeed => 'What do you need? *';

  @override
  String get respBackupNeedHint => 'For example: 2 injured, need an ambulance';

  @override
  String get respBackupSubmit => 'Send the request';

  @override
  String get respBackupAction => 'Request another agency\'s help';

  @override
  String get respDistressTitle => 'Are you in danger?';

  @override
  String get respDistressBody => 'This alerts the dispatcher immediately, with your location.\n\nUse it if you yourself need help.';

  @override
  String get respDistressNo => 'No';

  @override
  String get respDistressYes => 'YES, HELP';

  @override
  String get respDistressHold => 'PRESS AND HOLD IF YOU ARE IN DANGER';

  @override
  String get respDistressHoldBody => 'For your own safety, not the incident';

  @override
  String get respDistressSemantics => 'Distress signal. Press and hold to raise.';

  @override
  String get respNavTitle => 'Going to the scene';

  @override
  String get respNavLocating => 'Finding your location...';

  @override
  String get respNavStraightLine => 'This is a straight line, not a road. Follow the actual streets.';

  @override
  String get respNavExternal => 'Open in Google Maps for directions';

  @override
  String get respNavNoMapsApp => 'No maps app on this phone.';

  @override
  String get respNavStraightDistance => 'straight-line distance';

  @override
  String get respNavClose => 'almost there';

  @override
  String get respIncident => 'Incident';

  @override
  String get respSectionReport => 'INCIDENT REPORT';

  @override
  String get respSectionLocation => 'LOCATION';

  @override
  String get respSectionReporter => 'REPORTER';

  @override
  String get respSectionStation => 'STATION';

  @override
  String get respFieldCategory => 'Category';

  @override
  String get respFieldAddress => 'Address';

  @override
  String get respFieldLandmark => 'Landmark';

  @override
  String get respFieldGps => 'GPS';

  @override
  String get respFieldName => 'Name';

  @override
  String get respFieldPhone => 'Phone';

  @override
  String get respFieldStation => 'Station';

  @override
  String get respFieldEmergencyContact => 'Emergency Contact';

  @override
  String get respFieldContactNumber => 'Contact Number';

  @override
  String get respNavigate => 'Navigate';

  @override
  String get respGoBack => 'Go Back';

  @override
  String get respSosFlagged => 'SOS account flagged';

  @override
  String get respTranscriptWarning => 'The words above are transcribed and can be wrong.';

  @override
  String get respSceneOnlyWhenOnScene => 'You can only take photos once you are on scene.';

  @override
  String get respSceneUploading => 'Uploading...';

  @override
  String get respSceneTakePhoto => 'Take a photo of the scene';

  @override
  String respSceneAddMore(int count) {
    return 'Add more ($count added)';
  }

  @override
  String get respSceneNotSignedIn => 'You are not signed in.';

  @override
  String get respScenePhotoAdded => 'Photo added.';

  @override
  String get respScenePhotoNotAdded => 'Photo could not be added.';

  @override
  String get respScenePhotoUploadFailed => 'Photo could not be uploaded. Try again when you have signal.';

  @override
  String get respActionAccept => 'Accepting the call';

  @override
  String get respActionDecline => 'Declining the call';

  @override
  String get respActionStatusUpdate => 'Status update';

  @override
  String get respActionClose => 'Closing the incident';

  @override
  String get respActionSceneMedia => 'Scene photos';

  @override
  String get respActionDistress => 'Distress signal';

  @override
  String get respProfileTitle => 'Profile';

  @override
  String get respProfileSaved => 'Profile saved.';

  @override
  String get respProfileCancel => 'Cancel';

  @override
  String get respProfileEdit => 'Edit';

  @override
  String get respProfileSave => 'Save';

  @override
  String get respProfileContact => 'Contact';

  @override
  String get respProfileAssignment => 'Assignment';

  @override
  String get respProfileShift => 'This shift';

  @override
  String get respProfileBadge => 'Badge ID';

  @override
  String get respProfileAgency => 'Agency';

  @override
  String get respProfileMunicipality => 'Municipality';

  @override
  String get respProfileStatus => 'Status';

  @override
  String get respProfileAssignedNow => 'Assigned right now';

  @override
  String get respProfileWaitingToSend => 'Waiting to send';

  @override
  String get respProfileResolvedPeriod => 'Resolved this period';

  @override
  String get respProfileTypicalResponse => 'Typical response time';

  @override
  String get respProfileNameRequired => 'Name is required.';

  @override
  String get respLogout => 'Log out';

  @override
  String get respLogoutConfirm => 'Log out?';

  @override
  String get respLogoutBody => 'You will stop receiving dispatch alerts on this phone until you sign in again.';

  @override
  String get respOnDuty => 'ON DUTY';

  @override
  String get respOffDuty => 'OFF DUTY';

  @override
  String get respApproved => 'Approved';

  @override
  String get respRejected => 'Not approved';

  @override
  String get respPending => 'Awaiting approval';

  @override
  String get respPendingTitle => 'Awaiting approval';

  @override
  String get respPendingBody => 'You cannot receive dispatch until your Agency Admin verifies your badge ID.';

  @override
  String get respRejectedTitle => 'Your account was not approved';

  @override
  String get respRejectedBody => 'You cannot receive dispatch. Talk to your Agency Admin.';

  @override
  String get respCancel => 'Cancel';

  @override
  String respHazardBanner(int count) {
    return 'ROAD WARNINGS ($count)';
  }

  @override
  String respDeclinedTimes(int count) {
    return 'Refused ${count}x';
  }

  @override
  String respPriorWarnings(int count) {
    return '$count prior warning(s)';
  }

  @override
  String respSyncPending(int count) {
    return '$count waiting — will send when there is signal';
  }

  @override
  String respTellingResident(String eta) {
    return 'Resident is told: $eta';
  }

  @override
  String respLandmarkPrefix(String landmark) {
    return 'Landmark: $landmark';
  }

  @override
  String respStatsPeriod(int days) {
    return 'Last $days days';
  }

  @override
  String respAnswerWithin(String time) {
    return 'Answer within $time';
  }

  @override
  String respEtaMinutes(int minutes) {
    return 'about $minutes min';
  }

  @override
  String get respReasonVehicleDown => 'Vehicle down';

  @override
  String get respReasonVehicleDownHint => 'The truck or ambulance cannot roll';

  @override
  String get respReasonCommitted => 'On another call';

  @override
  String get respReasonCommittedHint => 'Already on another incident that is not closed';

  @override
  String get respReasonOutOfArea => 'Out of area';

  @override
  String get respReasonOutOfAreaHint => 'Wrong municipality for this unit';

  @override
  String get respReasonCrew => 'Not enough crew';

  @override
  String get respReasonCrewHint => 'Not enough hands to respond safely';

  @override
  String get respReasonRoad => 'Road impassable';

  @override
  String get respReasonRoadHint => 'Flood, landslide or a cut bridge';

  @override
  String get respReasonOther => 'Another reason';

  @override
  String get respReasonOtherHint => 'Explain in the note';

  @override
  String get respOutcomeHandled => 'Handled on scene';

  @override
  String get respOutcomeHandledHint => 'Dealt with, nobody moved';

  @override
  String get respOutcomeTransported => 'Taken to hospital';

  @override
  String get respOutcomeTransportedHint => 'Casualties taken to a facility';

  @override
  String get respOutcomeTurnedOver => 'Turned over';

  @override
  String get respOutcomeTurnedOverHint => 'Handed over to PNP, BFP, MDRRMO or a hospital';

  @override
  String get respOutcomeFalseAlarm => 'No real emergency';

  @override
  String get respOutcomeFalseAlarmHint => 'Nothing was happening';

  @override
  String get respOutcomeNobodyFound => 'Nobody found';

  @override
  String get respOutcomeNobodyFoundHint => 'Arrived, no incident and no reporter';

  @override
  String get respOutcomeRefused => 'Refused assistance';

  @override
  String get respOutcomeRefusedHint => 'Party present and declined help';

  @override
  String get respOutcomeNoAccess => 'Could not reach it';

  @override
  String get respOutcomeNoAccessHint => 'Could not reach the scene at all';

  @override
  String get respOutcomeOther => 'Other';

  @override
  String get respOutcomeOtherHint => 'Explain in the notes';

  @override
  String get respHazardRoad => 'Impassable';

  @override
  String get respHazardAccess => 'Hard to reach';

  @override
  String get respHazardSecurity => 'Dangerous';

  @override
  String get respHazardAnimal => 'Animals';

  @override
  String get respHazardStructural => 'Unsafe building';

  @override
  String get respHazardOther => 'Warning';

  @override
  String get respNoAnswerSeen => 'No answer — the dispatcher can see this';

  @override
  String get respUpdateStatus => 'Update Status';

  @override
  String get respAnswerSendFailed => 'Could not send. Try again.';

  @override
  String get respCloseFailed => 'Could not close.';

  @override
  String get respDeclineSent => 'Sent back to the dispatcher. They will look for another unit.';

  @override
  String respBackupSentTo(String station) {
    return 'Sent to $station. It is now in their queue.';
  }

  @override
  String get respEscalateSent => 'Sent. The Agency Admin knows.';

  @override
  String get respEscalateAction => 'Escalate incident';

  @override
  String get respEscalateBody => 'Tell the Agency Admin what changed. This notifies them to reassess — it does not change the official severity yourself.';

  @override
  String get respEscalateWhat => 'What changed?';

  @override
  String get respEscalateHint => 'e.g. Fire spreading rapidly, multiple casualties, additional agency required…';

  @override
  String get respEscalateSubmit => 'Send escalation';

  @override
  String get respDistressSentLive => 'SENT. The dispatcher can see you now.';

  @override
  String get respDistressSentQueued => 'No signal — this is queued. CALL THE STATION ON RADIO NOW.';

  @override
  String get respConfirmResolve => 'Mark this incident as Resolved? The dispatcher and the reporter will see this.';

  @override
  String get respConfirmStatusUpdate => 'Update the incident\'s status?';

  @override
  String get respNoLocationRecorded => 'No location was recorded on this report. Ask the dispatcher.';

  @override
  String get mapNearbyStationsTitle => 'Nearby Emergency Stations';

  @override
  String get mapResponderTitle => 'Incident Map';

  @override
  String get mapReportLocationTitle => 'Report Location';

  @override
  String get mapLocationOff => 'Location is off';

  @override
  String get mapLocationSearching => 'Finding your location…';

  @override
  String mapLocationPrecise(int accuracy) {
    return 'You are here · ±$accuracy m';
  }

  @override
  String mapLocationImprecise(int accuracy) {
    return 'Approximate · ±$accuracy m';
  }

  @override
  String get mapNoLocationYet => 'No location yet. Check if your GPS is turned on.';

  @override
  String get mapYouLabel => 'You';

  @override
  String get mapLoading => 'Loading map…';

  @override
  String get mapGetDirections => 'Get directions';

  @override
  String mapStationDistance(String distanceKm, String agency) {
    return '$distanceKm km away · $agency';
  }

  @override
  String mapStationDistanceShort(String distanceKm) {
    return '$distanceKm km';
  }

  @override
  String get settingsScreenTitle => 'Settings & Profile';

  @override
  String get settingsEditPersonalInfo => 'Edit personal information';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsNotificationPreferences => 'Notification preferences';

  @override
  String get settingsAppSettingsSection => 'App Settings';

  @override
  String get settingsDarkMode => 'Dark mode';

  @override
  String get settingsLocationServices => 'Location services';

  @override
  String get settingsLocationDenied => 'Location permission was not granted.';

  @override
  String get settingsLocationOffTitle => 'Turn off location services?';

  @override
  String get settingsLocationOffBody => 'Android and iOS only let you change this in your phone\'s Settings app, not inside Ziren.';

  @override
  String get settingsOpenSystemSettings => 'Open Settings';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsOfflineMaps => 'Offline maps';

  @override
  String get settingsOfflineMapsComingSoon => 'Offline maps are coming in a future update.';

  @override
  String get settingsSupportSection => 'Support';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsSectionLocation => 'Location';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsSectionHelpSupport => 'Help & Support';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsHelpFaq => 'Help & FAQ';

  @override
  String get settingsFaqReportQ => 'How do I report an emergency?';

  @override
  String get settingsFaqReportA => 'On Home, tap the kind of emergency (Fire, Medical, Accident, Crime, Calamity or Other). Check the landmark, say or type what happened, review it, then send. Ziren sends it to the nearest station that handles it.';

  @override
  String get settingsFaqOfflineQ => 'What happens with no internet?';

  @override
  String get settingsFaqOfflineA => 'A report needs internet to send. With no data, tap the kind of emergency on Home anyway: Ziren shows the official station hotlines for it, and a normal call only needs a phone signal. You can also call 911.';

  @override
  String get settingsFaqAgencyQ => 'Which agency responds to my report?';

  @override
  String get settingsFaqAgencyA => 'It depends on the emergency: BFP for fire, PNP for crime, MDRRMO for medical cases, accidents and calamities. The station in the town where the incident is receives it.';

  @override
  String get settingsFaqAccountQ => 'How do I update my emergency contact?';

  @override
  String get settingsFaqAccountA => 'In Settings, open \"Edit personal information\", change the contact name or number, and tap \"Save changes\".';

  @override
  String get settingsAboutZiren => 'About Ziren';

  @override
  String get settingsAboutTagline => 'Emergency Response, Simplified. Built for the residents of Biliran.';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsAboutTerms => 'Terms of Use';

  @override
  String get settingsAboutPrivacy => 'Data Privacy Notice';

  @override
  String get settingsLogOut => 'Log out';

  @override
  String get settingsLogOutConfirmTitle => 'Log out?';

  @override
  String get settingsLogOutConfirmBody => 'You will need to sign in again to access Ziren.';

  @override
  String get settingsSectionAccessibility => 'Accessibility';

  @override
  String get settingsAccessibilityAppearance => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get settingsAccessibilityTextSize => 'Text size';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeDefault => 'Default';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeExtraLarge => 'Extra Large';

  @override
  String get textSizePreview => 'A responder will see your report exactly this size.';

  @override
  String get settingsReduceMotion => 'Reduce motion';

  @override
  String get settingsHighContrast => 'High contrast';

  @override
  String get notifMoreOptions => 'More options';

  @override
  String get notifClearAll => 'Clear all';

  @override
  String get notifCategoryEmergencyUpdate => 'Emergency Update';

  @override
  String get notifCategoryReportConfirmed => 'Report Confirmed';

  @override
  String get notifCategorySafetyAdvisory => 'Safety Advisory';

  @override
  String get notifCategorySystemMessage => 'System Message';

  @override
  String get notifReportPrefix => 'Report #';

  @override
  String get notifEmptyTitle => 'No notifications yet';

  @override
  String get notifEmptySubtitle => 'Status updates for your reports will appear here.';

  @override
  String get voiceTapToRecord => 'Tap to record';

  @override
  String get voiceTapToStop => 'Tap to stop';

  @override
  String voiceUpToMinutes(int minutes) {
    return '(up to $minutes min)';
  }

  @override
  String get voiceRecordingHint => 'Say what happened in your own words. The station will hear it directly.';

  @override
  String get voicePlay => 'Play';

  @override
  String get voicePause => 'Pause';

  @override
  String voiceRecorded(String clock) {
    return 'Recorded · $clock';
  }

  @override
  String get voiceWillSend => 'This will be sent to the station.';

  @override
  String get voiceDeleteTooltip => 'Delete recording';

  @override
  String get voiceCaptureFailedMsg => 'Voice couldn\'t be recorded. Please write what happened above — your report can still be sent.';

  @override
  String get voiceUploadFailedMsg => 'Your report was sent, but the recording didn\'t reach the station. If signal is weak, try again.';

  @override
  String get voicePeopleCountQuestion => 'How many people are involved? (optional)';

  @override
  String get voicePeopleCountHint => 'This is often missed in the recording.';

  @override
  String get voicePeopleCountNotSure => 'Not sure';

  @override
  String get homeLocating => 'Locating…';

  @override
  String reportsLocationDistance(String location, String km) {
    return '$location · $km km';
  }

  @override
  String get reportsViewOnMap => 'View on Map';

  @override
  String get safetyGuideTitle => 'Safety Guide';

  @override
  String get safetyFireTitle => 'Fire';

  @override
  String get safetyFireStep1 => 'Get out of the building immediately. Do not go back for belongings.';

  @override
  String get safetyFireStep2 => 'If there is smoke, get low and crawl to the exit.';

  @override
  String get safetyFireStep3 => 'Do not use the elevator — stairs only.';

  @override
  String get safetyFireStep4 => 'Touch the doorknob with the back of your hand before opening it — if it is hot, do not open it.';

  @override
  String get safetyFireStep5 => 'Once outside, call the BFP right away or report using Ziren.';

  @override
  String get safetyFireStep6 => 'Do not go back inside until it has been declared safe.';

  @override
  String get safetyEarthquakeTitle => 'Earthquake';

  @override
  String get safetyEarthquakeStep1 => 'Duck, Cover, Hold — drop down, take cover under a sturdy table, and hold on.';

  @override
  String get safetyEarthquakeStep2 => 'Stay away from windows, glass, and heavy furniture.';

  @override
  String get safetyEarthquakeStep3 => 'If outdoors, move away from buildings, posts, and power lines.';

  @override
  String get safetyEarthquakeStep4 => 'If driving, pull over to a safe spot and stay inside the vehicle.';

  @override
  String get safetyEarthquakeStep5 => 'After the shaking stops, be ready for aftershocks.';

  @override
  String get safetyEarthquakeStep6 => 'Check your surroundings for damaged gas or power lines before moving.';

  @override
  String get safetyFloodTitle => 'Flood';

  @override
  String get safetyFloodStep1 => 'Move to higher ground immediately if your barangay is under a flood warning.';

  @override
  String get safetyFloodStep2 => 'Avoid walking or driving through floodwater — six inches of water can knock a person down.';

  @override
  String get safetyFloodStep3 => 'Turn off electrical appliances and switch off the main breaker if there is still time.';

  @override
  String get safetyFloodStep4 => 'Keep important documents in a waterproof container.';

  @override
  String get safetyFloodStep5 => 'Follow MDRRMO\'s instructions on evacuation.';

  @override
  String get safetyFloodStep6 => 'Do not drink floodwater or tap water until it has been declared safe.';

  @override
  String get safetyTyphoonTitle => 'Typhoon';

  @override
  String get safetyTyphoonStep1 => 'Watch PAGASA advisories and announcements from Ziren.';

  @override
  String get safetyTyphoonStep2 => 'Prepare an emergency kit: water, food, flashlight, first aid, and a power bank.';

  @override
  String get safetyTyphoonStep3 => 'Secure or bring inside anything that could be blown away by the wind.';

  @override
  String get safetyTyphoonStep4 => 'Stay indoors unless told to evacuate.';

  @override
  String get safetyTyphoonStep5 => 'Stay away from trees and power poles during strong winds.';

  @override
  String get safetyTyphoonStep6 => 'Know the location of the nearest evacuation center before the typhoon arrives.';

  @override
  String get safetyRoadAccidentTitle => 'Road Accident';

  @override
  String get safetyRoadAccidentStep1 => 'Make sure you are safe first before helping others.';

  @override
  String get safetyRoadAccidentStep2 => 'Turn on hazard/warning lights and set up a marker if you have one.';

  @override
  String get safetyRoadAccidentStep3 => 'Do not move the victim unless there is immediate danger (e.g. fire).';

  @override
  String get safetyRoadAccidentStep4 => 'Call the PNP and/or MDRRMO right away, or report using Ziren.';

  @override
  String get safetyRoadAccidentStep5 => 'Monitor the victim\'s breathing and pulse while waiting for help.';

  @override
  String get safetyRoadAccidentStep6 => 'If there is bleeding, apply pressure with a clean cloth.';

  @override
  String get safetyMedicalTitle => 'Medical Emergency';

  @override
  String get safetyMedicalStep1 => 'Check if the patient is still conscious and breathing normally.';

  @override
  String get safetyMedicalStep2 => 'Call for help right away — do not wait for the situation to get worse.';

  @override
  String get safetyMedicalStep3 => 'If not breathing and unconscious, start CPR if you know how.';

  @override
  String get safetyMedicalStep4 => 'Do not give food or drink to someone having trouble breathing or who is unconscious.';

  @override
  String get safetyMedicalStep5 => 'Keep the patient calm and comfortable while waiting.';

  @override
  String get safetyMedicalStep6 => 'Prepare the patient\'s information (age, condition, medication) for the responder.';

  @override
  String get safetyCrimeTitle => 'Crime';

  @override
  String get safetyCrimeStep1 => 'Prioritize your own safety — move away from danger if you can.';

  @override
  String get safetyCrimeStep2 => 'Do not touch or disturb the crime scene if it is safe to move away.';

  @override
  String get safetyCrimeStep3 => 'Call the PNP right away, or report using Ziren.';

  @override
  String get safetyCrimeStep4 => 'Note the details: appearance, plate number, direction — if you can safely do so.';

  @override
  String get safetyCrimeStep5 => 'Stay in a safe place until the responder arrives.';

  @override
  String get safetyCrimeStep6 => 'Follow the police\'s instructions once they arrive at the scene.';

  @override
  String get contactsTitle => 'Emergency Contacts';

  @override
  String get contactsNationalTitle => 'National Emergency Hotline';

  @override
  String get contactsNationalSubtitle => 'For any emergency, anywhere in the Philippines';

  @override
  String get contactsLocalAgencies => 'LOCAL AGENCIES';

  @override
  String get contactsNoneListed => 'No numbers listed yet. Use 911 or report through Ziren.';

  @override
  String get contactsHospitalsSection => 'HOSPITALS & EVACUATION CENTERS';

  @override
  String get contactsFindOnMap => 'Find on the Map';

  @override
  String get contactsFindOnMapBody => 'See the nearest station on the map.';

  @override
  String get contactsOpen => 'Open';

  @override
  String get announcementsTitle => 'Announcements';

  @override
  String get announcementsLoadError => 'Could not load announcements.';

  @override
  String get announcementsRetry => 'Retry';

  @override
  String get announcementsEmptyTitle => 'No announcements right now';

  @override
  String get announcementsEmptyBody => 'Official notices from Ziren will appear here.';

  @override
  String get announceCategoryMaintenance => 'Maintenance';

  @override
  String get announceCategoryEmergency => 'Emergency Notice';

  @override
  String get announceCategoryServiceInterruption => 'Service Interruption';

  @override
  String get announceCategoryFeature => 'New Feature';

  @override
  String get announceCategoryReminder => 'Reminder';

  @override
  String get announceCategoryGeneral => 'Announcement';

  @override
  String get profileSafetySection => 'Safety';

  @override
  String get aiScreenBody => 'This will help you build your report — asking what, where, and who was hurt, so the station receives complete information.';

  @override
  String get aiNotAvailable => 'This isn\'t available yet';

  @override
  String get aiNotAvailableBody => 'While you wait, use the quick report on Home or SOS if you need immediate help.';

  @override
  String get voiceConfirmAppBarTitle => 'Your report has been sent';

  @override
  String get voiceConfirmSkip => 'Skip';

  @override
  String get voiceConfirmSaveError => 'Your correction could not be saved. The report was still sent.';

  @override
  String get voiceConfirmSentTitle => 'Your report has been sent.';

  @override
  String get voiceConfirmSentBodyStation => 'The station can already hear this.';

  @override
  String voiceConfirmSentBodyStationNamed(String station) {
    return '$station can already hear this.';
  }

  @override
  String get voiceConfirmGaveUpTitle => 'The station will listen to your recording.';

  @override
  String get voiceConfirmGaveUpBody => 'We couldn\'t write down what you said right away, but they already have your actual voice.';

  @override
  String get voiceConfirmOk => 'OK';

  @override
  String get voiceConfirmListeningTitle => 'We\'re listening to your voice…';

  @override
  String get voiceConfirmListeningBody => 'Just a moment. We\'ll show you what we understood.';

  @override
  String get voiceConfirmEditTitle => 'What did you actually say?';

  @override
  String get voiceConfirmBack => 'Back';

  @override
  String get voiceConfirmSave => 'Save';

  @override
  String get voiceConfirmHeardTitle => 'Here\'s what we heard:';

  @override
  String get voiceConfirmWrongFix => 'Wrong — fix it';

  @override
  String get voiceConfirmCorrect => 'Correct';

  @override
  String get feedbackThanks => 'Thank you for your feedback!';

  @override
  String get feedbackClose => 'Close';

  @override
  String get feedbackHowWasIt => 'How was your experience?';

  @override
  String get feedbackNoImpact => 'This will not affect the priority of your next report.';

  @override
  String get feedbackCommentHint => 'Additional comments (optional)…';

  @override
  String get feedbackSubmit => 'Submit';

  @override
  String get feedbackMaybeLater => 'Maybe later';

  @override
  String get threadTitle => 'Report Updates';

  @override
  String get threadLoadError => 'Could not load messages.';

  @override
  String get threadEmptyTitle => 'No messages yet';

  @override
  String get threadEmptyBody => 'Any extra details you add and the agency\'s replies will appear here.';

  @override
  String get threadComposerHint => 'Add a detail…';

  @override
  String get threadClosedNotice => 'This report is closed — no more messages can be added.';

  @override
  String get reportsAskConfirmVoice => 'Did we hear this right?';

  @override
  String reportsAlreadyRated(String rating) {
    return 'You already rated this · $rating/5';
  }

  @override
  String get reportsRateService => 'Rate the Service';

  @override
  String get incidentStatusReceived => 'Received';

  @override
  String get incidentStatusProcessing => 'Processing';

  @override
  String get incidentStatusDispatched => 'Responder Dispatched';

  @override
  String get incidentStatusResolved => 'Resolved';

  @override
  String get incidentStatusCancelled => 'Cancelled';

  @override
  String incidentEtaMinutes(int minutes) {
    return 'about $minutes minutes';
  }

  @override
  String get threadAuthorYou => 'You';

  @override
  String activeReportAgencyEnRoute(String agency, String eta) {
    return '$agency is on the way — $eta';
  }

  @override
  String activeReportResponderEnRoute(String eta) {
    return 'A responder is on the way — $eta';
  }

  @override
  String get activeReportNotFollowedUp => 'This report was not followed up.';

  @override
  String get activeReportStale => 'Waiting a long time. Tap to check.';

  @override
  String activeReportStep(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get readyPanelFalseReportWarning => 'Filing a false report carries a penalty.';

  @override
  String get reviewRecordVideo => 'Record a video';

  @override
  String get reviewChooseFromGallery => 'Choose from gallery';

  @override
  String get reviewAttachmentsSection => 'ATTACHMENTS';

  @override
  String get reviewAddAttachment => 'Add';

  @override
  String get reviewAttachmentsHint => 'Optional — add a photo or video as evidence (max 5, 50MB each)';

  @override
  String get sosAddDetailsExample => 'e.g. \"3 people trying to escape, fire on the ground floor, no more visible flames outside…\"';

  @override
  String get reportsAddInformation => 'Chat';

  @override
  String get avatarSheetTitle => 'Profile Photo';

  @override
  String get avatarRemovePhoto => 'Remove photo';

  @override
  String get avatarUploadFailed => 'Could not update your profile picture. Please try again.';

  @override
  String get respDutyCardBusy => 'Just a moment...';

  @override
  String get respDutyCardOn => 'Currently On-Duty';

  @override
  String get respDutyCardOff => 'Off Duty';

  @override
  String respDutyCardStation(String station) {
    return '(Station: $station)';
  }

  @override
  String get respDutyToggleOff => 'Go off duty';

  @override
  String get respDutyToggleOn => 'Go on duty';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusNeedsReply => 'Needs your reply';

  @override
  String get reportRejectedTitle => 'The agency did not accept this report';

  @override
  String reportRejectedReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get reportRejectedHelp => 'If this is a real emergency, call the station now, or send a new report with more detail.';

  @override
  String get reportRejectedCall => 'Call emergency contacts';

  @override
  String get reportFileAgain => 'Send a new report';

  @override
  String get clarificationTitle => 'The agency needs more information';

  @override
  String get clarificationAsked => 'They asked:';

  @override
  String get clarificationReply => 'Reply';

  @override
  String get clarificationReplyHint => 'Answer here. The agency is waiting on your reply before it decides what to do.';

  @override
  String get notifRejectedTitle => 'Report not accepted';

  @override
  String get notifClarificationTitle => 'The agency needs more information';

  @override
  String get notifViewReport => 'View report';

  @override
  String get notifReplyNow => 'Reply now';

  @override
  String get idCheckTitle => 'We can\'t accept this photo yet';

  @override
  String get idCheckNoText => 'We couldn\'t read any text on it. Take the photo in good light, flat, with the whole card in frame.';

  @override
  String get idCheckNotAnIdTitle => 'We will not accept this — it is not an ID';

  @override
  String idCheckNotAnId(String chosen) {
    return 'We can\'t accept this photo because it is not an ID. Please upload again and make sure it is a photo of your $chosen — the card itself, not your face or another picture.';
  }

  @override
  String idCheckWrongTypeTitle(String chosen) {
    return 'This is not a $chosen';
  }

  @override
  String idCheckWrongType(String chosen, String found) {
    return 'We can\'t accept this. You chose $chosen, but this photo looks like a $found. Upload your $chosen instead — or go back and choose the ID type that matches your card.';
  }

  @override
  String idCheckTypeUnconfirmed(String chosen) {
    return 'We can\'t confirm that this is a $chosen. Take a clear photo of the FRONT of your $chosen, flat and in good light, with the printed words readable.';
  }

  @override
  String get idCheckNoFace => 'We couldn\'t find your photo on the card. Use the FRONT of your ID.';

  @override
  String get idCheckNoNumber => 'We couldn\'t find an ID number on it. Make sure the number is sharp and not covered by glare.';

  @override
  String get idCheckNumberMismatch => 'The number you typed is not the one on your ID photo. Fix it, or retake the photo.';

  @override
  String get idCheckRetakeHint => 'Retake the photo, or skip verification and do it later from Settings.';

  @override
  String get idCheckRetakeOnly => 'Retake the photo to continue.';

  @override
  String get idCheckPassed => 'ID photo accepted';

  @override
  String get idCheckChecking => 'Checking your photo…';

  @override
  String regLocationBarangaySet(String barangay, String municipality) {
    return 'Found your barangay: $barangay, $municipality. Check that it is right.';
  }

  @override
  String regLocationBarangayNear(String barangay, String municipality) {
    return 'Closest barangay: $barangay, $municipality. We are not sure, so please confirm or change it.';
  }

  @override
  String regLocationMunicipalityOnly(String municipality) {
    return 'Found $municipality, but could not tell your barangay. Please choose it below.';
  }

  @override
  String get selfieCapture => 'Take photo';

  @override
  String get selfieCapturing => 'Taking photo…';

  @override
  String get statusArrived => 'Responder arrived';

  @override
  String get statusCancelledByAgency => 'Cancelled by the agency';

  @override
  String get notifAcceptedTitle => 'Report accepted';

  @override
  String get notifAcceptedBody => 'The agency confirmed your report is real and is preparing a response.';

  @override
  String get notifEnRouteBody => 'The responder is heading to your location now.';

  @override
  String get notifArrivedBody => 'The responder has arrived at your location.';

  @override
  String get notifResolvedHelp => 'You can rate the response from My Reports.';

  @override
  String get notifCancelledTitle => 'Report cancelled by the agency';

  @override
  String get notifCancelledBody => 'The agency cancelled your report.';

  @override
  String notifCancelledReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get notifCancelledHelp => 'If you still need help, call the station or send a new report.';

  @override
  String get notifMessageTitle => 'New message from the agency';

  @override
  String get notifMessageHelp => 'Reply in the chat on this report.';

  @override
  String get notifOpenChat => 'Open chat';

  @override
  String get notifMessageFromResponder => 'New message from the responder';

  @override
  String get notifFeedTitleAccepted => 'Report accepted';

  @override
  String get notifFeedTitleCancelled => 'Report cancelled';

  @override
  String get notifFeedTitleMessage => 'New message';

  @override
  String get respEnRouteDone => 'You are marked en route. The dispatcher and the resident can see it.';

  @override
  String get respArrivedDone => 'You are marked on scene. The dispatcher and the resident can see it.';

  @override
  String get settingsProfileSaved => 'Your profile was saved.';

  @override
  String get welcomeResumeTitle => 'Continue where you left off?';

  @override
  String get welcomeResumeBody => 'You started creating an account on this phone but did not finish.';

  @override
  String get welcomeResumeContinue => 'Continue';

  @override
  String get welcomeResumeStartOver => 'Start over';

  @override
  String get respActiveAssignmentTitle => 'Active Assignment';

  @override
  String get respActiveAssignmentBody => 'You currently have an active incident assignment. Signing out may prevent you from receiving important updates.';

  @override
  String get respStaySignedIn => 'Stay Signed In';

  @override
  String get respNearbyTitle => 'Incidents near you';

  @override
  String get respNearbySubtitle => 'Nobody has been sent yet. You can say whether you\'re able to go — the dispatcher decides who responds.';

  @override
  String get respNearbyDistanceUnknown => 'Distance unknown';

  @override
  String respNearbyAlreadyOn(String category) {
    return 'You are already on $category';
  }

  @override
  String get respNearbyNotAvailable => 'Not available';

  @override
  String get respNearbyCanRespond => 'I can respond';

  @override
  String get respNearbyAnsweredYes => 'You said you can respond';

  @override
  String get respNearbyAnsweredNo => 'You said you are not available';

  @override
  String get respNearbySosChip => 'SOS';

  @override
  String get hotlinesTitle => 'Emergency hotlines';

  @override
  String hotlinesForCategory(String category) {
    return 'Hotlines for $category';
  }

  @override
  String get hotlinesSheetSubtitle => 'Tap a number to open your phone\'s dialer. The nearest town is listed first.';

  @override
  String get hotlinesOfflineTitle => 'No internet — call a station directly';

  @override
  String get hotlinesOfflineBody => 'Your report can\'t be sent right now. A regular call still works with just a phone signal.';

  @override
  String get hotlinesNearest => 'Nearest';

  @override
  String get hotlinesCallNow => 'Call now';

  @override
  String hotlinesCallSemantics(String number) {
    return 'Call $number';
  }

  @override
  String hotlinesCallFailed(String number) {
    return 'Couldn\'t open the dialer. Dial $number yourself.';
  }

  @override
  String get hotlinesNational => 'National Emergency Hotline';

  @override
  String get hotlinesNationalScope => 'Anywhere in the Philippines';

  @override
  String get hotlinesRhu => 'Rural Health Unit';

  @override
  String get hotlinesSeeAll => 'See all station hotlines';

  @override
  String get hotlinesScreenIntro => 'Official numbers of every BFP, PNP and MDRRMO station in Biliran. They work without internet — only a phone signal is needed.';

  @override
  String get hotlinesFilterAll => 'All';

  @override
  String get hotlinesHomeCardTitle => 'Station hotlines';

  @override
  String get hotlinesHomeCardBody => 'Call BFP, PNP or MDRRMO directly — works even without internet.';

  @override
  String get hotlinesCallInstead => 'Call a station instead';

  @override
  String get hotlinesStationCall => 'Call';

  @override
  String get homeOfflineCallHint => 'No internet. Tap a category below to see the station numbers to call.';

  @override
  String get locWhereTitle => 'Where is the incident?';

  @override
  String get locHere => 'I\'m at the incident';

  @override
  String get locElsewhere => 'Somewhere else';

  @override
  String get locPickedPoint => 'Location placed on the map';

  @override
  String get locElsewhereNote => 'The station will be told you are reporting from somewhere else.';

  @override
  String locElsewhereNoteFrom(String place) {
    return 'The station will be told you are reporting from $place.';
  }

  @override
  String get locChange => 'Change';

  @override
  String get locRefresh => 'Refresh location';

  @override
  String get locDeniedPickHint => 'No GPS? Choose \"Somewhere else\" and place the incident on the map.';

  @override
  String get locLandmarkRequired => 'Landmark (required)';

  @override
  String get locLandmarkMissing => 'Add a landmark so the responders can find the place.';

  @override
  String get locLandmarkAutoFilled => 'Filled in from the nearest landmark on the map — check that it is right.';

  @override
  String get locPickTitle => 'Where is the incident?';

  @override
  String get locPickHint => 'Move the map until the pin is on the incident, or search a barangay or landmark.';

  @override
  String get locPickConfirm => 'Use this location';

  @override
  String get locSearchHint => 'Search barangay or landmark';

  @override
  String get locSearchClear => 'Clear search';

  @override
  String get locKindLandmark => 'Landmark';

  @override
  String get locKindPlace => 'Barangay / place';

  @override
  String locNearLandmark(String landmark) {
    return 'Near $landmark';
  }

  @override
  String get locReviewReporterLabel => 'You are reporting from';

  @override
  String get locReviewReporterUnknown => 'Your location is unknown';

  @override
  String get helpTitle => 'How to use Ziren';

  @override
  String get helpIntroResident => 'Short guides to the things you will do in Ziren. Tap a topic to open its steps.';

  @override
  String get helpIntroResponder => 'Short guides for responders: duty, assignments, status updates and your own safety. Tap a topic to open its steps.';

  @override
  String get helpStillStuck => 'Still need help? Call your station';

  @override
  String get helpHomeLink => 'How to use Ziren?';

  @override
  String get mascotName => 'Hi! I\'m Ziren';

  @override
  String mascotResidentIntro(String name) {
    return '$name, in an emergency, tap the big button below and I\'ll get your report to the nearest station.';
  }

  @override
  String mascotResidentOpen(String count, String name) {
    return '$count of your reports are still being handled. I\'m right here with you, $name.';
  }

  @override
  String mascotResidentThanks(String count, String name) {
    return 'You\'ve sent $count reports so far. Thank you for looking out for your community, $name!';
  }

  @override
  String get mascotResidentOffline => 'You\'re offline right now. Tap an emergency type below to see the station numbers you can call.';

  @override
  String mascotResponderOffDuty(String name) {
    return 'You\'re off duty, $name. Turn on Duty Status below to receive dispatches.';
  }

  @override
  String mascotResponderQueue(String count, String critical, String name) {
    return 'You have $count assigned incidents, $critical critical. Stay safe out there, $name!';
  }

  @override
  String mascotResponderReady(String name) {
    return 'You\'re on duty and ready, $name. Nothing is assigned to you right now.';
  }

  @override
  String get helpButtonLabel => 'Ask Ziren for help';

  @override
  String get helpSheetClose => 'Close';

  @override
  String get homeProfileButtonLabel => 'Open your profile';

  @override
  String get respStatusNew => 'New';

  @override
  String get respStatusAccepted => 'Accepted';

  @override
  String get respStatusEnRoute => 'En route';

  @override
  String get respStatusOnScene => 'On scene';

  @override
  String get respStatusResolved => 'Resolved';

  @override
  String get respStatusCancelled => 'Cancelled';

  @override
  String get respStepAssigned => 'Assigned';

  @override
  String get respDutyOnTitle => 'On duty';

  @override
  String get respDutyOffTitle => 'Off duty';

  @override
  String respDutyOnBody(String station) {
    return 'Receiving dispatches · $station';
  }

  @override
  String get respDutyOnBodyPlain => 'Receiving dispatches';

  @override
  String get respDutyOffBody => 'You will not receive dispatches. Turn it on to start your shift.';

  @override
  String get respNextUpTitle => 'Do this first';

  @override
  String respNextUpCount(String count) {
    return '1 of $count';
  }

  @override
  String respOtherAssignments(String count) {
    return 'Other assignments ($count)';
  }

  @override
  String get respOpenAssignment => 'Open';

  @override
  String get respAnswerNow => 'Answer now';

  @override
  String respWaitingFor(String time) {
    return 'Waiting $time';
  }

  @override
  String respAssignedAgo(String time) {
    return 'Assigned $time ago';
  }

  @override
  String respClosedAgo(String time) {
    return 'Closed $time ago';
  }

  @override
  String respReportedAgo(String time) {
    return 'Reported $time ago';
  }

  @override
  String get respRecentClosedTitle => 'Recently closed';

  @override
  String get respNoLocation => 'No location';

  @override
  String get respReportsTitle => 'My reports';

  @override
  String get respReportsSubtitle => 'Everything a dispatcher has sent you.';

  @override
  String get respViewList => 'List';

  @override
  String get respViewRecord => 'Record';

  @override
  String get respFilterAll => 'All';

  @override
  String get respFilterOpen => 'Open';

  @override
  String get respFilterClosed => 'Closed';

  @override
  String get respSearchHint => 'Search barangay, INC or words';

  @override
  String respSearchEmpty(String query) {
    return 'Nothing matches \"$query\".';
  }

  @override
  String respSectionOpen(String count) {
    return 'Open, needs you ($count)';
  }

  @override
  String get respSectionThisWeek => 'Closed this week';

  @override
  String get respSectionLastWeek => 'Closed last week';

  @override
  String get respSectionOlder => 'Closed earlier';

  @override
  String get respHistoryCapNote => 'Showing your 50 most recent closed incidents.';

  @override
  String get respEmptyOpenTitle => 'Nothing open';

  @override
  String get respEmptyOpenBody => 'No assignment is waiting on you right now.';

  @override
  String get respEmptyClosedTitle => 'Nothing closed yet';

  @override
  String get respEmptyClosedBody => 'Incidents you finish will be filed here.';

  @override
  String get respEmptyAllTitle => 'No reports yet';

  @override
  String get respEmptyAllBody => 'Anything a dispatcher sends you will appear here, open or closed.';

  @override
  String get respRecTotalClosed => 'Closed in total';

  @override
  String get respRecThisWeek => 'Closed this week';

  @override
  String get respRecCritical => 'Critical handled';

  @override
  String get respRecTypical => 'Typical response';

  @override
  String get respRecChartTitle => 'Closed incidents';

  @override
  String get respRec7Days => '7 days';

  @override
  String get respRec8Weeks => '8 weeks';

  @override
  String respRecNoneInRange(String time) {
    return 'None closed in this period. Your last one was closed $time ago.';
  }

  @override
  String get respRecNoneEver => 'None closed in this period.';

  @override
  String get respRecMixTitle => 'Severity of what you closed';

  @override
  String get respRecCategoryTitle => 'Types of incident';

  @override
  String respRecTotal(String count) {
    return '$count total';
  }

  @override
  String get respRecReports => 'reports';

  @override
  String get respRecEmptyTitle => 'Nothing to show yet';

  @override
  String get respRecEmptyBody => 'Close your first incident and your record will show up here.';

  @override
  String get respRecTruncated => 'Your history is capped at 50 incidents, so the earliest part of this chart may be undercounted.';

  @override
  String get respRecWeekOf => 'wk';

  @override
  String get respStepsTitle => 'Progress';

  @override
  String get respNextStep => 'Next step';

  @override
  String get respCall => 'Call';

  @override
  String get respCopy => 'Copy';

  @override
  String get respGpsCopied => 'Coordinates copied.';

  @override
  String get respVerified => 'Verified';

  @override
  String get respUnverified => 'Not verified';

  @override
  String get respReporterUnknown => 'Unknown reporter';

  @override
  String get respCardReport => 'What happened';

  @override
  String get respCardLocation => 'Where';

  @override
  String get respCardReporter => 'Who reported';

  @override
  String get respCardStation => 'Your station';

  @override
  String get respClosedBanner => 'This incident is closed. Nothing else to do here.';

  @override
  String get respEmergencyContactShort => 'Emergency contact';

  @override
  String get profileChipVerified => 'Verified';

  @override
  String get profileChipInReview => 'In review';

  @override
  String get profileChipNotVerified => 'Not verified';

  @override
  String get profileSafetyHelp => 'Safety & help';

  @override
  String get profileStationContact => 'Station contact';

  @override
  String get profileStationSection => 'Station';

  @override
  String get profileSettings => 'Settings';

  @override
  String get profileCallStation => 'Call the station';

  @override
  String get settingsAccountCardHint => 'View and edit your details';

  @override
  String get settingsNotifDesc => 'Updates on your reports and alerts';

  @override
  String get settingsLocationDesc => 'Sends your location with a report';

  @override
  String get settingsReduceMotionDesc => 'Fewer moving animations';

  @override
  String get settingsHighContrastDesc => 'Stronger text and borders';

  @override
  String get settingsSaveChanges => 'Save changes';

  @override
  String get settingsDiscardTitle => 'Discard your changes?';

  @override
  String get settingsDiscardBody => 'You have edits that are not saved yet.';

  @override
  String get settingsDiscard => 'Discard';

  @override
  String get settingsKeepEditing => 'Keep editing';

  @override
  String get settingsEditorIntro => 'Stations see these details when you send a report.';

  @override
  String get cpIntro => 'Enter your current password, then choose a new one.';

  @override
  String get cpCurrent => 'Current password';

  @override
  String get cpNew => 'New password';

  @override
  String get cpConfirm => 'Confirm new password';

  @override
  String get cpEnterCurrent => 'Enter your current password.';

  @override
  String get cpMismatch => 'The two new passwords do not match.';

  @override
  String get cpSameAsOld => 'Your new password must be different from your current one.';

  @override
  String get cpWrongCurrent => 'Your current password is not correct.';

  @override
  String get cpFailed => 'Could not change your password. Check your connection and try again.';

  @override
  String get cpDone => 'Your password was changed.';

  @override
  String get cpForgot => 'Forgot your current password?';

  @override
  String get faqIntro => 'Quick answers to common questions.';

  @override
  String get faqStillNeedHelp => 'Still need help?';

  @override
  String get settingsFaqLandmarkQ => 'Why is a landmark required?';

  @override
  String get settingsFaqLandmarkA => 'GPS can be off by tens of metres. A landmark (a store, a chapel, a court) lets the responder find the place fast. Ziren fills in the nearest one for you; correct it if it is wrong.';

  @override
  String get settingsFaqElsewhereQ => 'The emergency is not where I am. What do I do?';

  @override
  String get settingsFaqElsewhereA => 'In the report, choose \"Somewhere else\" and move the map pin to where the incident is. Responders go to the pin, not to you, and the station is told you are reporting from elsewhere.';

  @override
  String get settingsFaqTrackQ => 'How do I know help is coming?';

  @override
  String get settingsFaqTrackA => 'Open My Reports. Each report shows how far it has gone — received, dispatched, on the way, on scene, resolved — and you get a notification each time it changes.';

  @override
  String get settingsFaqVerifyQ => 'Do I have to verify my account?';

  @override
  String get settingsFaqVerifyA => 'No, it is optional. A verified account (a photo of a valid ID) helps stations trust your reports faster.';

  @override
  String get safetyGuideIntro => 'What to do before help arrives. Works without internet.';

  @override
  String safetyGuideSteps(String count) {
    return '$count steps';
  }

  @override
  String get safetyGuideCallHotline => 'Call a hotline';

  @override
  String get aboutAgencies => 'Connects residents with the BFP, PNP and MDRRMO stations of Biliran.';

  @override
  String get sosWhereSection => 'Where you are (auto-detected)';

  @override
  String get sosLandmarkFinding => 'Finding the nearest landmark…';

  @override
  String sosLandmarkNear(String landmark) {
    return 'Near $landmark';
  }

  @override
  String get sosLandmarkAuto => 'Nearest landmark on the map · tap to change';

  @override
  String get sosLandmarkTyped => 'Landmark you added · tap to change';

  @override
  String get sosLandmarkNone => 'No landmark found nearby';

  @override
  String get sosLandmarkNoneHint => 'Tap to add one — optional';

  @override
  String get sosLandmarkEditTitle => 'Landmark near you';

  @override
  String get sosLandmarkEditBody => 'What can the responders look for? Leave it empty to use the one found on the map.';

  @override
  String get sosLandmarkEditHint => 'e.g. beside the barangay hall';

  @override
  String get sosLandmarkEditSave => 'Use this';

  @override
  String get sosLandmarkEditCancel => 'Cancel';

  @override
  String mapStationsOnMap(String count) {
    return 'Stations on the map: $count';
  }

  @override
  String get mapRecenter => 'Go to my location';

  @override
  String get mapNearestStation => 'Nearest station';

  @override
  String get mapSelectedStation => 'Selected station';

  @override
  String mapOtherStations(String count) {
    return 'Other stations ($count)';
  }

  @override
  String get stageShortReceived => 'Received';

  @override
  String get stageShortChecking => 'Checking';

  @override
  String get stageShortOnTheWay => 'On the way';

  @override
  String get stageShortResolved => 'Resolved';

  @override
  String reportSentAt(String when) {
    return 'Sent $when';
  }

  @override
  String get reportSectionYourReport => 'What you reported';

  @override
  String get reportSectionProgress => 'Progress';

  @override
  String get reportSectionLocation => 'Location';

  @override
  String get reportSectionDetails => 'Details';

  @override
  String get reportFactId => 'Report number';

  @override
  String get reportFactVia => 'Sent through';

  @override
  String get reportFactAddress => 'Address';

  @override
  String get reportFactDistance => 'From where you are now';

  @override
  String reportDistanceKm(String km) {
    return '$km km away';
  }

  @override
  String get reportViaApp => 'Ziren app';

  @override
  String get reportViaSos => 'Emergency SOS';

  @override
  String get reportViaSms => 'Text message (SMS)';

  @override
  String reportNextStep(String step) {
    return 'Next: $step';
  }

  @override
  String get mapYourReportLabel => 'Your report';

  @override
  String onbStep(String step, String total) {
    return 'Step $step of $total';
  }

  @override
  String get onbLangGreeting => 'Hi, I\'m Ziren! Which language would you like me to use?';

  @override
  String get onbLangTitle => 'Choose your language';

  @override
  String get onbLangSubtitle => 'The whole app will use it. You can change it any time in Settings.';

  @override
  String get onbLangMoreSoon => 'Waray and Bisaya are coming once a native speaker has reviewed them.';

  @override
  String get onbLangContinue => 'Continue';

  @override
  String get onbLangSelected => 'Selected';

  @override
  String consentAgreedCount(String done) {
    return '$done of 2 agreed';
  }

  @override
  String get consentNeedsReading => 'Open to read';

  @override
  String get consentAgreed => 'Agreed';

  @override
  String get welcomeHeadline => 'Help, one tap away.';

  @override
  String get welcomeFeatureReport => 'Report a fire, accident or medical emergency in seconds';

  @override
  String get welcomeFeatureStation => 'Your report goes straight to the nearest BFP, PNP or MDRRMO station';

  @override
  String get welcomeFeatureTrack => 'See when a responder is on the way';

  @override
  String get welcomeNewHere => 'New to Ziren?';

  @override
  String legalMeta(String sections, String minutes) {
    return '$sections sections · about $minutes min read';
  }

  @override
  String legalProgress(String percent) {
    return '$percent% read';
  }

  @override
  String get legalReachedEnd => 'You\'ve reached the end';

  @override
  String get legalBackToTop => 'Back to top';

  @override
  String get welcomeMascotLine => 'You\'re all set! Create an account, or sign in if you already have one.';

  @override
  String get categoryMissingPerson => 'Missing person';

  @override
  String get categoryEmergency => 'Emergency';

  @override
  String get respStatusDispatchedRespond => 'Dispatched — Respond Now';

  @override
  String get respNextEnRoute => 'On my way (En Route)';

  @override
  String get respNextOnScene => 'Arrived (On Scene)';

  @override
  String get respNextResolved => 'Done (Resolved)';

  @override
  String get respNoAddress => 'No address recorded';

  @override
  String get respAlertOverdueNote => 'The dispatcher now sees this as unanswered. You can still accept it.';

  @override
  String get respAlertTimeoutNote => 'If nobody answers, it goes back to the dispatcher so they can send someone else.';

  @override
  String get respNoMapApp => 'No map app could be opened on this phone.';

  @override
  String get respJustNow => 'just now';

  @override
  String get wizardSpeakDetails => 'Speak the details';

  @override
  String get wizardListening => 'Listening… (tap to stop)';

  @override
  String get wizardNext => 'Next →';

  @override
  String get respNavByRoad => 'by road';

  @override
  String get respNavRoadNote => 'The route follows the roads on the map. Watch for closed or flooded roads.';

  @override
  String get accountNoticeEyebrow => 'Account notice';

  @override
  String get accountWarnedTitle => 'You received a warning';

  @override
  String accountWarnedBody(String reason) {
    return 'Reason: $reason.';
  }

  @override
  String accountWarnedLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more warnings and your account will be suspended from reporting.',
      one: 'One more warning and your account will be suspended from reporting.',
    );
    return '$_temp0';
  }

  @override
  String get accountSuspendedTitle => 'Reporting is suspended';

  @override
  String accountSuspendedUntil(String date) {
    return 'You cannot send reports until $date.';
  }

  @override
  String get accountSuspendedIndefinite => 'You cannot send reports until further notice.';

  @override
  String get accountSuspendedHelp => 'In a real emergency, call 911 or a hotline. To appeal, contact your municipal MDRRMO office.';

  @override
  String get accountOpenHotlines => 'Emergency hotlines';

  @override
  String get accountReinstatedTitle => 'You can send reports again';

  @override
  String get accountReinstatedBody => 'Your suspension was lifted.';

  @override
  String get accountWarningsClearedBody => 'Your warnings were cleared.';

  @override
  String get violationFalseReport => 'Sending a false or prank report';

  @override
  String get violationFalseSos => 'Misusing the SOS button';

  @override
  String get violationSpam => 'Sending repeated or duplicate reports';

  @override
  String get violationAbusive => 'Abusive or threatening messages';

  @override
  String get violationFakeIdentity => 'Using a false or borrowed identity';

  @override
  String get violationOther => 'A violation of the reporting rules';

  @override
  String get annWholeProvince => 'Whole province';

  @override
  String get annKindEvacuation => 'Evacuation order';

  @override
  String get annKindWeather => 'Weather advisory';

  @override
  String get annKindHazard => 'Hazard warning';

  @override
  String get annKindRoadClosure => 'Road closure';

  @override
  String get annKindMissingPerson => 'Missing person';

  @override
  String get annKindAllClear => 'All clear';

  @override
  String get annKindRelief => 'Relief distribution';

  @override
  String get annKindHealth => 'Health advisory';

  @override
  String get annKindDrill => 'Drill';

  @override
  String get annKindUtility => 'Power / water interruption';

  @override
  String get annHazardFlood => 'Flood';

  @override
  String get annHazardLandslide => 'Landslide';

  @override
  String get annHazardStormSurge => 'Storm surge';

  @override
  String get annHazardEarthquake => 'Earthquake';

  @override
  String get annHazardTsunami => 'Tsunami';

  @override
  String get annHazardVolcanic => 'Volcanic activity';

  @override
  String get annHazardFire => 'Fire';

  @override
  String get annHazardOther => 'Other hazard';

  @override
  String get annRainfallYellow => 'Yellow rainfall warning';

  @override
  String get annRainfallOrange => 'Orange rainfall warning';

  @override
  String get annRainfallRed => 'Red rainfall warning';

  @override
  String annSignal(int n) {
    return 'Signal No. $n';
  }

  @override
  String get annEvacForced => 'Forced';

  @override
  String get annEvacPreemptive => 'Pre-emptive';

  @override
  String annReopens(String when) {
    return 'Reopens $when';
  }

  @override
  String annAge(int age) {
    return 'Age $age';
  }

  @override
  String get annGoTo => 'Go to';

  @override
  String get annBring => 'Bring';

  @override
  String get annArea => 'Area';

  @override
  String get annClosed => 'Closed';

  @override
  String get annUseInstead => 'Use instead';

  @override
  String get annName => 'Name';

  @override
  String get annLastSeen => 'Last seen';

  @override
  String get annLooksLike => 'Looks like';

  @override
  String get annCall => 'Call';

  @override
  String get annWhere => 'Where';

  @override
  String get annFrom => 'From';

  @override
  String get annNeedHelpTitle => 'Ask for help';

  @override
  String get annNeedHelpBody => 'The stations of your town are told at once, with where your phone is. Add a line if you can - how many of you, what is happening.';

  @override
  String get annNeedHelpHint => 'e.g. Three of us on the roof, water rising';

  @override
  String get annNeedHelpSend => 'Send: I need help';

  @override
  String get annCancel => 'Cancel';

  @override
  String get annSentSafe => 'Sent: you are safe. Thank you.';

  @override
  String get annSentHelp => 'Sent. The stations of your town have been told.';

  @override
  String get annEndedTitle => 'This alert has ended';

  @override
  String get annEndedBody => 'An all clear was sent or it expired, so it takes no more answers. If you still need help, call a hotline.';

  @override
  String get annNotSentTitle => 'Your answer was not sent';

  @override
  String get annNotSentHelpBody => 'Ziren could not reach the server. If you need help now, call a hotline - a call needs only signal.';

  @override
  String get annNotSentBody => 'Ziren could not reach the server. Try again when you have a connection.';

  @override
  String get annAreYouSafe => 'Are you safe?';

  @override
  String get annImSafe => 'I am safe';

  @override
  String get annINeedHelp => 'I need help';

  @override
  String get annYouSaidSafe => 'You said you are safe.';

  @override
  String get annYouAskedHelp => 'You asked for help. The stations have been told.';

  @override
  String get annHelpReached => 'A station has your call for help and is responding.';

  @override
  String get annHelpWhileWaiting => 'Stay where it is safest. If it gets worse, call a hotline.';

  @override
  String get annChange => 'Change';

  @override
  String get annSafetyAlerts => 'Safety alerts';

  @override
  String get annUpdates => 'Updates';

  @override
  String annIssuedBy(String office) {
    return 'From $office';
  }

  @override
  String annUntil(String date) {
    return 'Until $date';
  }

  @override
  String get annEnded => 'Ended';

  @override
  String annEndsTitle(String title) {
    return 'Ends: $title';
  }

  @override
  String annEndedBy(String title) {
    return 'Ended by: $title';
  }

  @override
  String get annNotFoundTitle => 'Not available';

  @override
  String get annNotFoundBody => 'This announcement was taken down, or it is not for your area.';

  @override
  String annHomeMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more alerts',
      one: '1 more alert',
    );
    return '$_temp0';
  }

  @override
  String get annSeeDetails => 'See details';

  @override
  String get annNoticeEyebrow => 'Safety alert';

  @override
  String get annNoticeEyebrowInfo => 'Announcement';

  @override
  String get annRespondNow => 'Answer: are you safe?';

  @override
  String get annOpen => 'Open';

  @override
  String get annHelpAckTitle => 'Your call for help was received';

  @override
  String annHelpAckBody(String station) {
    return '$station has your request and is responding. Stay where it is safest.';
  }

  @override
  String welcomeDemoTitle(String name) {
    return 'Hi, $name!';
  }

  @override
  String get welcomeDemoTitleNoName => 'Hi there!';

  @override
  String get welcomeDemoBodyResident => 'Welcome to Ziren! Want me to show you around the app first? It takes a minute, and nothing is sent while I show you.';

  @override
  String get welcomeDemoBodyResponder => 'Welcome to the team! Want me to show you around your screens first? It takes a minute, and nothing is changed while I show you.';

  @override
  String get welcomeDemoStart => 'Yes, show me';

  @override
  String get welcomeDemoLater => 'Maybe later';

  @override
  String welcomeDemoHint(String button) {
    return 'You can watch it anytime: tap \"$button\" on Home, then Demo.';
  }
}
