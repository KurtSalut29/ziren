import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil')
  ];

  /// No description provided for @regIdTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an ID'**
  String get regIdTypeTitle;

  /// No description provided for @regIdTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We use it once, to confirm you are a real person in Biliran.'**
  String get regIdTypeSubtitle;

  /// No description provided for @actionTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get actionTakePhoto;

  /// No description provided for @regTakeIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your ID'**
  String get regTakeIdPhoto;

  /// No description provided for @regIdPhotoTips.
  ///
  /// In en, this message translates to:
  /// **'Flat, well lit, all four corners visible'**
  String get regIdPhotoTips;

  /// No description provided for @regIdReadable.
  ///
  /// In en, this message translates to:
  /// **'Your ID looks readable.'**
  String get regIdReadable;

  /// Success sheet heading after a report is submitted
  ///
  /// In en, this message translates to:
  /// **'Report Received'**
  String get reportReceivedTitle;

  /// Success sheet subheading. Deliberately makes no promise about response time.
  ///
  /// In en, this message translates to:
  /// **'Your report is now with the dispatcher.'**
  String get reportReceivedBody;

  /// Label before the incident category, confirming what was understood. Acknowledgement only — never severity or priority.
  ///
  /// In en, this message translates to:
  /// **'Recorded as'**
  String get recordedAs;

  /// Label before the station name the report was routed to
  ///
  /// In en, this message translates to:
  /// **'Sent to'**
  String get sentTo;

  /// Confirms GPS coordinates were included
  ///
  /// In en, this message translates to:
  /// **'Location attached'**
  String get locationAttached;

  /// Confirms media was included
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo or video} other{{count} photos or videos}}'**
  String mediaAttached(int count);

  /// No description provided for @reportIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Report ID'**
  String get reportIdLabel;

  /// No description provided for @trackReport.
  ///
  /// In en, this message translates to:
  /// **'Track Report'**
  String get trackReport;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHome;

  /// No description provided for @myReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'My Reports'**
  String get myReportsTitle;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterOpen.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get filterOpen;

  /// No description provided for @filterDone.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get filterDone;

  /// No description provided for @statusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get statusReceived;

  /// Deliberately not 'Processing' — that reads as machine work to a resident waiting for help.
  ///
  /// In en, this message translates to:
  /// **'Being reviewed'**
  String get statusProcessing;

  /// No description provided for @statusDispatched.
  ///
  /// In en, this message translates to:
  /// **'Responder on the way'**
  String get statusDispatched;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// Title of the status-update sheet shown when a resident's own report changes status.
  ///
  /// In en, this message translates to:
  /// **'Report update'**
  String get notifStatusTitle;

  /// Status-update sheet body, status = processing.
  ///
  /// In en, this message translates to:
  /// **'Your report is being reviewed.'**
  String get notifStatusProcessing;

  /// Status-update sheet body, status = dispatched.
  ///
  /// In en, this message translates to:
  /// **'A responder is on the way.'**
  String get notifStatusDispatched;

  /// Status-update sheet body, status = resolved.
  ///
  /// In en, this message translates to:
  /// **'Your report has been marked resolved.'**
  String get notifStatusResolved;

  /// Status-update sheet body, status = cancelled.
  ///
  /// In en, this message translates to:
  /// **'Your report was cancelled.'**
  String get notifStatusCancelled;

  /// Dismiss button on the status-update sheet.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get notifStatusOk;

  /// No description provided for @noReportsYet.
  ///
  /// In en, this message translates to:
  /// **'No reports yet'**
  String get noReportsYet;

  /// No description provided for @noReportsYetBody.
  ///
  /// In en, this message translates to:
  /// **'Reports you submit will appear here.'**
  String get noReportsYetBody;

  /// No description provided for @noOpenReports.
  ///
  /// In en, this message translates to:
  /// **'No open reports'**
  String get noOpenReports;

  /// No description provided for @noOpenReportsBody.
  ///
  /// In en, this message translates to:
  /// **'All your reports are closed.'**
  String get noOpenReportsBody;

  /// No description provided for @noResolvedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing resolved yet'**
  String get noResolvedYet;

  /// No description provided for @noResolvedYetBody.
  ///
  /// In en, this message translates to:
  /// **'Resolved reports will appear here.'**
  String get noResolvedYetBody;

  /// No description provided for @noDetails.
  ///
  /// In en, this message translates to:
  /// **'No details'**
  String get noDetails;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @groupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get groupToday;

  /// No description provided for @groupYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get groupYesterday;

  /// No description provided for @groupThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get groupThisWeek;

  /// No description provided for @groupThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get groupThisMonth;

  /// No description provided for @groupOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get groupOlder;

  /// No description provided for @categoryFire.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get categoryFire;

  /// No description provided for @categoryMedicalTrauma.
  ///
  /// In en, this message translates to:
  /// **'Medical / Trauma'**
  String get categoryMedicalTrauma;

  /// No description provided for @categoryVehicular.
  ///
  /// In en, this message translates to:
  /// **'Road Accident'**
  String get categoryVehicular;

  /// No description provided for @categoryFloodLandslideCalamity.
  ///
  /// In en, this message translates to:
  /// **'Flood / Landslide / Calamity'**
  String get categoryFloodLandslideCalamity;

  /// No description provided for @categoryDomesticDisputeCrime.
  ///
  /// In en, this message translates to:
  /// **'Disturbance / Crime'**
  String get categoryDomesticDisputeCrime;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @preferredLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get preferredLanguage;

  /// No description provided for @reportsOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{open} open · {total} total'**
  String reportsOpenCount(int open, int total);

  /// No description provided for @reportsAllDone.
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =1{1 report · closed} other{{total} reports · all closed}}'**
  String reportsAllDone(int total);

  /// No description provided for @noReportsYetLong.
  ///
  /// In en, this message translates to:
  /// **'When you report an emergency, every step of the response will show up here.'**
  String get noReportsYetLong;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get consentTitle;

  /// No description provided for @consentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please read and agree to both documents below.'**
  String get consentSubtitle;

  /// No description provided for @consentSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'The short version'**
  String get consentSummaryTitle;

  /// No description provided for @consentSummaryLocation.
  ///
  /// In en, this message translates to:
  /// **'We use your location and contact details so responders can find you.'**
  String get consentSummaryLocation;

  /// No description provided for @consentSummaryReporting.
  ///
  /// In en, this message translates to:
  /// **'You can always report an emergency, verified or not.'**
  String get consentSummaryReporting;

  /// No description provided for @consentSummaryPhotos.
  ///
  /// In en, this message translates to:
  /// **'Your ID and face photos are private, and deleted once checked.'**
  String get consentSummaryPhotos;

  /// No description provided for @consentSummaryNotHotline.
  ///
  /// In en, this message translates to:
  /// **'Ziren does not replace 911. Call directly if the app cannot reach the network.'**
  String get consentSummaryNotHotline;

  /// No description provided for @consentPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Privacy Notice'**
  String get consentPrivacyTitle;

  /// No description provided for @consentPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'What we collect and why'**
  String get consentPrivacySubtitle;

  /// No description provided for @consentTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get consentTermsTitle;

  /// No description provided for @consentTermsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What Ziren does, and what it does not do'**
  String get consentTermsSubtitle;

  /// No description provided for @consentActionRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get consentActionRead;

  /// No description provided for @consentBadgeRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get consentBadgeRead;

  /// No description provided for @consentAgreePrivacy.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Data Privacy Notice'**
  String get consentAgreePrivacy;

  /// No description provided for @consentAgreeTerms.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Use'**
  String get consentAgreeTerms;

  /// No description provided for @consentMustReadFirst.
  ///
  /// In en, this message translates to:
  /// **'Open each document first.'**
  String get consentMustReadFirst;

  /// No description provided for @consentContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get consentContinue;

  /// No description provided for @legalReadConfirm.
  ///
  /// In en, this message translates to:
  /// **'I have read this'**
  String get legalReadConfirm;

  /// No description provided for @legalScrollHint.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the end to continue'**
  String get legalScrollHint;

  /// No description provided for @legalClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get legalClose;

  /// No description provided for @legalLoadError.
  ///
  /// In en, this message translates to:
  /// **'This document could not be opened. Please update the app or contact your MDRRMO office.'**
  String get legalLoadError;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Emergency response for Biliran.'**
  String get welcomeTagline;

  /// No description provided for @welcomeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get welcomeSignIn;

  /// No description provided for @welcomeCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get welcomeCreateAccount;

  /// No description provided for @welcomeHasAccount.
  ///
  /// In en, this message translates to:
  /// **'Already registered?'**
  String get welcomeHasAccount;

  /// No description provided for @homeOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get homeOnline;

  /// No description provided for @homeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get homeOffline;

  /// No description provided for @homeConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get homeConnecting;

  /// No description provided for @homeEmergency.
  ///
  /// In en, this message translates to:
  /// **'EMERGENCY'**
  String get homeEmergency;

  /// No description provided for @categoryFireShort.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get categoryFireShort;

  /// No description provided for @categoryMedicalShort.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get categoryMedicalShort;

  /// No description provided for @categoryCrimeShort.
  ///
  /// In en, this message translates to:
  /// **'Crime'**
  String get categoryCrimeShort;

  /// No description provided for @categoryCalamityShort.
  ///
  /// In en, this message translates to:
  /// **'Calamity'**
  String get categoryCalamityShort;

  /// No description provided for @categoryAccidentShort.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get categoryAccidentShort;

  /// No description provided for @categoryOtherShort.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOtherShort;

  /// No description provided for @homeLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get homeLocation;

  /// No description provided for @homeTimeNow.
  ///
  /// In en, this message translates to:
  /// **'Time now'**
  String get homeTimeNow;

  /// No description provided for @homeRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get homeRouting;

  /// Resident's barangay in the hero fact strip. 'Brgy.' is the standard Philippine abbreviation and stays untranslated in both locales.
  ///
  /// In en, this message translates to:
  /// **'Brgy. {name}'**
  String homeBarangay(String name);

  /// Hero fact value when the profile carries no barangay. Says the app does not know, never guesses.
  ///
  /// In en, this message translates to:
  /// **'Not known yet'**
  String get homeLocationUnknown;

  /// Hero fact value: the report will be routed by the server.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get homeRoutingAuto;

  /// Caption under the SOS button for someone who cannot name the emergency.
  ///
  /// In en, this message translates to:
  /// **'Not sure? Press this'**
  String get homeSosHint;

  /// Greeting name when neither the profile nor the email supplies one.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get homeResidentFallbackName;

  /// Action link on the Safe places card, opens the station map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get homeMapAction;

  /// Delivery band at the top of Home. States how the next report will travel, before it is sent.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get homeDeliveryOnlineTitle;

  /// No description provided for @homeDeliveryOnlineDetail.
  ///
  /// In en, this message translates to:
  /// **'Your report goes straight to the nearest station.'**
  String get homeDeliveryOnlineDetail;

  /// Shown when the phone has no working route to the server. There is no fallback delivery path — the copy must not imply a report can still get out.
  ///
  /// In en, this message translates to:
  /// **'No internet'**
  String get homeDeliveryOfflineTitle;

  /// No description provided for @homeDeliveryOfflineDetail.
  ///
  /// In en, this message translates to:
  /// **'Reports can\'t be sent right now. If this is an emergency, call 911 directly.'**
  String get homeDeliveryOfflineDetail;

  /// No description provided for @homeDeliveryCheckingTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking connection'**
  String get homeDeliveryCheckingTitle;

  /// No description provided for @homeDeliveryCheckingDetail.
  ///
  /// In en, this message translates to:
  /// **'Checking whether the server can be reached.'**
  String get homeDeliveryCheckingDetail;

  /// Screen-reader name and tooltip for the notification bell.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get homeBellLabel;

  /// Bell label when unread notifications exist. The unread dot is colour-only, so the state has to be spoken here.
  ///
  /// In en, this message translates to:
  /// **'Notifications, new items'**
  String get homeBellLabelUnread;

  /// Screen-reader label for one category chip on the SOS dial. The chip shows only an icon and a short label, so the verb has to come from here.
  ///
  /// In en, this message translates to:
  /// **'Report {category}'**
  String homeReportAction(String category);

  /// No description provided for @homeAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get homeAlerts;

  /// No description provided for @homeAlertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No new alerts. Updates on your reports will appear here.'**
  String get homeAlertsEmpty;

  /// No description provided for @homeTapToView.
  ///
  /// In en, this message translates to:
  /// **'Tap to view'**
  String get homeTapToView;

  /// No description provided for @homeSafePlaces.
  ///
  /// In en, this message translates to:
  /// **'Safe places'**
  String get homeSafePlaces;

  /// No description provided for @homeStationsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not load the station list.'**
  String get homeStationsUnavailable;

  /// No description provided for @homeStationCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 station} other{{count} stations}}'**
  String homeStationCount(int count);

  /// No description provided for @agencyMdrrmo.
  ///
  /// In en, this message translates to:
  /// **'MDRRMO'**
  String get agencyMdrrmo;

  /// No description provided for @agencyPnp.
  ///
  /// In en, this message translates to:
  /// **'Police'**
  String get agencyPnp;

  /// No description provided for @agencyBfp.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get agencyBfp;

  /// No description provided for @homeMyReports.
  ///
  /// In en, this message translates to:
  /// **'Your reports'**
  String get homeMyReports;

  /// No description provided for @homeSeeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get homeSeeAll;

  /// No description provided for @homeNoReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get homeNoReportsTitle;

  /// No description provided for @homeNoReportsBody.
  ///
  /// In en, this message translates to:
  /// **'When you report an incident, you will see its status here.'**
  String get homeNoReportsBody;

  /// No description provided for @homeUntitledReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get homeUntitledReport;

  /// Home screen greeting, before noon.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}!'**
  String homeGreetingMorning(String name);

  /// Home screen greeting, noon to 6pm.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}!'**
  String homeGreetingAfternoon(String name);

  /// Home screen greeting, after 6pm.
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}!'**
  String homeGreetingEvening(String name);

  /// No description provided for @homeStayAlertBody.
  ///
  /// In en, this message translates to:
  /// **'Stay alert. Help is always near.'**
  String get homeStayAlertBody;

  /// No description provided for @homeReportCtaTitle.
  ///
  /// In en, this message translates to:
  /// **'Report an Emergency'**
  String get homeReportCtaTitle;

  /// No description provided for @homeReportCtaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The fastest way to reach a station — pick what\'s wrong, hold to send'**
  String get homeReportCtaSubtitle;

  /// No description provided for @homeReportCtaBadge.
  ///
  /// In en, this message translates to:
  /// **'FASTEST'**
  String get homeReportCtaBadge;

  /// No description provided for @homeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get homeRecentActivity;

  /// No description provided for @timeAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeAgoJustNow;

  /// No description provided for @timeAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String timeAgoMinutes(int count);

  /// No description provided for @timeAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeAgoHours(int count);

  /// No description provided for @timeAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeAgoDays(int count);

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Report an emergency, or respond to one.'**
  String get loginSubtitle;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get fieldEmail;

  /// No description provided for @hintEmail.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get hintEmail;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @hintPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get hintPassword;

  /// No description provided for @validationPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required.'**
  String get validationPasswordRequired;

  /// No description provided for @loginForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get loginForgotPassword;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginButton;

  /// No description provided for @loginNewToZiren.
  ///
  /// In en, this message translates to:
  /// **'New to Ziren?'**
  String get loginNewToZiren;

  /// No description provided for @loginCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get loginCreateAccount;

  /// No description provided for @regHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get regHaveAccount;

  /// No description provided for @authLegalIntro.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to Ziren\'s'**
  String get authLegalIntro;

  /// No description provided for @authLegalAnd.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get authLegalAnd;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @forgotSendLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get forgotSendLink;

  /// No description provided for @forgotBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get forgotBackToSignIn;

  /// No description provided for @forgotSentBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, a password reset link has been sent.'**
  String get forgotSentBody;

  /// No description provided for @pendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Account pending approval'**
  String get pendingTitle;

  /// No description provided for @pendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your Responder account has been created and is waiting for verification by your Agency Admin.'**
  String get pendingBody;

  /// No description provided for @pendingStep1.
  ///
  /// In en, this message translates to:
  /// **'Your Agency Admin reviews your badge ID'**
  String get pendingStep1;

  /// No description provided for @pendingStep2.
  ///
  /// In en, this message translates to:
  /// **'They confirm it against agency records'**
  String get pendingStep2;

  /// No description provided for @pendingStep3.
  ///
  /// In en, this message translates to:
  /// **'You are notified as soon as the account is approved'**
  String get pendingStep3;

  /// No description provided for @rejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account not approved'**
  String get rejectedTitle;

  /// No description provided for @rejectedBody.
  ///
  /// In en, this message translates to:
  /// **'Your Responder account was not approved by your Agency Admin. The most common reason is a badge ID that could not be matched to agency records.'**
  String get rejectedBody;

  /// No description provided for @rejectedStep1.
  ///
  /// In en, this message translates to:
  /// **'Contact your agency directly to confirm your badge ID'**
  String get rejectedStep1;

  /// No description provided for @rejectedStep2.
  ///
  /// In en, this message translates to:
  /// **'Ask your Agency Admin to review the account again'**
  String get rejectedStep2;

  /// No description provided for @pendingWhatNext.
  ///
  /// In en, this message translates to:
  /// **'What happens next'**
  String get pendingWhatNext;

  /// No description provided for @actionLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get actionLogOut;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navZirenAi.
  ///
  /// In en, this message translates to:
  /// **'Ziren AI'**
  String get navZirenAi;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get forgotTitle;

  /// No description provided for @forgotSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get forgotSentTitle;

  /// No description provided for @forgotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address and we will send you a link to set a new one.'**
  String get forgotSubtitle;

  /// No description provided for @regRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get regRoleTitle;

  /// No description provided for @regRoleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which of these are you?'**
  String get regRoleSubtitle;

  /// No description provided for @roleResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get roleResident;

  /// No description provided for @roleResponder.
  ///
  /// In en, this message translates to:
  /// **'Responder'**
  String get roleResponder;

  /// No description provided for @regRoleResidentBody.
  ///
  /// In en, this message translates to:
  /// **'Report emergencies where you live, and follow what happens to your report.'**
  String get regRoleResidentBody;

  /// No description provided for @regRoleResponderBody.
  ///
  /// In en, this message translates to:
  /// **'BFP, PNP or MDRRMO. Your Agency Admin approves the account before you can use it.'**
  String get regRoleResponderBody;

  /// No description provided for @regNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get regNameTitle;

  /// No description provided for @regNameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter it exactly as it appears on your ID.'**
  String get regNameSubtitle;

  /// No description provided for @fieldFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get fieldFirstName;

  /// No description provided for @hintFirstName.
  ///
  /// In en, this message translates to:
  /// **'Juan'**
  String get hintFirstName;

  /// No description provided for @fieldMiddleName.
  ///
  /// In en, this message translates to:
  /// **'Middle name'**
  String get fieldMiddleName;

  /// No description provided for @hintMiddleName.
  ///
  /// In en, this message translates to:
  /// **'Santos'**
  String get hintMiddleName;

  /// No description provided for @fieldLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get fieldLastName;

  /// No description provided for @hintLastName.
  ///
  /// In en, this message translates to:
  /// **'dela Cruz'**
  String get hintLastName;

  /// No description provided for @fieldSuffix.
  ///
  /// In en, this message translates to:
  /// **'Suffix'**
  String get fieldSuffix;

  /// No description provided for @hintSuffix.
  ///
  /// In en, this message translates to:
  /// **'Jr, Sr, III'**
  String get hintSuffix;

  /// No description provided for @fieldDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get fieldDateOfBirth;

  /// No description provided for @regChooseDob.
  ///
  /// In en, this message translates to:
  /// **'Choose your date of birth'**
  String get regChooseDob;

  /// No description provided for @regDobWhy.
  ///
  /// In en, this message translates to:
  /// **'A responding crew treats a 3-year-old and a 40-year-old differently for the same symptoms.'**
  String get regDobWhy;

  /// No description provided for @fieldSex.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get fieldSex;

  /// No description provided for @sexMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get sexMale;

  /// No description provided for @sexFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get sexFemale;

  /// No description provided for @sexPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get sexPreferNotToSay;

  /// No description provided for @regAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Where you live'**
  String get regAddressTitle;

  /// No description provided for @regAddressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This decides which station responds to you.'**
  String get regAddressSubtitle;

  /// No description provided for @fieldMunicipality.
  ///
  /// In en, this message translates to:
  /// **'Municipality'**
  String get fieldMunicipality;

  /// No description provided for @hintMunicipality.
  ///
  /// In en, this message translates to:
  /// **'Choose your municipality'**
  String get hintMunicipality;

  /// No description provided for @fieldBarangay.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get fieldBarangay;

  /// No description provided for @fieldPurok.
  ///
  /// In en, this message translates to:
  /// **'Purok or sitio'**
  String get fieldPurok;

  /// No description provided for @hintPurok.
  ///
  /// In en, this message translates to:
  /// **'Purok 3'**
  String get hintPurok;

  /// No description provided for @fieldStreet.
  ///
  /// In en, this message translates to:
  /// **'Street or landmark'**
  String get fieldStreet;

  /// No description provided for @hintStreet.
  ///
  /// In en, this message translates to:
  /// **'Rizal St, beside the chapel'**
  String get hintStreet;

  /// No description provided for @regStreetHelp.
  ///
  /// In en, this message translates to:
  /// **'What helps a crew find your door'**
  String get regStreetHelp;

  /// No description provided for @regChooseMunicipalityFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a municipality first'**
  String get regChooseMunicipalityFirst;

  /// No description provided for @hintBarangay.
  ///
  /// In en, this message translates to:
  /// **'Choose your barangay'**
  String get hintBarangay;

  /// No description provided for @regUseMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get regUseMyLocation;

  /// No description provided for @regFindingYou.
  ///
  /// In en, this message translates to:
  /// **'Finding you...'**
  String get regFindingYou;

  /// No description provided for @regLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission was declined.'**
  String get regLocationDenied;

  /// No description provided for @regLocationSet.
  ///
  /// In en, this message translates to:
  /// **'Municipality set from your location.'**
  String get regLocationSet;

  /// No description provided for @regLocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read your location. Choose it below.'**
  String get regLocationFailed;

  /// No description provided for @regNotInBiliran.
  ///
  /// In en, this message translates to:
  /// **'You do not appear to be in Biliran right now. Choose your home municipality below.'**
  String get regNotInBiliran;

  /// No description provided for @regBarangayListFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the barangay list. Check your connection.'**
  String get regBarangayListFailed;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @regContactTitle.
  ///
  /// In en, this message translates to:
  /// **'How we reach you'**
  String get regContactTitle;

  /// No description provided for @regContactSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A responder may need to call you on the way.'**
  String get regContactSubtitle;

  /// No description provided for @fieldMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get fieldMobile;

  /// No description provided for @hintMobile.
  ///
  /// In en, this message translates to:
  /// **'09XX XXX XXXX'**
  String get hintMobile;

  /// No description provided for @hintCreatePassword.
  ///
  /// In en, this message translates to:
  /// **'Create a password'**
  String get hintCreatePassword;

  /// No description provided for @passwordRule.
  ///
  /// In en, this message translates to:
  /// **'Min 8 characters, 1 uppercase, 1 number'**
  String get passwordRule;

  /// No description provided for @passwordReqTitle.
  ///
  /// In en, this message translates to:
  /// **'Your password must have:'**
  String get passwordReqTitle;

  /// No description provided for @passwordReqLength.
  ///
  /// In en, this message translates to:
  /// **'At least {count} characters'**
  String passwordReqLength(int count);

  /// No description provided for @passwordReqUpper.
  ///
  /// In en, this message translates to:
  /// **'1 uppercase letter (A-Z)'**
  String get passwordReqUpper;

  /// No description provided for @passwordReqNumber.
  ///
  /// In en, this message translates to:
  /// **'1 number (0-9)'**
  String get passwordReqNumber;

  /// No description provided for @passwordConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Type the same password again.'**
  String get passwordConfirmHint;

  /// No description provided for @fieldConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get fieldConfirmPassword;

  /// No description provided for @hintConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get hintConfirmPassword;

  /// No description provided for @fieldEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get fieldEmergencyContact;

  /// No description provided for @hintName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get hintName;

  /// No description provided for @hintTheirMobile.
  ///
  /// In en, this message translates to:
  /// **'Their mobile number'**
  String get hintTheirMobile;

  /// No description provided for @regEmergencyWhoTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact person'**
  String get regEmergencyWhoTitle;

  /// No description provided for @regEmergencyWhoBody.
  ///
  /// In en, this message translates to:
  /// **'Add ONE other person we can call if something happens to YOU — for example a parent, spouse, sibling or close friend. Enter THEIR name and number, not your own. You can skip this.'**
  String get regEmergencyWhoBody;

  /// No description provided for @hintEmergencyName.
  ///
  /// In en, this message translates to:
  /// **'Their full name (not yours)'**
  String get hintEmergencyName;

  /// No description provided for @hintEmergencyNumber.
  ///
  /// In en, this message translates to:
  /// **'Their mobile number (not yours)'**
  String get hintEmergencyNumber;

  /// No description provided for @regEmergencyNeedsNumber.
  ///
  /// In en, this message translates to:
  /// **'Add their mobile number too, or clear their name.'**
  String get regEmergencyNeedsNumber;

  /// No description provided for @regEmergencyNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Add their name too, or clear the number.'**
  String get regEmergencyNeedsName;

  /// No description provided for @regEmergencySameAsYours.
  ///
  /// In en, this message translates to:
  /// **'That is your own number. Enter the number of someone else — the person we should call about you.'**
  String get regEmergencySameAsYours;

  /// No description provided for @emergencyWhoShort.
  ///
  /// In en, this message translates to:
  /// **'The person we should call if something happens to YOU — a family member, a friend or someone you trust. Enter THEIR name and number, not your own.'**
  String get emergencyWhoShort;

  /// No description provided for @hintPwdId.
  ///
  /// In en, this message translates to:
  /// **'PWD ID number'**
  String get hintPwdId;

  /// No description provided for @pwdIdHelp.
  ///
  /// In en, this message translates to:
  /// **'Issued by your MSWDO or PDAO - also proves residency'**
  String get pwdIdHelp;

  /// No description provided for @hintAccessibilityNotes.
  ///
  /// In en, this message translates to:
  /// **'Anything else that would help (optional)'**
  String get hintAccessibilityNotes;

  /// No description provided for @contactModeAny.
  ///
  /// In en, this message translates to:
  /// **'Any way'**
  String get contactModeAny;

  /// No description provided for @contactModeSms.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get contactModeSms;

  /// No description provided for @contactModeApp.
  ///
  /// In en, this message translates to:
  /// **'In-app only'**
  String get contactModeApp;

  /// No description provided for @contactModeVoice.
  ///
  /// In en, this message translates to:
  /// **'Calling is fine'**
  String get contactModeVoice;

  /// No description provided for @regIsPwd.
  ///
  /// In en, this message translates to:
  /// **'I am a person with disability'**
  String get regIsPwd;

  /// No description provided for @regAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get regAccessibility;

  /// No description provided for @regAccessibilityWhy.
  ///
  /// In en, this message translates to:
  /// **'So a crew arrives prepared. Optional.'**
  String get regAccessibilityWhy;

  /// No description provided for @regAccessibilityAsk.
  ///
  /// In en, this message translates to:
  /// **'What should a crew know before they arrive?'**
  String get regAccessibilityAsk;

  /// No description provided for @regContactModeAsk.
  ///
  /// In en, this message translates to:
  /// **'How should we contact you?'**
  String get regContactModeAsk;

  /// No description provided for @regAgencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your agency'**
  String get regAgencyTitle;

  /// No description provided for @regAgencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your Agency Admin checks these before approving you.'**
  String get regAgencySubtitle;

  /// No description provided for @fieldAgency.
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get fieldAgency;

  /// No description provided for @fieldBadgeId.
  ///
  /// In en, this message translates to:
  /// **'Badge or employee ID'**
  String get fieldBadgeId;

  /// No description provided for @hintBadgeId.
  ///
  /// In en, this message translates to:
  /// **'As issued by your agency'**
  String get hintBadgeId;

  /// No description provided for @fieldRank.
  ///
  /// In en, this message translates to:
  /// **'Rank or position'**
  String get fieldRank;

  /// No description provided for @hintRank.
  ///
  /// In en, this message translates to:
  /// **'SFO1, PCpl, Rescue Team Leader'**
  String get hintRank;

  /// No description provided for @fieldUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit or station'**
  String get fieldUnit;

  /// No description provided for @hintUnit.
  ///
  /// In en, this message translates to:
  /// **'Naval Fire Station'**
  String get hintUnit;

  /// No description provided for @fieldDateJoined.
  ///
  /// In en, this message translates to:
  /// **'Date you joined'**
  String get fieldDateJoined;

  /// No description provided for @fieldAgencyIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo of your agency ID'**
  String get fieldAgencyIdPhoto;

  /// No description provided for @regTakeAgencyIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your agency ID'**
  String get regTakeAgencyIdPhoto;

  /// No description provided for @regChooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get regChooseDate;

  /// No description provided for @regAgencyIdWhy.
  ///
  /// In en, this message translates to:
  /// **'Speeds up approval considerably - your admin can check the badge number without calling your station.'**
  String get regAgencyIdWhy;

  /// No description provided for @regIdBestChoice.
  ///
  /// In en, this message translates to:
  /// **'Best choice'**
  String get regIdBestChoice;

  /// No description provided for @regIdProvesResidency.
  ///
  /// In en, this message translates to:
  /// **'Also proves you live in Biliran'**
  String get regIdProvesResidency;

  /// No description provided for @regIdAlsoAccepted.
  ///
  /// In en, this message translates to:
  /// **'Also accepted'**
  String get regIdAlsoAccepted;

  /// No description provided for @regIdIdentityOnly.
  ///
  /// In en, this message translates to:
  /// **'Proves who you are, but not where you live'**
  String get regIdIdentityOnly;

  /// No description provided for @actionChooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get actionChooseFromGallery;

  /// No description provided for @regIdCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Photograph your ID'**
  String get regIdCaptureTitle;

  /// No description provided for @fieldIdNumber.
  ///
  /// In en, this message translates to:
  /// **'ID number'**
  String get fieldIdNumber;

  /// No description provided for @hintIdNumber.
  ///
  /// In en, this message translates to:
  /// **'As printed on the card'**
  String get hintIdNumber;

  /// No description provided for @regReadingId.
  ///
  /// In en, this message translates to:
  /// **'Reading your ID...'**
  String get regReadingId;

  /// No description provided for @regOcrFilled.
  ///
  /// In en, this message translates to:
  /// **'Filled in from your photo - correct it if it is wrong'**
  String get regOcrFilled;

  /// No description provided for @regIdPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'This photo is private. It is never shown publicly, never seen by responders, and is deleted once an administrator has checked it.'**
  String get regIdPrivacyNote;

  /// No description provided for @regIdUnreadable.
  ///
  /// In en, this message translates to:
  /// **'We could not read much from that photo. You can still continue - just type the number below. A clearer photo helps the reviewer.'**
  String get regIdUnreadable;

  /// No description provided for @actionRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get actionRetake;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionTakePhotoShort.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get actionTakePhotoShort;

  /// No description provided for @selfieFramingNone.
  ///
  /// In en, this message translates to:
  /// **'Put your face inside the circle'**
  String get selfieFramingNone;

  /// No description provided for @selfieFramingMultiple.
  ///
  /// In en, this message translates to:
  /// **'Only one face, please'**
  String get selfieFramingMultiple;

  /// No description provided for @selfieFramingTooFar.
  ///
  /// In en, this message translates to:
  /// **'Move a little closer'**
  String get selfieFramingTooFar;

  /// No description provided for @selfieFramingTooClose.
  ///
  /// In en, this message translates to:
  /// **'Move a little further back'**
  String get selfieFramingTooClose;

  /// No description provided for @selfieFramingOffCentre.
  ///
  /// In en, this message translates to:
  /// **'Centre your face'**
  String get selfieFramingOffCentre;

  /// No description provided for @selfieAutoCapture.
  ///
  /// In en, this message translates to:
  /// **'We take the photo automatically once you do.'**
  String get selfieAutoCapture;

  /// No description provided for @selfieOrManual.
  ///
  /// In en, this message translates to:
  /// **'Or take the photo yourself.'**
  String get selfieOrManual;

  /// No description provided for @selfieTitle.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie'**
  String get selfieTitle;

  /// No description provided for @selfieReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'How does this look?'**
  String get selfieReviewTitle;

  /// No description provided for @selfieSubtitle.
  ///
  /// In en, this message translates to:
  /// **'So an administrator can match your face to your ID.'**
  String get selfieSubtitle;

  /// No description provided for @selfieReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure your face is clear and well lit.'**
  String get selfieReviewSubtitle;

  /// No description provided for @selfieCameraError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the camera. Check that Ziren has camera permission in your phone settings.'**
  String get selfieCameraError;

  /// No description provided for @selfieCaptureError.
  ///
  /// In en, this message translates to:
  /// **'Could not take the photo. Please try again.'**
  String get selfieCaptureError;

  /// No description provided for @regReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your details'**
  String get regReviewTitle;

  /// No description provided for @regReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap anything to change it.'**
  String get regReviewSubtitle;

  /// No description provided for @regGroupAboutYou.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get regGroupAboutYou;

  /// No description provided for @regGroupAddress.
  ///
  /// In en, this message translates to:
  /// **'Where you live'**
  String get regGroupAddress;

  /// No description provided for @regGroupContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get regGroupContact;

  /// No description provided for @regGroupAgency.
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get regGroupAgency;

  /// No description provided for @regGroupIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get regGroupIdentity;

  /// No description provided for @actionChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get actionChange;

  /// No description provided for @regReenterPassword.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get regReenterPassword;

  /// No description provided for @hintYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Your password'**
  String get hintYourPassword;

  /// No description provided for @regVerifyNowInstead.
  ///
  /// In en, this message translates to:
  /// **'Verify now instead'**
  String get regVerifyNowInstead;

  /// No description provided for @regVerificationSkipped.
  ///
  /// In en, this message translates to:
  /// **'Verification skipped'**
  String get regVerificationSkipped;

  /// No description provided for @valueNotGiven.
  ///
  /// In en, this message translates to:
  /// **'Not given'**
  String get valueNotGiven;

  /// No description provided for @valueAttached.
  ///
  /// In en, this message translates to:
  /// **'Attached'**
  String get valueAttached;

  /// No description provided for @labelName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelName;

  /// No description provided for @labelDateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get labelDateOfBirth;

  /// No description provided for @labelSex.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get labelSex;

  /// No description provided for @labelMunicipality.
  ///
  /// In en, this message translates to:
  /// **'Municipality'**
  String get labelMunicipality;

  /// No description provided for @labelBarangay.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get labelBarangay;

  /// No description provided for @labelPurok.
  ///
  /// In en, this message translates to:
  /// **'Purok or sitio'**
  String get labelPurok;

  /// No description provided for @labelStreet.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get labelStreet;

  /// No description provided for @labelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get labelEmail;

  /// No description provided for @labelMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get labelMobile;

  /// No description provided for @labelEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get labelEmergencyContact;

  /// No description provided for @labelAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get labelAccessibility;

  /// No description provided for @labelBadgeId.
  ///
  /// In en, this message translates to:
  /// **'Badge ID'**
  String get labelBadgeId;

  /// No description provided for @labelRank.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get labelRank;

  /// No description provided for @labelUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get labelUnit;

  /// No description provided for @labelAgencyIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Agency ID photo'**
  String get labelAgencyIdPhoto;

  /// No description provided for @labelIdType.
  ///
  /// In en, this message translates to:
  /// **'ID type'**
  String get labelIdType;

  /// No description provided for @labelIdNumber.
  ///
  /// In en, this message translates to:
  /// **'ID number'**
  String get labelIdNumber;

  /// No description provided for @labelIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'ID photo'**
  String get labelIdPhoto;

  /// No description provided for @regSelfieAttached.
  ///
  /// In en, this message translates to:
  /// **'Selfie attached for identity checking.'**
  String get regSelfieAttached;

  /// No description provided for @regSkippedNotice.
  ///
  /// In en, this message translates to:
  /// **'Your account will work straight away and you can report emergencies. Finish verification later from your profile.'**
  String get regSkippedNotice;

  /// No description provided for @regSkipDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip verification for now?'**
  String get regSkipDialogTitle;

  /// No description provided for @actionGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get actionGoBack;

  /// No description provided for @actionSkipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get actionSkipForNow;

  /// No description provided for @regSkipDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Your account will be created and you can report emergencies straight away.\n\nA dispatcher will see that your identity has not been checked yet. You can finish this any time from your profile.'**
  String get regSkipDialogBody;

  /// No description provided for @regSkipLink.
  ///
  /// In en, this message translates to:
  /// **'I need help right now - skip this'**
  String get regSkipLink;

  /// No description provided for @profilePersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get profilePersonalInfo;

  /// No description provided for @labelNameProfile.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelNameProfile;

  /// No description provided for @labelEmailProfile.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get labelEmailProfile;

  /// No description provided for @labelPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get labelPhone;

  /// No description provided for @profileAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get profileAddress;

  /// No description provided for @labelBarangayProfile.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get labelBarangayProfile;

  /// No description provided for @labelMunicipalityProfile.
  ///
  /// In en, this message translates to:
  /// **'Municipality'**
  String get labelMunicipalityProfile;

  /// No description provided for @profileAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccount;

  /// No description provided for @labelRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get labelRole;

  /// No description provided for @labelStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get labelStatus;

  /// No description provided for @profileEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact'**
  String get profileEmergencyContact;

  /// No description provided for @labelNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get labelNumber;

  /// No description provided for @profileNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileNotSet;

  /// No description provided for @labelEmergencyContactName.
  ///
  /// In en, this message translates to:
  /// **'Contact name'**
  String get labelEmergencyContactName;

  /// No description provided for @labelEmergencyContactNumber.
  ///
  /// In en, this message translates to:
  /// **'Contact number'**
  String get labelEmergencyContactNumber;

  /// No description provided for @profileAccountVerified.
  ///
  /// In en, this message translates to:
  /// **'Account verified'**
  String get profileAccountVerified;

  /// No description provided for @profileAccountVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Your identity is confirmed. You get priority support during emergencies.'**
  String get profileAccountVerifiedBody;

  /// No description provided for @profileVerifyLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get profileVerifyLearnMore;

  /// No description provided for @profileStaleWarning.
  ///
  /// In en, this message translates to:
  /// **'Details below may be out of date.'**
  String profileStaleWarning(String message);

  /// No description provided for @actionRetryProfile.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetryProfile;

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfile;

  /// No description provided for @fieldFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fieldFullName;

  /// No description provided for @fieldMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get fieldMobileNumber;

  /// No description provided for @hintMobileShort.
  ///
  /// In en, this message translates to:
  /// **'09xxxxxxxxx'**
  String get hintMobileShort;

  /// No description provided for @settingsAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get settingsAddress;

  /// No description provided for @fieldBarangaySettings.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get fieldBarangaySettings;

  /// No description provided for @hintBarangayExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Brgy. Caraycaray'**
  String get hintBarangayExample;

  /// No description provided for @fieldMunicipalitySettings.
  ///
  /// In en, this message translates to:
  /// **'Municipality'**
  String get fieldMunicipalitySettings;

  /// No description provided for @hintMunicipalityExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Naval'**
  String get hintMunicipalityExample;

  /// No description provided for @settingsPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferences;

  /// No description provided for @settingsEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact'**
  String get settingsEmergencyContact;

  /// No description provided for @fieldContactName.
  ///
  /// In en, this message translates to:
  /// **'Contact person\'s name'**
  String get fieldContactName;

  /// No description provided for @hintContactName.
  ///
  /// In en, this message translates to:
  /// **'Their full name, e.g. Maria Santos'**
  String get hintContactName;

  /// No description provided for @fieldContactNumber.
  ///
  /// In en, this message translates to:
  /// **'Contact person\'s number'**
  String get fieldContactNumber;

  /// No description provided for @verifyWhichId.
  ///
  /// In en, this message translates to:
  /// **'Which ID will you show?'**
  String get verifyWhichId;

  /// No description provided for @verifyIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo of the ID'**
  String get verifyIdPhoto;

  /// No description provided for @verifyIdNumber.
  ///
  /// In en, this message translates to:
  /// **'ID number'**
  String get verifyIdNumber;

  /// No description provided for @verifySelfie.
  ///
  /// In en, this message translates to:
  /// **'Selfie (optional but helps)'**
  String get verifySelfie;

  /// No description provided for @verifySubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get verifySubmit;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your account'**
  String get verifyTitle;

  /// No description provided for @verifyChooseId.
  ///
  /// In en, this message translates to:
  /// **'Choose an ID'**
  String get verifyChooseId;

  /// No description provided for @verifyTakeIdPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your ID'**
  String get verifyTakeIdPhoto;

  /// No description provided for @verifyTakeSelfie.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie'**
  String get verifyTakeSelfie;

  /// No description provided for @verifySentTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent for review'**
  String get verifySentTitle;

  /// No description provided for @verifyNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'You are not signed in.'**
  String get verifyNotSignedIn;

  /// No description provided for @verifyIntro.
  ///
  /// In en, this message translates to:
  /// **'This is optional. You can already report emergencies without it - verifying just tells a dispatcher your reports come from a confirmed resident.'**
  String get verifyIntro;

  /// No description provided for @verifySentBody.
  ///
  /// In en, this message translates to:
  /// **'An administrator will check your ID. Nothing changes for you in the meantime - keep using Ziren exactly as before.'**
  String get verifySentBody;

  /// No description provided for @verifyPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your photos are private, never shown to responders, and deleted once an administrator has checked them.'**
  String get verifyPrivacyNote;

  /// No description provided for @bannerInReview.
  ///
  /// In en, this message translates to:
  /// **'Verification in review'**
  String get bannerInReview;

  /// No description provided for @bannerFinishVerifying.
  ///
  /// In en, this message translates to:
  /// **'Finish verifying your account'**
  String get bannerFinishVerifying;

  /// No description provided for @bannerVerifyNow.
  ///
  /// In en, this message translates to:
  /// **'Verify now'**
  String get bannerVerifyNow;

  /// No description provided for @bannerNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get bannerNotNow;

  /// No description provided for @bannerInReviewBody.
  ///
  /// In en, this message translates to:
  /// **'An administrator is checking your ID. You can keep using Ziren normally in the meantime.'**
  String get bannerInReviewBody;

  /// No description provided for @bannerFinishBody.
  ///
  /// In en, this message translates to:
  /// **'Add a valid ID so a dispatcher knows your reports come from a real resident. You can report emergencies either way.'**
  String get bannerFinishBody;

  /// No description provided for @badgeRequired.
  ///
  /// In en, this message translates to:
  /// **'REQUIRED'**
  String get badgeRequired;

  /// No description provided for @badgeOptional.
  ///
  /// In en, this message translates to:
  /// **'OPTIONAL'**
  String get badgeOptional;

  /// No description provided for @badgeAuto.
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get badgeAuto;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report an Emergency'**
  String get reportTitle;

  /// No description provided for @reportSectionWhat.
  ///
  /// In en, this message translates to:
  /// **'WHAT - Type of Emergency'**
  String get reportSectionWhat;

  /// No description provided for @reportExtraDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get reportExtraDetails;

  /// No description provided for @reportSectionHow.
  ///
  /// In en, this message translates to:
  /// **'HOW - Details'**
  String get reportSectionHow;

  /// No description provided for @reportOverlapQuestion.
  ///
  /// In en, this message translates to:
  /// **'Anything else to worry about?'**
  String get reportOverlapQuestion;

  /// No description provided for @reportSelectAllApply.
  ///
  /// In en, this message translates to:
  /// **'Select all that apply'**
  String get reportSelectAllApply;

  /// No description provided for @reportLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get reportLocation;

  /// No description provided for @reportNoGps.
  ///
  /// In en, this message translates to:
  /// **'No GPS - it can still be sent without it'**
  String get reportNoGps;

  /// No description provided for @reportFindingLocation.
  ///
  /// In en, this message translates to:
  /// **'Finding your location...'**
  String get reportFindingLocation;

  /// No description provided for @reportGpsAcquired.
  ///
  /// In en, this message translates to:
  /// **'GPS acquired'**
  String get reportGpsAcquired;

  /// No description provided for @reportFindingAddress.
  ///
  /// In en, this message translates to:
  /// **'Finding the address...'**
  String get reportFindingAddress;

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review your report'**
  String get reviewTitle;

  /// No description provided for @reviewTypeOfEmergency.
  ///
  /// In en, this message translates to:
  /// **'TYPE OF EMERGENCY'**
  String get reviewTypeOfEmergency;

  /// No description provided for @reviewDetails.
  ///
  /// In en, this message translates to:
  /// **'DETAILS'**
  String get reviewDetails;

  /// No description provided for @reviewAlsoInvolved.
  ///
  /// In en, this message translates to:
  /// **'ALSO INVOLVED'**
  String get reviewAlsoInvolved;

  /// No description provided for @reviewLocation.
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get reviewLocation;

  /// No description provided for @reviewRelationship.
  ///
  /// In en, this message translates to:
  /// **'RELATIONSHIP TO THE VICTIM'**
  String get reviewRelationship;

  /// No description provided for @reviewExtraDetails.
  ///
  /// In en, this message translates to:
  /// **'MORE DETAILS'**
  String get reviewExtraDetails;

  /// No description provided for @reviewNoGps.
  ///
  /// In en, this message translates to:
  /// **'GPS not available'**
  String get reviewNoGps;

  /// No description provided for @reviewFalseReportWarning.
  ///
  /// In en, this message translates to:
  /// **'Filing a false report carries legal penalties. Make sure all the information is correct.'**
  String get reviewFalseReportWarning;

  /// No description provided for @reviewSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get reviewSubmit;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @reviewTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get reviewTakePhoto;

  /// No description provided for @quickIncident.
  ///
  /// In en, this message translates to:
  /// **'Incident'**
  String get quickIncident;

  /// No description provided for @quickReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get quickReport;

  /// No description provided for @quickYourLocation.
  ///
  /// In en, this message translates to:
  /// **'Your location'**
  String get quickYourLocation;

  /// Confirmation snackbar after a one-tap report is accepted.
  ///
  /// In en, this message translates to:
  /// **'Report sent to {station}.'**
  String quickSentTo(String station);

  /// Shown under the captured coordinates when the fix is tight.
  ///
  /// In en, this message translates to:
  /// **'GPS is accurate (±{meters} m)'**
  String quickGpsPrecise(int meters);

  /// Shown when the fix is loose. Says so plainly rather than presenting a weak fix as fact.
  ///
  /// In en, this message translates to:
  /// **'GPS is imprecise (±{meters} m) — this may not be exactly where you are.'**
  String quickGpsVague(int meters);

  /// Placeholder for the optional free-text note.
  ///
  /// In en, this message translates to:
  /// **'e.g. someone is trapped inside'**
  String get quickNoteHint;

  /// Primary button on the one-tap report confirm screen.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get quickSendReport;

  /// Note under the send button.
  ///
  /// In en, this message translates to:
  /// **'This sends a real call-out to the station. A false report carries a penalty.'**
  String get quickSendWarning;

  /// No description provided for @quickLocationOff.
  ///
  /// In en, this message translates to:
  /// **'Location is off. The report will still be sent, but a dispatcher will have to ask where you are.'**
  String get quickLocationOff;

  /// No description provided for @quickSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get quickSearching;

  /// No description provided for @quickCoordinatesFound.
  ///
  /// In en, this message translates to:
  /// **'Coordinates acquired'**
  String get quickCoordinatesFound;

  /// No description provided for @quickReceivingStation.
  ///
  /// In en, this message translates to:
  /// **'Receiving station'**
  String get quickReceivingStation;

  /// No description provided for @quickLoadingStations.
  ///
  /// In en, this message translates to:
  /// **'Loading the list...'**
  String get quickLoadingStations;

  /// No description provided for @quickStationUnknown.
  ///
  /// In en, this message translates to:
  /// **'Cannot be determined yet - your location is needed.'**
  String get quickStationUnknown;

  /// Receiving-agency line on the quick-report review when the phone has a GPS fix but no station list (e.g. that one call has not loaded yet). The report is still sendable: the server picks the nearest station itself from coordinates.
  ///
  /// In en, this message translates to:
  /// **'Assigned automatically from your location'**
  String get quickStationAuto;

  /// No description provided for @quickLandmark.
  ///
  /// In en, this message translates to:
  /// **'Landmark (optional)'**
  String get quickLandmark;

  /// No description provided for @quickLandmarkHelp.
  ///
  /// In en, this message translates to:
  /// **'What is next to it or nearby? This is what a responder will look for.'**
  String get quickLandmarkHelp;

  /// No description provided for @quickLandmarkHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. next to the barangay hall'**
  String get quickLandmarkHint;

  /// report_text sent when the resident recorded a voice note but typed no message. Must stay well over 10 characters for every category — the backend rejects report_text under 10 chars, and the transcript this refers to isn't available until after submission.
  ///
  /// In en, this message translates to:
  /// **'{category} — reported by voice recording'**
  String quickVoiceOnlyReportText(String category);

  /// report_text sent when the resident typed no message AND recorded no voice note — category selection alone. Must stay well over 10 characters for every category.
  ///
  /// In en, this message translates to:
  /// **'{category} — no additional details provided'**
  String quickNoDetailsReportText(String category);

  /// AppBar title on the quick-report confirm screen.
  ///
  /// In en, this message translates to:
  /// **'Report a {category}'**
  String quickFlowTitle(String category);

  /// No description provided for @quickHelpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help us get the right team to the right place.'**
  String get quickHelpSubtitle;

  /// No description provided for @quickYourLocationAuto.
  ///
  /// In en, this message translates to:
  /// **'Your location (auto-detected)'**
  String get quickYourLocationAuto;

  /// GPS accuracy line under the detected address.
  ///
  /// In en, this message translates to:
  /// **'Accuracy: ±{meters} m'**
  String quickAccuracy(int meters);

  /// No description provided for @quickDescribeWhatHappened.
  ///
  /// In en, this message translates to:
  /// **'Describe what happened'**
  String get quickDescribeWhatHappened;

  /// No description provided for @quickOrTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Or type your message (optional)'**
  String get quickOrTypeMessage;

  /// No description provided for @quickAttachPhotoVideo.
  ///
  /// In en, this message translates to:
  /// **'Attach photo or video (optional)'**
  String get quickAttachPhotoVideo;

  /// No description provided for @quickMediaHint.
  ///
  /// In en, this message translates to:
  /// **'Add photos or videos as evidence (max 5, 50MB each)'**
  String get quickMediaHint;

  /// No description provided for @quickTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get quickTakePhoto;

  /// No description provided for @quickRecordVideo.
  ///
  /// In en, this message translates to:
  /// **'Record a video'**
  String get quickRecordVideo;

  /// No description provided for @quickChooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get quickChooseFromGallery;

  /// No description provided for @quickAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo or video'**
  String get quickAddPhoto;

  /// No description provided for @quickReviewReportAction.
  ///
  /// In en, this message translates to:
  /// **'Review report'**
  String get quickReviewReportAction;

  /// No description provided for @quickReviewWarning.
  ///
  /// In en, this message translates to:
  /// **'By sending this, you are creating a real emergency report. Please be serious and accurate.'**
  String get quickReviewWarning;

  /// No description provided for @quickReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review report'**
  String get quickReviewTitle;

  /// No description provided for @quickReviewCareful.
  ///
  /// In en, this message translates to:
  /// **'Please review your report carefully.'**
  String get quickReviewCareful;

  /// Sub-line under the careful-review banner.
  ///
  /// In en, this message translates to:
  /// **'This will be sent to the nearest {agency} station.'**
  String quickReviewWillSendTo(String agency);

  /// No description provided for @quickReviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get quickReviewDescription;

  /// No description provided for @quickReviewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get quickReviewPhoto;

  /// Photo/video count line on the review screen.
  ///
  /// In en, this message translates to:
  /// **'{count} attached'**
  String quickReviewAttachedCount(int count);

  /// No description provided for @quickReviewReceivingAgency.
  ///
  /// In en, this message translates to:
  /// **'Receiving agency'**
  String get quickReviewReceivingAgency;

  /// Distance to the receiving station on the review screen.
  ///
  /// In en, this message translates to:
  /// **'{km} km away'**
  String quickReviewAway(String km);

  /// No description provided for @quickReviewVoiceRecording.
  ///
  /// In en, this message translates to:
  /// **'Voice recording'**
  String get quickReviewVoiceRecording;

  /// No description provided for @quickReviewAttached.
  ///
  /// In en, this message translates to:
  /// **'Attached'**
  String get quickReviewAttached;

  /// No description provided for @categoryQuestion.
  ///
  /// In en, this message translates to:
  /// **'What kind of emergency?'**
  String get categoryQuestion;

  /// No description provided for @categoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the closest category'**
  String get categoryHelp;

  /// No description provided for @whoTitle.
  ///
  /// In en, this message translates to:
  /// **'Who and where?'**
  String get whoTitle;

  /// No description provided for @whoRelationship.
  ///
  /// In en, this message translates to:
  /// **'What is your relationship to the victim?'**
  String get whoRelationship;

  /// No description provided for @whoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get whoLocation;

  /// No description provided for @whoLandmark.
  ///
  /// In en, this message translates to:
  /// **'Landmark or nearby marker (optional)'**
  String get whoLandmark;

  /// No description provided for @whoLandmarkHint.
  ///
  /// In en, this message translates to:
  /// **'For example: near the church, beside the market...'**
  String get whoLandmarkHint;

  /// No description provided for @overlapTitle.
  ///
  /// In en, this message translates to:
  /// **'Anything else involved...'**
  String get overlapTitle;

  /// No description provided for @overlapHelp.
  ///
  /// In en, this message translates to:
  /// **'Select all that apply - this helps alert the right agency.'**
  String get overlapHelp;

  /// No description provided for @stationPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a Station'**
  String get stationPickTitle;

  /// No description provided for @actionTryAgainStation.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgainStation;

  /// No description provided for @stationNoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No stations available.'**
  String get stationNoneAvailable;

  /// No description provided for @stationPickHelp.
  ///
  /// In en, this message translates to:
  /// **'Tap the station that should receive your report.'**
  String get stationPickHelp;

  /// No description provided for @qFireMaterial.
  ///
  /// In en, this message translates to:
  /// **'What is burning?'**
  String get qFireMaterial;

  /// No description provided for @qFireSpreading.
  ///
  /// In en, this message translates to:
  /// **'Is it still spreading?'**
  String get qFireSpreading;

  /// No description provided for @qFireInjured.
  ///
  /// In en, this message translates to:
  /// **'Anyone hurt or trapped?'**
  String get qFireInjured;

  /// No description provided for @qFireRoadBlocked.
  ///
  /// In en, this message translates to:
  /// **'Is the fire blocking the road?'**
  String get qFireRoadBlocked;

  /// No description provided for @qMedType.
  ///
  /// In en, this message translates to:
  /// **'Type of emergency?'**
  String get qMedType;

  /// No description provided for @qMedVictimCount.
  ///
  /// In en, this message translates to:
  /// **'How many victims?'**
  String get qMedVictimCount;

  /// No description provided for @qMedBleeding.
  ///
  /// In en, this message translates to:
  /// **'Bleeding or serious wounds?'**
  String get qMedBleeding;

  /// No description provided for @qMedConscious.
  ///
  /// In en, this message translates to:
  /// **'Is the victim conscious?'**
  String get qMedConscious;

  /// No description provided for @qVehType.
  ///
  /// In en, this message translates to:
  /// **'What vehicle?'**
  String get qVehType;

  /// No description provided for @qVehInjured.
  ///
  /// In en, this message translates to:
  /// **'Anyone hurt?'**
  String get qVehInjured;

  /// No description provided for @qVehRoadBlocked.
  ///
  /// In en, this message translates to:
  /// **'Is the road blocked?'**
  String get qVehRoadBlocked;

  /// No description provided for @qCalType.
  ///
  /// In en, this message translates to:
  /// **'Type of calamity?'**
  String get qCalType;

  /// No description provided for @qCalAffected.
  ///
  /// In en, this message translates to:
  /// **'How many families affected?'**
  String get qCalAffected;

  /// No description provided for @qCalRoadCut.
  ///
  /// In en, this message translates to:
  /// **'Is the road cut off?'**
  String get qCalRoadCut;

  /// No description provided for @qCalEvacuation.
  ///
  /// In en, this message translates to:
  /// **'Is evacuation needed?'**
  String get qCalEvacuation;

  /// No description provided for @qCrimeType.
  ///
  /// In en, this message translates to:
  /// **'Type of incident?'**
  String get qCrimeType;

  /// No description provided for @qCrimeWeapon.
  ///
  /// In en, this message translates to:
  /// **'Any weapons?'**
  String get qCrimeWeapon;

  /// No description provided for @qCrimeOngoing.
  ///
  /// In en, this message translates to:
  /// **'Is it still happening now?'**
  String get qCrimeOngoing;

  /// No description provided for @ansYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get ansYes;

  /// No description provided for @ansNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get ansNo;

  /// No description provided for @ansNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get ansNone;

  /// No description provided for @ansDontKnow.
  ///
  /// In en, this message translates to:
  /// **'I do not know'**
  String get ansDontKnow;

  /// No description provided for @ansOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get ansOther;

  /// No description provided for @ansHouse.
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get ansHouse;

  /// No description provided for @ansVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get ansVehicle;

  /// No description provided for @ansForestField.
  ///
  /// In en, this message translates to:
  /// **'Forest / Field'**
  String get ansForestField;

  /// No description provided for @ansBuildingWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Building / Warehouse'**
  String get ansBuildingWarehouse;

  /// No description provided for @ansYesSpreading.
  ///
  /// In en, this message translates to:
  /// **'Yes, spreading'**
  String get ansYesSpreading;

  /// No description provided for @ansNoControlled.
  ///
  /// In en, this message translates to:
  /// **'No, under control'**
  String get ansNoControlled;

  /// No description provided for @ansAccident.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get ansAccident;

  /// No description provided for @ansHeartAttackStroke.
  ///
  /// In en, this message translates to:
  /// **'Heart attack / Stroke'**
  String get ansHeartAttackStroke;

  /// No description provided for @ansSeizure.
  ///
  /// In en, this message translates to:
  /// **'Seizure'**
  String get ansSeizure;

  /// No description provided for @ansTroubleBreathing.
  ///
  /// In en, this message translates to:
  /// **'Trouble breathing'**
  String get ansTroubleBreathing;

  /// No description provided for @ansOne.
  ///
  /// In en, this message translates to:
  /// **'1'**
  String get ansOne;

  /// No description provided for @ansTwoToFive.
  ///
  /// In en, this message translates to:
  /// **'2-5'**
  String get ansTwoToFive;

  /// No description provided for @ansMoreThanFive.
  ///
  /// In en, this message translates to:
  /// **'More than 5'**
  String get ansMoreThanFive;

  /// No description provided for @ansYesConscious.
  ///
  /// In en, this message translates to:
  /// **'Yes, conscious'**
  String get ansYesConscious;

  /// No description provided for @ansNoUnconscious.
  ///
  /// In en, this message translates to:
  /// **'No, unconscious'**
  String get ansNoUnconscious;

  /// No description provided for @ansMotorcycle.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get ansMotorcycle;

  /// No description provided for @ansCarSuv.
  ///
  /// In en, this message translates to:
  /// **'Car / SUV'**
  String get ansCarSuv;

  /// No description provided for @ansBusTruck.
  ///
  /// In en, this message translates to:
  /// **'Bus / Truck'**
  String get ansBusTruck;

  /// No description provided for @ansTricycleEbike.
  ///
  /// In en, this message translates to:
  /// **'Tricycle / E-bike'**
  String get ansTricycleEbike;

  /// No description provided for @ansYesBlocked.
  ///
  /// In en, this message translates to:
  /// **'Yes, blocked'**
  String get ansYesBlocked;

  /// No description provided for @ansPartly.
  ///
  /// In en, this message translates to:
  /// **'Partly'**
  String get ansPartly;

  /// No description provided for @ansFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get ansFlood;

  /// No description provided for @ansLandslide.
  ///
  /// In en, this message translates to:
  /// **'Landslide'**
  String get ansLandslide;

  /// No description provided for @ansStorm.
  ///
  /// In en, this message translates to:
  /// **'Storm'**
  String get ansStorm;

  /// No description provided for @ansEarthquake.
  ///
  /// In en, this message translates to:
  /// **'Earthquake'**
  String get ansEarthquake;

  /// No description provided for @ansOneToFive.
  ///
  /// In en, this message translates to:
  /// **'1-5'**
  String get ansOneToFive;

  /// No description provided for @ansSixToTwenty.
  ///
  /// In en, this message translates to:
  /// **'6-20'**
  String get ansSixToTwenty;

  /// No description provided for @ansMoreThanTwenty.
  ///
  /// In en, this message translates to:
  /// **'More than 20'**
  String get ansMoreThanTwenty;

  /// No description provided for @ansYesUrgent.
  ///
  /// In en, this message translates to:
  /// **'Yes, urgent'**
  String get ansYesUrgent;

  /// No description provided for @ansPossibly.
  ///
  /// In en, this message translates to:
  /// **'Possibly'**
  String get ansPossibly;

  /// No description provided for @ansNotYetNeeded.
  ///
  /// In en, this message translates to:
  /// **'Not needed yet'**
  String get ansNotYetNeeded;

  /// No description provided for @ansFightDisturbance.
  ///
  /// In en, this message translates to:
  /// **'Fight / Disturbance'**
  String get ansFightDisturbance;

  /// No description provided for @ansTheftHoldup.
  ///
  /// In en, this message translates to:
  /// **'Theft / Hold-up'**
  String get ansTheftHoldup;

  /// No description provided for @ansPhysicalAssault.
  ///
  /// In en, this message translates to:
  /// **'Physical assault'**
  String get ansPhysicalAssault;

  /// No description provided for @ansArmed.
  ///
  /// In en, this message translates to:
  /// **'Weapon involved'**
  String get ansArmed;

  /// No description provided for @ansYesOngoing.
  ///
  /// In en, this message translates to:
  /// **'Yes, still happening'**
  String get ansYesOngoing;

  /// No description provided for @ansItIsOver.
  ///
  /// In en, this message translates to:
  /// **'It is over'**
  String get ansItIsOver;

  /// No description provided for @qExtraDetails.
  ///
  /// In en, this message translates to:
  /// **'More details (optional)'**
  String get qExtraDetails;

  /// No description provided for @sosAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS - Emergency Report'**
  String get sosAppBarTitle;

  /// No description provided for @sosHeading.
  ///
  /// In en, this message translates to:
  /// **'Emergency SOS'**
  String get sosHeading;

  /// No description provided for @sosIntro.
  ///
  /// In en, this message translates to:
  /// **'Your identity and location will be sent to the nearest emergency station.'**
  String get sosIntro;

  /// No description provided for @sosLocating.
  ///
  /// In en, this message translates to:
  /// **'Determining your location...'**
  String get sosLocating;

  /// No description provided for @sosStationAuto.
  ///
  /// In en, this message translates to:
  /// **'Nearest station will be identified automatically.'**
  String get sosStationAuto;

  /// No description provided for @sosLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable'**
  String get sosLocationUnavailable;

  /// No description provided for @sosNoGpsBody.
  ///
  /// In en, this message translates to:
  /// **'Your SOS will be sent without GPS. The server will route to the nearest Naval station.'**
  String get sosNoGpsBody;

  /// No description provided for @sosLocationCaptured.
  ///
  /// In en, this message translates to:
  /// **'Location captured'**
  String get sosLocationCaptured;

  /// No description provided for @sosBriefDescription.
  ///
  /// In en, this message translates to:
  /// **'Brief description (optional)'**
  String get sosBriefDescription;

  /// No description provided for @sosLegalWarning.
  ///
  /// In en, this message translates to:
  /// **'Legal Warning'**
  String get sosLegalWarning;

  /// The legal warning itself. Sat under the localised heading in English only until now, so a Filipino-locale resident read a consequence notice in a second language.
  ///
  /// In en, this message translates to:
  /// **'Submitting a false emergency report is a punishable offense under Philippine law (RA 10175, local ordinances). Your full identity and location are permanently attached to this report. Repeated false reports will result in suspension of your SOS access and referral to local authorities.'**
  String get sosLegalBody;

  /// Checkbox the resident must tick before the SOS button enables.
  ///
  /// In en, this message translates to:
  /// **'I understand this is a real emergency and confirm my report is truthful.'**
  String get sosTruthConfirm;

  /// Primary button on the SOS confirm screen.
  ///
  /// In en, this message translates to:
  /// **'Send SOS Now'**
  String get sosSendNow;

  /// Shown while the client-side SOS cooldown is active. Pluralised properly — the previous copy said 'minute(s)'.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{You submitted an SOS recently. Please wait 1 more minute before sending another. If this is an ongoing emergency, call 911 directly.} other{You submitted an SOS recently. Please wait {minutes} more minutes before sending another. If this is an ongoing emergency, call 911 directly.}}'**
  String sosCooldownWarning(int minutes);

  /// No description provided for @sosSentTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS Sent'**
  String get sosSentTitle;

  /// No description provided for @sosSentBody.
  ///
  /// In en, this message translates to:
  /// **'Your emergency report has been received and is being reviewed by a dispatcher.'**
  String get sosSentBody;

  /// No description provided for @actionBackToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get actionBackToHome;

  /// No description provided for @sosWorsensNote.
  ///
  /// In en, this message translates to:
  /// **'If the emergency worsens, call 911 directly.\nA dispatcher will contact you if needed.'**
  String get sosWorsensNote;

  /// No description provided for @sosDispatchedTo.
  ///
  /// In en, this message translates to:
  /// **'Dispatched to'**
  String get sosDispatchedTo;

  /// No description provided for @sosAddDetails.
  ///
  /// In en, this message translates to:
  /// **'Add more details (optional)'**
  String get sosAddDetails;

  /// No description provided for @sosAddDetailsHelp.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is already sent. If you can safely provide more information (what happened, number of people involved, etc.), the dispatcher will find it helpful.'**
  String get sosAddDetailsHelp;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @sosSendDetails.
  ///
  /// In en, this message translates to:
  /// **'Send Details'**
  String get sosSendDetails;

  /// No description provided for @sosDetailsSent.
  ///
  /// In en, this message translates to:
  /// **'Additional details sent. The dispatcher has been updated.'**
  String get sosDetailsSent;

  /// No description provided for @formSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Report Submitted'**
  String get formSubmittedTitle;

  /// No description provided for @formTrackReport.
  ///
  /// In en, this message translates to:
  /// **'Track My Report'**
  String get formTrackReport;

  /// No description provided for @formReportEmergency.
  ///
  /// In en, this message translates to:
  /// **'Report Emergency'**
  String get formReportEmergency;

  /// No description provided for @formMyReports.
  ///
  /// In en, this message translates to:
  /// **'My Reports'**
  String get formMyReports;

  /// No description provided for @actionLogOutForm.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get actionLogOutForm;

  /// No description provided for @formDescribe.
  ///
  /// In en, this message translates to:
  /// **'Describe the emergency'**
  String get formDescribe;

  /// No description provided for @formDescribeHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Fire in Brgy. Caraycaray Naval, a house is burning, two people are escaping...'**
  String get formDescribeHint;

  /// No description provided for @formDescribeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please describe the emergency.'**
  String get formDescribeRequired;

  /// No description provided for @formDescribeTooShort.
  ///
  /// In en, this message translates to:
  /// **'Please provide more detail (at least 10 characters).'**
  String get formDescribeTooShort;

  /// No description provided for @formSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Emergency Report'**
  String get formSubmit;

  /// No description provided for @formSubmitNote.
  ///
  /// In en, this message translates to:
  /// **'This report will be reviewed by a dispatcher. For life-threatening emergencies, also call 911.'**
  String get formSubmitNote;

  /// No description provided for @actionChangeForm.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get actionChangeForm;

  /// No description provided for @formNoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location not available - report will be sent without GPS'**
  String get formNoLocation;

  /// Resident withdrawing their own report from My Reports.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get withdrawReport;

  /// Resident withdrawing their own report from My Reports.
  ///
  /// In en, this message translates to:
  /// **'Move this report to Trash?'**
  String get withdrawConfirmTitle;

  /// Resident withdrawing their own report from My Reports. Must state the 30-day auto-delete policy — this is the only place that promise is made before the fact.
  ///
  /// In en, this message translates to:
  /// **'It will be moved to Trash and taken off the dispatcher\'s list. Reports in Trash are permanently deleted after 30 days. Do this only if help is no longer needed.'**
  String get withdrawConfirmBody;

  /// Resident withdrawing their own report from My Reports.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get withdrawConfirmAction;

  /// Resident withdrawing their own report from My Reports.
  ///
  /// In en, this message translates to:
  /// **'Keep report'**
  String get withdrawCancelAction;

  /// Resident withdrawing their own report from My Reports.
  ///
  /// In en, this message translates to:
  /// **'Moved to Trash. It will be permanently deleted in 30 days.'**
  String get withdrawDone;

  /// Trash filter on My Reports: reports the resident withdrew.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get filterTrash;

  /// Trash filter on My Reports: reports the resident withdrew.
  ///
  /// In en, this message translates to:
  /// **'Nothing withdrawn'**
  String get noTrashedReports;

  /// Trash filter on My Reports: reports the resident withdrew.
  ///
  /// In en, this message translates to:
  /// **'Reports you take back appear here. They stay on record, but nobody is working on them.'**
  String get noTrashedReportsBody;

  /// Countdown shown on a trashed report — how long until the 30-day retention permanently deletes it.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Deletes today} =1{Deletes in 1 day} other{Deletes in {days} days}}'**
  String trashDeletesInDays(int days);

  /// App bar title of the full report detail screen, opened by tapping a card in My Reports.
  ///
  /// In en, this message translates to:
  /// **'Report Details'**
  String get reportDetailsTitle;

  /// Responder app: Home
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get respTabHome;

  /// Responder app: Stats
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get respTabStats;

  /// Responder app: the tab listing every report assigned to this responder
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get respTabReports;

  /// Responder app: incidents this responder closed today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get respStatToday;

  /// Responder app: this responder's median time from dispatch to close
  ///
  /// In en, this message translates to:
  /// **'Typical'**
  String get respStatTypical;

  /// Responder app: Map
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get respTabMap;

  /// Responder app: Profile
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get respTabProfile;

  /// Responder app: Assigned
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get respStatAssigned;

  /// Responder app: Critical
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get respStatCritical;

  /// Responder app: Longest waiting
  ///
  /// In en, this message translates to:
  /// **'Longest waiting'**
  String get respStatOldest;

  /// Responder app: Home screen greeting subtitle, under the name greeting
  ///
  /// In en, this message translates to:
  /// **'Here\'s what\'s on your queue today.'**
  String get respHomeGreetingSubtitle;

  /// Responder app: Home screen recent-activity section heading
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get respHomeRecentActivity;

  /// Responder app: Home screen recent-activity "view all" action
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get respHomeViewAll;

  /// Responder app: Home screen queue section heading
  ///
  /// In en, this message translates to:
  /// **'Assigned to you'**
  String get respHomeQueueTitle;

  /// Responder app: Home screen quick-action tile jumping to the worst-ranked open assignment
  ///
  /// In en, this message translates to:
  /// **'Awaiting Dispatch'**
  String get respHomeAwaitingDispatch;

  /// Responder app: Home screen empty-queue card title, on duty
  ///
  /// In en, this message translates to:
  /// **'No assignments'**
  String get respHomeNoAssignmentsTitle;

  /// Responder app: Home screen empty-queue card title, off duty
  ///
  /// In en, this message translates to:
  /// **'Off duty'**
  String get respHomeOffDutyTitle;

  /// Responder app: Home screen empty-queue card body heading, on duty
  ///
  /// In en, this message translates to:
  /// **'Queue clear'**
  String get respHomeQueueClear;

  /// Responder app: Home screen empty-queue card body heading, off duty
  ///
  /// In en, this message translates to:
  /// **'Not accepting calls'**
  String get respHomeNotAccepting;

  /// Responder app: Home screen empty-queue card body, on duty
  ///
  /// In en, this message translates to:
  /// **'Nothing assigned to you yet. New calls will show up here.'**
  String get respHomeQueueClearBody;

  /// Responder app: Home screen empty-queue card body, off duty
  ///
  /// In en, this message translates to:
  /// **'No assignments will be sent while you are off duty. Flip the switch above.'**
  String get respHomeOffDutyBody;

  /// Responder app: My dashboard
  ///
  /// In en, this message translates to:
  /// **'My dashboard'**
  String get respDashTitle;

  /// Responder app: Assigned
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get respDashAssigned;

  /// Responder app: Critical
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get respDashCritical;

  /// Responder app: En route
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get respDashEnRoute;

  /// Responder app: On scene
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get respDashOnScene;

  /// Responder app: Closed today
  ///
  /// In en, this message translates to:
  /// **'Closed today'**
  String get respDashClosedToday;

  /// Responder app: Typical time to close
  ///
  /// In en, this message translates to:
  /// **'Typical time to close'**
  String get respDashTypicalTime;

  /// Responder app: From the moment you were sent, to resolved.
  ///
  /// In en, this message translates to:
  /// **'From the moment you were sent, to resolved.'**
  String get respDashTypicalBody;

  /// Responder app: My closed incidents
  ///
  /// In en, this message translates to:
  /// **'My closed incidents'**
  String get respHistoryTitle;

  /// Responder app: Could not load your history
  ///
  /// In en, this message translates to:
  /// **'Could not load your history'**
  String get respHistoryError;

  /// Responder app: Nothing closed yet
  ///
  /// In en, this message translates to:
  /// **'Nothing closed yet'**
  String get respHistoryEmpty;

  /// Responder app: I WILL RESPOND
  ///
  /// In en, this message translates to:
  /// **'I WILL RESPOND'**
  String get respAccept;

  /// Responder app: CAN'T RESPOND
  ///
  /// In en, this message translates to:
  /// **'CAN\'T RESPOND'**
  String get respDecline;

  /// Responder app: CAN'T RESPOND
  ///
  /// In en, this message translates to:
  /// **'CAN\'T RESPOND'**
  String get respDeclineLong;

  /// Responder app: You have accepted this. The dispatcher knows.
  ///
  /// In en, this message translates to:
  /// **'You have accepted this. The dispatcher knows.'**
  String get respAccepted;

  /// Responder app: seconds
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get respSeconds;

  /// Responder app: NO ANSWER YET
  ///
  /// In en, this message translates to:
  /// **'NO ANSWER YET'**
  String get respOverdue;

  /// Responder app: NOT YET TRIAGED
  ///
  /// In en, this message translates to:
  /// **'NOT YET TRIAGED'**
  String get respUntriaged;

  /// Responder app: Can't respond?
  ///
  /// In en, this message translates to:
  /// **'Can\'t respond?'**
  String get respDeclineTitle;

  /// Responder app: This goes back to the dispatcher with your reason, so they can send so
  ///
  /// In en, this message translates to:
  /// **'This goes back to the dispatcher with your reason, so they can send someone else right away.'**
  String get respDeclineSubtitle;

  /// Responder app: Extra detail (optional)
  ///
  /// In en, this message translates to:
  /// **'Extra detail (optional)'**
  String get respDeclineNote;

  /// Responder app: For example: truck is on a jack, 30 more minutes
  ///
  /// In en, this message translates to:
  /// **'For example: truck is on a jack, 30 more minutes'**
  String get respDeclineNoteHint;

  /// Responder app: Send back to dispatcher
  ///
  /// In en, this message translates to:
  /// **'Send back to dispatcher'**
  String get respDeclineSubmit;

  /// Responder app: What did you find?
  ///
  /// In en, this message translates to:
  /// **'What did you find?'**
  String get respCloseTitle;

  /// Responder app: Number of people
  ///
  /// In en, this message translates to:
  /// **'Number of people'**
  String get respCloseCasualties;

  /// Responder app: Leave blank if not counted. That is not the same as zero.
  ///
  /// In en, this message translates to:
  /// **'Leave blank if not counted. That is not the same as zero.'**
  String get respCloseCasualtiesHint;

  /// Responder app: Injured
  ///
  /// In en, this message translates to:
  /// **'Injured'**
  String get respCloseInjured;

  /// Responder app: Died
  ///
  /// In en, this message translates to:
  /// **'Died'**
  String get respCloseFatal;

  /// Responder app: Taken to hospital
  ///
  /// In en, this message translates to:
  /// **'Taken to hospital'**
  String get respCloseTransported;

  /// Responder app: Short account (optional)
  ///
  /// In en, this message translates to:
  /// **'Short account (optional)'**
  String get respCloseNarrative;

  /// Responder app: What happened, and what you did
  ///
  /// In en, this message translates to:
  /// **'What happened, and what you did'**
  String get respCloseNarrativeHint;

  /// Responder app: Close incident
  ///
  /// In en, this message translates to:
  /// **'Close incident'**
  String get respCloseSubmit;

  /// Responder app: Not yet — I'll come back
  ///
  /// In en, this message translates to:
  /// **'Not yet — I\'ll come back'**
  String get respCloseLater;

  /// Responder app: Count
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get respCount;

  /// Responder app: Not counted
  ///
  /// In en, this message translates to:
  /// **'Not counted'**
  String get respNotCounted;

  /// Responder app: Incident closed. Thank you!
  ///
  /// In en, this message translates to:
  /// **'Incident closed. Thank you!'**
  String get respClosed;

  /// Responder app: Request assistance
  ///
  /// In en, this message translates to:
  /// **'Request assistance'**
  String get respBackupTitle;

  /// Responder app: This creates a new incident for their dispatcher, linked to this call.
  ///
  /// In en, this message translates to:
  /// **'This creates a new incident for their dispatcher, linked to this call. It is not just a message.'**
  String get respBackupSubtitle;

  /// Responder app: What do you need? *
  ///
  /// In en, this message translates to:
  /// **'What do you need? *'**
  String get respBackupNeed;

  /// Responder app: For example: 2 injured, need an ambulance
  ///
  /// In en, this message translates to:
  /// **'For example: 2 injured, need an ambulance'**
  String get respBackupNeedHint;

  /// Responder app: Send the request
  ///
  /// In en, this message translates to:
  /// **'Send the request'**
  String get respBackupSubmit;

  /// Responder app: Request another agency's help
  ///
  /// In en, this message translates to:
  /// **'Request another agency\'s help'**
  String get respBackupAction;

  /// Responder app: Are you in danger?
  ///
  /// In en, this message translates to:
  /// **'Are you in danger?'**
  String get respDistressTitle;

  /// Responder app: This alerts the dispatcher immediately, with your location.
  ///
  /// Use it if
  ///
  /// In en, this message translates to:
  /// **'This alerts the dispatcher immediately, with your location.\n\nUse it if you yourself need help.'**
  String get respDistressBody;

  /// Responder app: No
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get respDistressNo;

  /// Responder app: YES, HELP
  ///
  /// In en, this message translates to:
  /// **'YES, HELP'**
  String get respDistressYes;

  /// Responder app: PRESS AND HOLD IF YOU ARE IN DANGER
  ///
  /// In en, this message translates to:
  /// **'PRESS AND HOLD IF YOU ARE IN DANGER'**
  String get respDistressHold;

  /// Responder app: For your own safety, not the incident
  ///
  /// In en, this message translates to:
  /// **'For your own safety, not the incident'**
  String get respDistressHoldBody;

  /// Responder app: Distress signal. Press and hold to raise.
  ///
  /// In en, this message translates to:
  /// **'Distress signal. Press and hold to raise.'**
  String get respDistressSemantics;

  /// Responder app: Going to the scene
  ///
  /// In en, this message translates to:
  /// **'Going to the scene'**
  String get respNavTitle;

  /// Responder app: Finding your location...
  ///
  /// In en, this message translates to:
  /// **'Finding your location...'**
  String get respNavLocating;

  /// Responder app: This is a straight line, not a road. Follow the actual streets.
  ///
  /// In en, this message translates to:
  /// **'This is a straight line, not a road. Follow the actual streets.'**
  String get respNavStraightLine;

  /// Responder app: Open in Google Maps for directions
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps for directions'**
  String get respNavExternal;

  /// Responder app: No maps app on this phone.
  ///
  /// In en, this message translates to:
  /// **'No maps app on this phone.'**
  String get respNavNoMapsApp;

  /// Responder app: straight-line distance
  ///
  /// In en, this message translates to:
  /// **'straight-line distance'**
  String get respNavStraightDistance;

  /// Responder app: almost there
  ///
  /// In en, this message translates to:
  /// **'almost there'**
  String get respNavClose;

  /// Responder app: Incident
  ///
  /// In en, this message translates to:
  /// **'Incident'**
  String get respIncident;

  /// Responder app: INCIDENT REPORT
  ///
  /// In en, this message translates to:
  /// **'INCIDENT REPORT'**
  String get respSectionReport;

  /// Responder app: LOCATION
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get respSectionLocation;

  /// Responder app: REPORTER
  ///
  /// In en, this message translates to:
  /// **'REPORTER'**
  String get respSectionReporter;

  /// Responder app: STATION
  ///
  /// In en, this message translates to:
  /// **'STATION'**
  String get respSectionStation;

  /// Responder app: Category
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get respFieldCategory;

  /// Responder app: Address
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get respFieldAddress;

  /// Responder app: Landmark
  ///
  /// In en, this message translates to:
  /// **'Landmark'**
  String get respFieldLandmark;

  /// Responder app: GPS
  ///
  /// In en, this message translates to:
  /// **'GPS'**
  String get respFieldGps;

  /// Responder app: Name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get respFieldName;

  /// Responder app: Phone
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get respFieldPhone;

  /// Responder app: Station
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get respFieldStation;

  /// Responder app: Emergency Contact
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact'**
  String get respFieldEmergencyContact;

  /// Responder app: Contact Number
  ///
  /// In en, this message translates to:
  /// **'Contact Number'**
  String get respFieldContactNumber;

  /// Responder app: Navigate
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get respNavigate;

  /// Responder app: Go Back
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get respGoBack;

  /// Responder app: SOS account flagged
  ///
  /// In en, this message translates to:
  /// **'SOS account flagged'**
  String get respSosFlagged;

  /// Responder app: The words above are transcribed and can be wrong.
  ///
  /// In en, this message translates to:
  /// **'The words above are transcribed and can be wrong.'**
  String get respTranscriptWarning;

  /// Responder app: You can only take photos once you are on scene.
  ///
  /// In en, this message translates to:
  /// **'You can only take photos once you are on scene.'**
  String get respSceneOnlyWhenOnScene;

  /// Responder app: scene capture button label while uploading
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get respSceneUploading;

  /// Responder app: scene capture button label before any photo is attached
  ///
  /// In en, this message translates to:
  /// **'Take a photo of the scene'**
  String get respSceneTakePhoto;

  /// Responder app: scene capture button label after at least one photo is attached
  ///
  /// In en, this message translates to:
  /// **'Add more ({count} added)'**
  String respSceneAddMore(int count);

  /// Responder app: scene capture failure, no authenticated user
  ///
  /// In en, this message translates to:
  /// **'You are not signed in.'**
  String get respSceneNotSignedIn;

  /// Responder app: scene capture success toast
  ///
  /// In en, this message translates to:
  /// **'Photo added.'**
  String get respScenePhotoAdded;

  /// Responder app: scene capture attach-failure toast
  ///
  /// In en, this message translates to:
  /// **'Photo could not be added.'**
  String get respScenePhotoNotAdded;

  /// Responder app: scene capture upload-failure toast, offline
  ///
  /// In en, this message translates to:
  /// **'Photo could not be uploaded. Try again when you have signal.'**
  String get respScenePhotoUploadFailed;

  /// Responder app: queued-action label, accept
  ///
  /// In en, this message translates to:
  /// **'Accepting the call'**
  String get respActionAccept;

  /// Responder app: queued-action label, decline
  ///
  /// In en, this message translates to:
  /// **'Declining the call'**
  String get respActionDecline;

  /// Responder app: queued-action label, status change
  ///
  /// In en, this message translates to:
  /// **'Status update'**
  String get respActionStatusUpdate;

  /// Responder app: queued-action label, close
  ///
  /// In en, this message translates to:
  /// **'Closing the incident'**
  String get respActionClose;

  /// Responder app: queued-action label, scene media attach
  ///
  /// In en, this message translates to:
  /// **'Scene photos'**
  String get respActionSceneMedia;

  /// Responder app: queued-action label, distress signal
  ///
  /// In en, this message translates to:
  /// **'Distress signal'**
  String get respActionDistress;

  /// Responder app: Profile
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get respProfileTitle;

  /// Responder app: Profile saved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved.'**
  String get respProfileSaved;

  /// Responder app: Cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get respProfileCancel;

  /// Responder app: Edit
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get respProfileEdit;

  /// Responder app: Save
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get respProfileSave;

  /// Responder app: Contact
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get respProfileContact;

  /// Responder app: Assignment
  ///
  /// In en, this message translates to:
  /// **'Assignment'**
  String get respProfileAssignment;

  /// Responder app: This shift
  ///
  /// In en, this message translates to:
  /// **'This shift'**
  String get respProfileShift;

  /// Responder app: Badge ID
  ///
  /// In en, this message translates to:
  /// **'Badge ID'**
  String get respProfileBadge;

  /// Responder app: Agency
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get respProfileAgency;

  /// Responder app: Municipality
  ///
  /// In en, this message translates to:
  /// **'Municipality'**
  String get respProfileMunicipality;

  /// Responder app: Status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get respProfileStatus;

  /// Responder app: Assigned right now
  ///
  /// In en, this message translates to:
  /// **'Assigned right now'**
  String get respProfileAssignedNow;

  /// Responder app: Waiting to send
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get respProfileWaitingToSend;

  /// Responder app: Profile shift summary — incidents resolved in the current 30-day dashboard window
  ///
  /// In en, this message translates to:
  /// **'Resolved this period'**
  String get respProfileResolvedPeriod;

  /// Responder app: Profile shift summary — median minutes from dispatch to close
  ///
  /// In en, this message translates to:
  /// **'Typical response time'**
  String get respProfileTypicalResponse;

  /// Responder app: Name is required.
  ///
  /// In en, this message translates to:
  /// **'Name is required.'**
  String get respProfileNameRequired;

  /// Responder app: Log out
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get respLogout;

  /// Responder app: Log out?
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get respLogoutConfirm;

  /// Responder app: You will stop receiving dispatch alerts on this phone until you sign i
  ///
  /// In en, this message translates to:
  /// **'You will stop receiving dispatch alerts on this phone until you sign in again.'**
  String get respLogoutBody;

  /// Responder app: ON DUTY
  ///
  /// In en, this message translates to:
  /// **'ON DUTY'**
  String get respOnDuty;

  /// Responder app: OFF DUTY
  ///
  /// In en, this message translates to:
  /// **'OFF DUTY'**
  String get respOffDuty;

  /// Responder app: Approved
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get respApproved;

  /// Responder app: Not approved
  ///
  /// In en, this message translates to:
  /// **'Not approved'**
  String get respRejected;

  /// Responder app: Awaiting approval
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get respPending;

  /// Responder app: Awaiting approval
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get respPendingTitle;

  /// Responder app: You cannot receive dispatch until your Agency Admin verifies your badg
  ///
  /// In en, this message translates to:
  /// **'You cannot receive dispatch until your Agency Admin verifies your badge ID.'**
  String get respPendingBody;

  /// Responder app: Your account was not approved
  ///
  /// In en, this message translates to:
  /// **'Your account was not approved'**
  String get respRejectedTitle;

  /// Responder app: You cannot receive dispatch. Talk to your Agency Admin.
  ///
  /// In en, this message translates to:
  /// **'You cannot receive dispatch. Talk to your Agency Admin.'**
  String get respRejectedBody;

  /// Responder app: Cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get respCancel;

  /// Responder app: ROAD WARNINGS ({count})
  ///
  /// In en, this message translates to:
  /// **'ROAD WARNINGS ({count})'**
  String respHazardBanner(int count);

  /// Responder app: Refused {count}x
  ///
  /// In en, this message translates to:
  /// **'Refused {count}x'**
  String respDeclinedTimes(int count);

  /// Responder app: {count} prior warning(s)
  ///
  /// In en, this message translates to:
  /// **'{count} prior warning(s)'**
  String respPriorWarnings(int count);

  /// Responder app: {count} waiting — will send when there is signal
  ///
  /// In en, this message translates to:
  /// **'{count} waiting — will send when there is signal'**
  String respSyncPending(int count);

  /// Responder app: Resident is told: {eta}
  ///
  /// In en, this message translates to:
  /// **'Resident is told: {eta}'**
  String respTellingResident(String eta);

  /// Responder app: Landmark: {landmark}
  ///
  /// In en, this message translates to:
  /// **'Landmark: {landmark}'**
  String respLandmarkPrefix(String landmark);

  /// Responder app: Last {days} days
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String respStatsPeriod(int days);

  /// Responder app: Answer within {time}
  ///
  /// In en, this message translates to:
  /// **'Answer within {time}'**
  String respAnswerWithin(String time);

  /// Responder app: about {minutes} min
  ///
  /// In en, this message translates to:
  /// **'about {minutes} min'**
  String respEtaMinutes(int minutes);

  /// Responder app: Vehicle down
  ///
  /// In en, this message translates to:
  /// **'Vehicle down'**
  String get respReasonVehicleDown;

  /// Responder app: The truck or ambulance cannot roll
  ///
  /// In en, this message translates to:
  /// **'The truck or ambulance cannot roll'**
  String get respReasonVehicleDownHint;

  /// Responder app: On another call
  ///
  /// In en, this message translates to:
  /// **'On another call'**
  String get respReasonCommitted;

  /// Responder app: Already on another incident that is not closed
  ///
  /// In en, this message translates to:
  /// **'Already on another incident that is not closed'**
  String get respReasonCommittedHint;

  /// Responder app: Out of area
  ///
  /// In en, this message translates to:
  /// **'Out of area'**
  String get respReasonOutOfArea;

  /// Responder app: Wrong municipality for this unit
  ///
  /// In en, this message translates to:
  /// **'Wrong municipality for this unit'**
  String get respReasonOutOfAreaHint;

  /// Responder app: Not enough crew
  ///
  /// In en, this message translates to:
  /// **'Not enough crew'**
  String get respReasonCrew;

  /// Responder app: Not enough hands to respond safely
  ///
  /// In en, this message translates to:
  /// **'Not enough hands to respond safely'**
  String get respReasonCrewHint;

  /// Responder app: Road impassable
  ///
  /// In en, this message translates to:
  /// **'Road impassable'**
  String get respReasonRoad;

  /// Responder app: Flood, landslide or a cut bridge
  ///
  /// In en, this message translates to:
  /// **'Flood, landslide or a cut bridge'**
  String get respReasonRoadHint;

  /// Responder app: Another reason
  ///
  /// In en, this message translates to:
  /// **'Another reason'**
  String get respReasonOther;

  /// Responder app: Explain in the note
  ///
  /// In en, this message translates to:
  /// **'Explain in the note'**
  String get respReasonOtherHint;

  /// Responder app: Handled on scene
  ///
  /// In en, this message translates to:
  /// **'Handled on scene'**
  String get respOutcomeHandled;

  /// Responder app: Dealt with, nobody moved
  ///
  /// In en, this message translates to:
  /// **'Dealt with, nobody moved'**
  String get respOutcomeHandledHint;

  /// Responder app: Taken to hospital
  ///
  /// In en, this message translates to:
  /// **'Taken to hospital'**
  String get respOutcomeTransported;

  /// Responder app: Casualties taken to a facility
  ///
  /// In en, this message translates to:
  /// **'Casualties taken to a facility'**
  String get respOutcomeTransportedHint;

  /// Responder app: Turned over
  ///
  /// In en, this message translates to:
  /// **'Turned over'**
  String get respOutcomeTurnedOver;

  /// Responder app: Handed over to PNP, BFP, MDRRMO or a hospital
  ///
  /// In en, this message translates to:
  /// **'Handed over to PNP, BFP, MDRRMO or a hospital'**
  String get respOutcomeTurnedOverHint;

  /// Responder app: No real emergency
  ///
  /// In en, this message translates to:
  /// **'No real emergency'**
  String get respOutcomeFalseAlarm;

  /// Responder app: Nothing was happening
  ///
  /// In en, this message translates to:
  /// **'Nothing was happening'**
  String get respOutcomeFalseAlarmHint;

  /// Responder app: Nobody found
  ///
  /// In en, this message translates to:
  /// **'Nobody found'**
  String get respOutcomeNobodyFound;

  /// Responder app: Arrived, no incident and no reporter
  ///
  /// In en, this message translates to:
  /// **'Arrived, no incident and no reporter'**
  String get respOutcomeNobodyFoundHint;

  /// Responder app: Refused assistance
  ///
  /// In en, this message translates to:
  /// **'Refused assistance'**
  String get respOutcomeRefused;

  /// Responder app: Party present and declined help
  ///
  /// In en, this message translates to:
  /// **'Party present and declined help'**
  String get respOutcomeRefusedHint;

  /// Responder app: Could not reach it
  ///
  /// In en, this message translates to:
  /// **'Could not reach it'**
  String get respOutcomeNoAccess;

  /// Responder app: Could not reach the scene at all
  ///
  /// In en, this message translates to:
  /// **'Could not reach the scene at all'**
  String get respOutcomeNoAccessHint;

  /// Responder app: Other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get respOutcomeOther;

  /// Responder app: Explain in the notes
  ///
  /// In en, this message translates to:
  /// **'Explain in the notes'**
  String get respOutcomeOtherHint;

  /// Responder app: Impassable
  ///
  /// In en, this message translates to:
  /// **'Impassable'**
  String get respHazardRoad;

  /// Responder app: Hard to reach
  ///
  /// In en, this message translates to:
  /// **'Hard to reach'**
  String get respHazardAccess;

  /// Responder app: Dangerous
  ///
  /// In en, this message translates to:
  /// **'Dangerous'**
  String get respHazardSecurity;

  /// Responder app: Animals
  ///
  /// In en, this message translates to:
  /// **'Animals'**
  String get respHazardAnimal;

  /// Responder app: Unsafe building
  ///
  /// In en, this message translates to:
  /// **'Unsafe building'**
  String get respHazardStructural;

  /// Responder app: Warning
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get respHazardOther;

  /// Responder app: No answer — the dispatcher can see this
  ///
  /// In en, this message translates to:
  /// **'No answer — the dispatcher can see this'**
  String get respNoAnswerSeen;

  /// Responder app: incident detail, fallback action button label
  ///
  /// In en, this message translates to:
  /// **'Update Status'**
  String get respUpdateStatus;

  /// Responder app: incident detail, generic answer/backup send failure toast
  ///
  /// In en, this message translates to:
  /// **'Could not send. Try again.'**
  String get respAnswerSendFailed;

  /// Responder app: incident detail, close-incident failure toast
  ///
  /// In en, this message translates to:
  /// **'Could not close.'**
  String get respCloseFailed;

  /// Responder app: incident detail, decline-assignment success toast
  ///
  /// In en, this message translates to:
  /// **'Sent back to the dispatcher. They will look for another unit.'**
  String get respDeclineSent;

  /// Responder app: incident detail, backup-request success toast
  ///
  /// In en, this message translates to:
  /// **'Sent to {station}. It is now in their queue.'**
  String respBackupSentTo(String station);

  /// Responder app: incident detail, escalate success toast
  ///
  /// In en, this message translates to:
  /// **'Sent. The Agency Admin knows.'**
  String get respEscalateSent;

  /// Responder app: incident detail, distress signal sent while online
  ///
  /// In en, this message translates to:
  /// **'SENT. The dispatcher can see you now.'**
  String get respDistressSentLive;

  /// Responder app: incident detail, distress signal queued while offline — a safety-critical fallback instruction
  ///
  /// In en, this message translates to:
  /// **'No signal — this is queued. CALL THE STATION ON RADIO NOW.'**
  String get respDistressSentQueued;

  /// Responder app: incident detail, confirm dialog body when resolving
  ///
  /// In en, this message translates to:
  /// **'Mark this incident as Resolved? The dispatcher and the reporter will see this.'**
  String get respConfirmResolve;

  /// Responder app: incident detail, confirm dialog body for a generic status advance
  ///
  /// In en, this message translates to:
  /// **'Update the incident\'s status?'**
  String get respConfirmStatusUpdate;

  /// Responder app: incident detail, navigation fallback when the report has neither coordinates nor an address
  ///
  /// In en, this message translates to:
  /// **'No location was recorded on this report. Ask the dispatcher.'**
  String get respNoLocationRecorded;

  /// No description provided for @mapNearbyStationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby Emergency Stations'**
  String get mapNearbyStationsTitle;

  /// No description provided for @mapResponderTitle.
  ///
  /// In en, this message translates to:
  /// **'Incident Map'**
  String get mapResponderTitle;

  /// Map screen title when opened from My Reports' 'View on Map' — locked to one report and its responding station, not the usual nearby-stations view.
  ///
  /// In en, this message translates to:
  /// **'Report Location'**
  String get mapReportLocationTitle;

  /// No description provided for @mapLocationOff.
  ///
  /// In en, this message translates to:
  /// **'Location is off'**
  String get mapLocationOff;

  /// No description provided for @mapLocationSearching.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get mapLocationSearching;

  /// No description provided for @mapLocationPrecise.
  ///
  /// In en, this message translates to:
  /// **'You are here · ±{accuracy} m'**
  String mapLocationPrecise(int accuracy);

  /// No description provided for @mapLocationImprecise.
  ///
  /// In en, this message translates to:
  /// **'Approximate · ±{accuracy} m'**
  String mapLocationImprecise(int accuracy);

  /// No description provided for @mapNoLocationYet.
  ///
  /// In en, this message translates to:
  /// **'No location yet. Check if your GPS is turned on.'**
  String get mapNoLocationYet;

  /// Label under the viewer's own pin on the map.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get mapYouLabel;

  /// No description provided for @mapLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading map…'**
  String get mapLoading;

  /// No description provided for @mapGetDirections.
  ///
  /// In en, this message translates to:
  /// **'Get directions'**
  String get mapGetDirections;

  /// No description provided for @mapStationDistance.
  ///
  /// In en, this message translates to:
  /// **'{distanceKm} km away · {agency}'**
  String mapStationDistance(String distanceKm, String agency);

  /// Distance-only, for a row in the station picker list — the agency is already shown as an icon on that row.
  ///
  /// In en, this message translates to:
  /// **'{distanceKm} km'**
  String mapStationDistanceShort(String distanceKm);

  /// No description provided for @settingsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings & Profile'**
  String get settingsScreenTitle;

  /// No description provided for @settingsEditPersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit personal information'**
  String get settingsEditPersonalInfo;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// No description provided for @settingsNotificationPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get settingsNotificationPreferences;

  /// No description provided for @settingsAppSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get settingsAppSettingsSection;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsDarkMode;

  /// No description provided for @settingsLocationServices.
  ///
  /// In en, this message translates to:
  /// **'Location services'**
  String get settingsLocationServices;

  /// No description provided for @settingsLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission was not granted.'**
  String get settingsLocationDenied;

  /// No description provided for @settingsLocationOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off location services?'**
  String get settingsLocationOffTitle;

  /// No description provided for @settingsLocationOffBody.
  ///
  /// In en, this message translates to:
  /// **'Android and iOS only let you change this in your phone\'s Settings app, not inside Ziren.'**
  String get settingsLocationOffBody;

  /// No description provided for @settingsOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get settingsOpenSystemSettings;

  /// No description provided for @settingsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// No description provided for @settingsOfflineMaps.
  ///
  /// In en, this message translates to:
  /// **'Offline maps'**
  String get settingsOfflineMaps;

  /// No description provided for @settingsOfflineMapsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Offline maps are coming in a future update.'**
  String get settingsOfflineMapsComingSoon;

  /// No description provided for @settingsSupportSection.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupportSection;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsSectionNotifications;

  /// No description provided for @settingsSectionLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get settingsSectionLocation;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsSectionHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get settingsSectionHelpSupport;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @settingsHelpFaq.
  ///
  /// In en, this message translates to:
  /// **'Help & FAQ'**
  String get settingsHelpFaq;

  /// No description provided for @settingsFaqReportQ.
  ///
  /// In en, this message translates to:
  /// **'How do I report an emergency?'**
  String get settingsFaqReportQ;

  /// No description provided for @settingsFaqReportA.
  ///
  /// In en, this message translates to:
  /// **'On Home, tap the kind of emergency (Fire, Medical, Accident, Crime, Calamity or Other). Check the landmark, say or type what happened, review it, then send. Ziren sends it to the nearest station that handles it.'**
  String get settingsFaqReportA;

  /// No description provided for @settingsFaqOfflineQ.
  ///
  /// In en, this message translates to:
  /// **'What happens with no internet?'**
  String get settingsFaqOfflineQ;

  /// No description provided for @settingsFaqOfflineA.
  ///
  /// In en, this message translates to:
  /// **'A report needs internet to send. With no data, tap the kind of emergency on Home anyway: Ziren shows the official station hotlines for it, and a normal call only needs a phone signal. You can also call 911.'**
  String get settingsFaqOfflineA;

  /// No description provided for @settingsFaqAgencyQ.
  ///
  /// In en, this message translates to:
  /// **'Which agency responds to my report?'**
  String get settingsFaqAgencyQ;

  /// No description provided for @settingsFaqAgencyA.
  ///
  /// In en, this message translates to:
  /// **'It depends on the emergency: BFP for fire, PNP for crime, MDRRMO for medical cases, accidents and calamities. The station in the town where the incident is receives it.'**
  String get settingsFaqAgencyA;

  /// No description provided for @settingsFaqAccountQ.
  ///
  /// In en, this message translates to:
  /// **'How do I update my emergency contact?'**
  String get settingsFaqAccountQ;

  /// No description provided for @settingsFaqAccountA.
  ///
  /// In en, this message translates to:
  /// **'In Settings, open \"Edit personal information\", change the contact name or number, and tap \"Save changes\".'**
  String get settingsFaqAccountA;

  /// No description provided for @settingsAboutZiren.
  ///
  /// In en, this message translates to:
  /// **'About Ziren'**
  String get settingsAboutZiren;

  /// No description provided for @settingsAboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Emergency Response, Simplified. Built for the residents of Biliran.'**
  String get settingsAboutTagline;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAboutVersion(String version);

  /// No description provided for @settingsAboutTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get settingsAboutTerms;

  /// No description provided for @settingsAboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Data Privacy Notice'**
  String get settingsAboutPrivacy;

  /// No description provided for @settingsLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogOut;

  /// No description provided for @settingsLogOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get settingsLogOutConfirmTitle;

  /// No description provided for @settingsLogOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to access Ziren.'**
  String get settingsLogOutConfirmBody;

  /// No description provided for @settingsSectionAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsSectionAccessibility;

  /// No description provided for @settingsAccessibilityAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAccessibilityAppearance;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @settingsAccessibilityTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsAccessibilityTextSize;

  /// No description provided for @textSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get textSizeSmall;

  /// No description provided for @textSizeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get textSizeDefault;

  /// No description provided for @textSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get textSizeLarge;

  /// No description provided for @textSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get textSizeExtraLarge;

  /// No description provided for @textSizePreview.
  ///
  /// In en, this message translates to:
  /// **'A responder will see your report exactly this size.'**
  String get textSizePreview;

  /// No description provided for @settingsReduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsReduceMotion;

  /// No description provided for @settingsHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get settingsHighContrast;

  /// No description provided for @notifMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get notifMoreOptions;

  /// No description provided for @notifClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get notifClearAll;

  /// No description provided for @notifCategoryEmergencyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Emergency Update'**
  String get notifCategoryEmergencyUpdate;

  /// No description provided for @notifCategoryReportConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Report Confirmed'**
  String get notifCategoryReportConfirmed;

  /// No description provided for @notifCategorySafetyAdvisory.
  ///
  /// In en, this message translates to:
  /// **'Safety Advisory'**
  String get notifCategorySafetyAdvisory;

  /// No description provided for @notifCategorySystemMessage.
  ///
  /// In en, this message translates to:
  /// **'System Message'**
  String get notifCategorySystemMessage;

  /// No description provided for @notifReportPrefix.
  ///
  /// In en, this message translates to:
  /// **'Report #'**
  String get notifReportPrefix;

  /// No description provided for @notifEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notifEmptyTitle;

  /// No description provided for @notifEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Status updates for your reports will appear here.'**
  String get notifEmptySubtitle;

  /// No description provided for @voiceTapToRecord.
  ///
  /// In en, this message translates to:
  /// **'Tap to record'**
  String get voiceTapToRecord;

  /// No description provided for @voiceTapToStop.
  ///
  /// In en, this message translates to:
  /// **'Tap to stop'**
  String get voiceTapToStop;

  /// No description provided for @voiceUpToMinutes.
  ///
  /// In en, this message translates to:
  /// **'(up to {minutes} min)'**
  String voiceUpToMinutes(int minutes);

  /// No description provided for @voiceRecordingHint.
  ///
  /// In en, this message translates to:
  /// **'Say what happened in your own words. The station will hear it directly.'**
  String get voiceRecordingHint;

  /// No description provided for @voicePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get voicePlay;

  /// No description provided for @voicePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get voicePause;

  /// No description provided for @voiceRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded · {clock}'**
  String voiceRecorded(String clock);

  /// No description provided for @voiceWillSend.
  ///
  /// In en, this message translates to:
  /// **'This will be sent to the station.'**
  String get voiceWillSend;

  /// No description provided for @voiceDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get voiceDeleteTooltip;

  /// No description provided for @voiceCaptureFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Voice couldn\'t be recorded. Please write what happened above — your report can still be sent.'**
  String get voiceCaptureFailedMsg;

  /// No description provided for @voiceUploadFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Your report was sent, but the recording didn\'t reach the station. If signal is weak, try again.'**
  String get voiceUploadFailedMsg;

  /// No description provided for @voicePeopleCountQuestion.
  ///
  /// In en, this message translates to:
  /// **'How many people are involved? (optional)'**
  String get voicePeopleCountQuestion;

  /// No description provided for @voicePeopleCountHint.
  ///
  /// In en, this message translates to:
  /// **'This is often missed in the recording.'**
  String get voicePeopleCountHint;

  /// No description provided for @voicePeopleCountNotSure.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get voicePeopleCountNotSure;

  /// No description provided for @homeLocating.
  ///
  /// In en, this message translates to:
  /// **'Locating…'**
  String get homeLocating;

  /// My Reports card: location plus distance from the resident's current position.
  ///
  /// In en, this message translates to:
  /// **'{location} · {km} km'**
  String reportsLocationDistance(String location, String km);

  /// Report Details: tapping the location card opens the Map tab centred on this report.
  ///
  /// In en, this message translates to:
  /// **'View on Map'**
  String get reportsViewOnMap;

  /// No description provided for @safetyGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety Guide'**
  String get safetyGuideTitle;

  /// No description provided for @safetyFireTitle.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get safetyFireTitle;

  /// No description provided for @safetyFireStep1.
  ///
  /// In en, this message translates to:
  /// **'Get out of the building immediately. Do not go back for belongings.'**
  String get safetyFireStep1;

  /// No description provided for @safetyFireStep2.
  ///
  /// In en, this message translates to:
  /// **'If there is smoke, get low and crawl to the exit.'**
  String get safetyFireStep2;

  /// No description provided for @safetyFireStep3.
  ///
  /// In en, this message translates to:
  /// **'Do not use the elevator — stairs only.'**
  String get safetyFireStep3;

  /// No description provided for @safetyFireStep4.
  ///
  /// In en, this message translates to:
  /// **'Touch the doorknob with the back of your hand before opening it — if it is hot, do not open it.'**
  String get safetyFireStep4;

  /// No description provided for @safetyFireStep5.
  ///
  /// In en, this message translates to:
  /// **'Once outside, call the BFP right away or report using Ziren.'**
  String get safetyFireStep5;

  /// No description provided for @safetyFireStep6.
  ///
  /// In en, this message translates to:
  /// **'Do not go back inside until it has been declared safe.'**
  String get safetyFireStep6;

  /// No description provided for @safetyEarthquakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Earthquake'**
  String get safetyEarthquakeTitle;

  /// No description provided for @safetyEarthquakeStep1.
  ///
  /// In en, this message translates to:
  /// **'Duck, Cover, Hold — drop down, take cover under a sturdy table, and hold on.'**
  String get safetyEarthquakeStep1;

  /// No description provided for @safetyEarthquakeStep2.
  ///
  /// In en, this message translates to:
  /// **'Stay away from windows, glass, and heavy furniture.'**
  String get safetyEarthquakeStep2;

  /// No description provided for @safetyEarthquakeStep3.
  ///
  /// In en, this message translates to:
  /// **'If outdoors, move away from buildings, posts, and power lines.'**
  String get safetyEarthquakeStep3;

  /// No description provided for @safetyEarthquakeStep4.
  ///
  /// In en, this message translates to:
  /// **'If driving, pull over to a safe spot and stay inside the vehicle.'**
  String get safetyEarthquakeStep4;

  /// No description provided for @safetyEarthquakeStep5.
  ///
  /// In en, this message translates to:
  /// **'After the shaking stops, be ready for aftershocks.'**
  String get safetyEarthquakeStep5;

  /// No description provided for @safetyEarthquakeStep6.
  ///
  /// In en, this message translates to:
  /// **'Check your surroundings for damaged gas or power lines before moving.'**
  String get safetyEarthquakeStep6;

  /// No description provided for @safetyFloodTitle.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get safetyFloodTitle;

  /// No description provided for @safetyFloodStep1.
  ///
  /// In en, this message translates to:
  /// **'Move to higher ground immediately if your barangay is under a flood warning.'**
  String get safetyFloodStep1;

  /// No description provided for @safetyFloodStep2.
  ///
  /// In en, this message translates to:
  /// **'Avoid walking or driving through floodwater — six inches of water can knock a person down.'**
  String get safetyFloodStep2;

  /// No description provided for @safetyFloodStep3.
  ///
  /// In en, this message translates to:
  /// **'Turn off electrical appliances and switch off the main breaker if there is still time.'**
  String get safetyFloodStep3;

  /// No description provided for @safetyFloodStep4.
  ///
  /// In en, this message translates to:
  /// **'Keep important documents in a waterproof container.'**
  String get safetyFloodStep4;

  /// No description provided for @safetyFloodStep5.
  ///
  /// In en, this message translates to:
  /// **'Follow MDRRMO\'s instructions on evacuation.'**
  String get safetyFloodStep5;

  /// No description provided for @safetyFloodStep6.
  ///
  /// In en, this message translates to:
  /// **'Do not drink floodwater or tap water until it has been declared safe.'**
  String get safetyFloodStep6;

  /// No description provided for @safetyTyphoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Typhoon'**
  String get safetyTyphoonTitle;

  /// No description provided for @safetyTyphoonStep1.
  ///
  /// In en, this message translates to:
  /// **'Watch PAGASA advisories and announcements from Ziren.'**
  String get safetyTyphoonStep1;

  /// No description provided for @safetyTyphoonStep2.
  ///
  /// In en, this message translates to:
  /// **'Prepare an emergency kit: water, food, flashlight, first aid, and a power bank.'**
  String get safetyTyphoonStep2;

  /// No description provided for @safetyTyphoonStep3.
  ///
  /// In en, this message translates to:
  /// **'Secure or bring inside anything that could be blown away by the wind.'**
  String get safetyTyphoonStep3;

  /// No description provided for @safetyTyphoonStep4.
  ///
  /// In en, this message translates to:
  /// **'Stay indoors unless told to evacuate.'**
  String get safetyTyphoonStep4;

  /// No description provided for @safetyTyphoonStep5.
  ///
  /// In en, this message translates to:
  /// **'Stay away from trees and power poles during strong winds.'**
  String get safetyTyphoonStep5;

  /// No description provided for @safetyTyphoonStep6.
  ///
  /// In en, this message translates to:
  /// **'Know the location of the nearest evacuation center before the typhoon arrives.'**
  String get safetyTyphoonStep6;

  /// No description provided for @safetyRoadAccidentTitle.
  ///
  /// In en, this message translates to:
  /// **'Road Accident'**
  String get safetyRoadAccidentTitle;

  /// No description provided for @safetyRoadAccidentStep1.
  ///
  /// In en, this message translates to:
  /// **'Make sure you are safe first before helping others.'**
  String get safetyRoadAccidentStep1;

  /// No description provided for @safetyRoadAccidentStep2.
  ///
  /// In en, this message translates to:
  /// **'Turn on hazard/warning lights and set up a marker if you have one.'**
  String get safetyRoadAccidentStep2;

  /// No description provided for @safetyRoadAccidentStep3.
  ///
  /// In en, this message translates to:
  /// **'Do not move the victim unless there is immediate danger (e.g. fire).'**
  String get safetyRoadAccidentStep3;

  /// No description provided for @safetyRoadAccidentStep4.
  ///
  /// In en, this message translates to:
  /// **'Call the PNP and/or MDRRMO right away, or report using Ziren.'**
  String get safetyRoadAccidentStep4;

  /// No description provided for @safetyRoadAccidentStep5.
  ///
  /// In en, this message translates to:
  /// **'Monitor the victim\'s breathing and pulse while waiting for help.'**
  String get safetyRoadAccidentStep5;

  /// No description provided for @safetyRoadAccidentStep6.
  ///
  /// In en, this message translates to:
  /// **'If there is bleeding, apply pressure with a clean cloth.'**
  String get safetyRoadAccidentStep6;

  /// No description provided for @safetyMedicalTitle.
  ///
  /// In en, this message translates to:
  /// **'Medical Emergency'**
  String get safetyMedicalTitle;

  /// No description provided for @safetyMedicalStep1.
  ///
  /// In en, this message translates to:
  /// **'Check if the patient is still conscious and breathing normally.'**
  String get safetyMedicalStep1;

  /// No description provided for @safetyMedicalStep2.
  ///
  /// In en, this message translates to:
  /// **'Call for help right away — do not wait for the situation to get worse.'**
  String get safetyMedicalStep2;

  /// No description provided for @safetyMedicalStep3.
  ///
  /// In en, this message translates to:
  /// **'If not breathing and unconscious, start CPR if you know how.'**
  String get safetyMedicalStep3;

  /// No description provided for @safetyMedicalStep4.
  ///
  /// In en, this message translates to:
  /// **'Do not give food or drink to someone having trouble breathing or who is unconscious.'**
  String get safetyMedicalStep4;

  /// No description provided for @safetyMedicalStep5.
  ///
  /// In en, this message translates to:
  /// **'Keep the patient calm and comfortable while waiting.'**
  String get safetyMedicalStep5;

  /// No description provided for @safetyMedicalStep6.
  ///
  /// In en, this message translates to:
  /// **'Prepare the patient\'s information (age, condition, medication) for the responder.'**
  String get safetyMedicalStep6;

  /// No description provided for @safetyCrimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Crime'**
  String get safetyCrimeTitle;

  /// No description provided for @safetyCrimeStep1.
  ///
  /// In en, this message translates to:
  /// **'Prioritize your own safety — move away from danger if you can.'**
  String get safetyCrimeStep1;

  /// No description provided for @safetyCrimeStep2.
  ///
  /// In en, this message translates to:
  /// **'Do not touch or disturb the crime scene if it is safe to move away.'**
  String get safetyCrimeStep2;

  /// No description provided for @safetyCrimeStep3.
  ///
  /// In en, this message translates to:
  /// **'Call the PNP right away, or report using Ziren.'**
  String get safetyCrimeStep3;

  /// No description provided for @safetyCrimeStep4.
  ///
  /// In en, this message translates to:
  /// **'Note the details: appearance, plate number, direction — if you can safely do so.'**
  String get safetyCrimeStep4;

  /// No description provided for @safetyCrimeStep5.
  ///
  /// In en, this message translates to:
  /// **'Stay in a safe place until the responder arrives.'**
  String get safetyCrimeStep5;

  /// No description provided for @safetyCrimeStep6.
  ///
  /// In en, this message translates to:
  /// **'Follow the police\'s instructions once they arrive at the scene.'**
  String get safetyCrimeStep6;

  /// No description provided for @contactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contacts'**
  String get contactsTitle;

  /// No description provided for @contactsNationalTitle.
  ///
  /// In en, this message translates to:
  /// **'National Emergency Hotline'**
  String get contactsNationalTitle;

  /// No description provided for @contactsNationalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For any emergency, anywhere in the Philippines'**
  String get contactsNationalSubtitle;

  /// No description provided for @contactsLocalAgencies.
  ///
  /// In en, this message translates to:
  /// **'LOCAL AGENCIES'**
  String get contactsLocalAgencies;

  /// No description provided for @contactsNoneListed.
  ///
  /// In en, this message translates to:
  /// **'No numbers listed yet. Use 911 or report through Ziren.'**
  String get contactsNoneListed;

  /// No description provided for @contactsHospitalsSection.
  ///
  /// In en, this message translates to:
  /// **'HOSPITALS & EVACUATION CENTERS'**
  String get contactsHospitalsSection;

  /// No description provided for @contactsFindOnMap.
  ///
  /// In en, this message translates to:
  /// **'Find on the Map'**
  String get contactsFindOnMap;

  /// No description provided for @contactsFindOnMapBody.
  ///
  /// In en, this message translates to:
  /// **'See the nearest station on the map.'**
  String get contactsFindOnMapBody;

  /// No description provided for @contactsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get contactsOpen;

  /// No description provided for @announcementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcementsTitle;

  /// No description provided for @announcementsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load announcements.'**
  String get announcementsLoadError;

  /// No description provided for @announcementsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get announcementsRetry;

  /// No description provided for @announcementsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No announcements right now'**
  String get announcementsEmptyTitle;

  /// No description provided for @announcementsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Official notices from Ziren will appear here.'**
  String get announcementsEmptyBody;

  /// No description provided for @announceCategoryMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get announceCategoryMaintenance;

  /// No description provided for @announceCategoryEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency Notice'**
  String get announceCategoryEmergency;

  /// No description provided for @announceCategoryServiceInterruption.
  ///
  /// In en, this message translates to:
  /// **'Service Interruption'**
  String get announceCategoryServiceInterruption;

  /// No description provided for @announceCategoryFeature.
  ///
  /// In en, this message translates to:
  /// **'New Feature'**
  String get announceCategoryFeature;

  /// No description provided for @announceCategoryReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get announceCategoryReminder;

  /// No description provided for @announceCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get announceCategoryGeneral;

  /// No description provided for @profileSafetySection.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get profileSafetySection;

  /// No description provided for @aiScreenBody.
  ///
  /// In en, this message translates to:
  /// **'This will help you build your report — asking what, where, and who was hurt, so the station receives complete information.'**
  String get aiScreenBody;

  /// No description provided for @aiNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t available yet'**
  String get aiNotAvailable;

  /// No description provided for @aiNotAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'While you wait, use the quick report on Home or SOS if you need immediate help.'**
  String get aiNotAvailableBody;

  /// No description provided for @voiceConfirmAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Your report has been sent'**
  String get voiceConfirmAppBarTitle;

  /// No description provided for @voiceConfirmSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get voiceConfirmSkip;

  /// No description provided for @voiceConfirmSaveError.
  ///
  /// In en, this message translates to:
  /// **'Your correction could not be saved. The report was still sent.'**
  String get voiceConfirmSaveError;

  /// No description provided for @voiceConfirmSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Your report has been sent.'**
  String get voiceConfirmSentTitle;

  /// No description provided for @voiceConfirmSentBodyStation.
  ///
  /// In en, this message translates to:
  /// **'The station can already hear this.'**
  String get voiceConfirmSentBodyStation;

  /// No description provided for @voiceConfirmSentBodyStationNamed.
  ///
  /// In en, this message translates to:
  /// **'{station} can already hear this.'**
  String voiceConfirmSentBodyStationNamed(String station);

  /// No description provided for @voiceConfirmGaveUpTitle.
  ///
  /// In en, this message translates to:
  /// **'The station will listen to your recording.'**
  String get voiceConfirmGaveUpTitle;

  /// No description provided for @voiceConfirmGaveUpBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t write down what you said right away, but they already have your actual voice.'**
  String get voiceConfirmGaveUpBody;

  /// No description provided for @voiceConfirmOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get voiceConfirmOk;

  /// No description provided for @voiceConfirmListeningTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re listening to your voice…'**
  String get voiceConfirmListeningTitle;

  /// No description provided for @voiceConfirmListeningBody.
  ///
  /// In en, this message translates to:
  /// **'Just a moment. We\'ll show you what we understood.'**
  String get voiceConfirmListeningBody;

  /// No description provided for @voiceConfirmEditTitle.
  ///
  /// In en, this message translates to:
  /// **'What did you actually say?'**
  String get voiceConfirmEditTitle;

  /// No description provided for @voiceConfirmBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get voiceConfirmBack;

  /// No description provided for @voiceConfirmSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get voiceConfirmSave;

  /// No description provided for @voiceConfirmHeardTitle.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what we heard:'**
  String get voiceConfirmHeardTitle;

  /// No description provided for @voiceConfirmWrongFix.
  ///
  /// In en, this message translates to:
  /// **'Wrong — fix it'**
  String get voiceConfirmWrongFix;

  /// No description provided for @voiceConfirmCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get voiceConfirmCorrect;

  /// No description provided for @feedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get feedbackThanks;

  /// No description provided for @feedbackClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get feedbackClose;

  /// No description provided for @feedbackHowWasIt.
  ///
  /// In en, this message translates to:
  /// **'How was your experience?'**
  String get feedbackHowWasIt;

  /// No description provided for @feedbackNoImpact.
  ///
  /// In en, this message translates to:
  /// **'This will not affect the priority of your next report.'**
  String get feedbackNoImpact;

  /// No description provided for @feedbackCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Additional comments (optional)…'**
  String get feedbackCommentHint;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get feedbackSubmit;

  /// No description provided for @feedbackMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get feedbackMaybeLater;

  /// No description provided for @threadTitle.
  ///
  /// In en, this message translates to:
  /// **'Report Updates'**
  String get threadTitle;

  /// No description provided for @threadLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load messages.'**
  String get threadLoadError;

  /// No description provided for @threadEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get threadEmptyTitle;

  /// No description provided for @threadEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Any extra details you add and the agency\'s replies will appear here.'**
  String get threadEmptyBody;

  /// No description provided for @threadComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Add a detail…'**
  String get threadComposerHint;

  /// No description provided for @threadClosedNotice.
  ///
  /// In en, this message translates to:
  /// **'This report is closed — no more messages can be added.'**
  String get threadClosedNotice;

  /// No description provided for @reportsAskConfirmVoice.
  ///
  /// In en, this message translates to:
  /// **'Did we hear this right?'**
  String get reportsAskConfirmVoice;

  /// No description provided for @reportsAlreadyRated.
  ///
  /// In en, this message translates to:
  /// **'You already rated this · {rating}/5'**
  String reportsAlreadyRated(String rating);

  /// No description provided for @reportsRateService.
  ///
  /// In en, this message translates to:
  /// **'Rate the Service'**
  String get reportsRateService;

  /// No description provided for @incidentStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get incidentStatusReceived;

  /// No description provided for @incidentStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get incidentStatusProcessing;

  /// No description provided for @incidentStatusDispatched.
  ///
  /// In en, this message translates to:
  /// **'Responder Dispatched'**
  String get incidentStatusDispatched;

  /// No description provided for @incidentStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get incidentStatusResolved;

  /// No description provided for @incidentStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get incidentStatusCancelled;

  /// No description provided for @incidentEtaMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {minutes} minutes'**
  String incidentEtaMinutes(int minutes);

  /// No description provided for @threadAuthorYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get threadAuthorYou;

  /// No description provided for @activeReportAgencyEnRoute.
  ///
  /// In en, this message translates to:
  /// **'{agency} is on the way — {eta}'**
  String activeReportAgencyEnRoute(String agency, String eta);

  /// No description provided for @activeReportResponderEnRoute.
  ///
  /// In en, this message translates to:
  /// **'A responder is on the way — {eta}'**
  String activeReportResponderEnRoute(String eta);

  /// No description provided for @activeReportNotFollowedUp.
  ///
  /// In en, this message translates to:
  /// **'This report was not followed up.'**
  String get activeReportNotFollowedUp;

  /// No description provided for @activeReportStale.
  ///
  /// In en, this message translates to:
  /// **'Waiting a long time. Tap to check.'**
  String get activeReportStale;

  /// No description provided for @activeReportStep.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String activeReportStep(int step, int total);

  /// No description provided for @readyPanelFalseReportWarning.
  ///
  /// In en, this message translates to:
  /// **'Filing a false report carries a penalty.'**
  String get readyPanelFalseReportWarning;

  /// No description provided for @reviewRecordVideo.
  ///
  /// In en, this message translates to:
  /// **'Record a video'**
  String get reviewRecordVideo;

  /// No description provided for @reviewChooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get reviewChooseFromGallery;

  /// No description provided for @reviewAttachmentsSection.
  ///
  /// In en, this message translates to:
  /// **'ATTACHMENTS'**
  String get reviewAttachmentsSection;

  /// No description provided for @reviewAddAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get reviewAddAttachment;

  /// No description provided for @reviewAttachmentsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — add a photo or video as evidence (max 5, 50MB each)'**
  String get reviewAttachmentsHint;

  /// No description provided for @sosAddDetailsExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"3 people trying to escape, fire on the ground floor, no more visible flames outside…\"'**
  String get sosAddDetailsExample;

  /// No description provided for @reportsAddInformation.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get reportsAddInformation;

  /// No description provided for @avatarSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Photo'**
  String get avatarSheetTitle;

  /// No description provided for @avatarRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get avatarRemovePhoto;

  /// No description provided for @avatarUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update your profile picture. Please try again.'**
  String get avatarUploadFailed;

  /// No description provided for @respDutyCardBusy.
  ///
  /// In en, this message translates to:
  /// **'Just a moment...'**
  String get respDutyCardBusy;

  /// No description provided for @respDutyCardOn.
  ///
  /// In en, this message translates to:
  /// **'Currently On-Duty'**
  String get respDutyCardOn;

  /// No description provided for @respDutyCardOff.
  ///
  /// In en, this message translates to:
  /// **'Off Duty'**
  String get respDutyCardOff;

  /// No description provided for @respDutyCardStation.
  ///
  /// In en, this message translates to:
  /// **'(Station: {station})'**
  String respDutyCardStation(String station);

  /// No description provided for @respDutyToggleOff.
  ///
  /// In en, this message translates to:
  /// **'Go off duty'**
  String get respDutyToggleOff;

  /// No description provided for @respDutyToggleOn.
  ///
  /// In en, this message translates to:
  /// **'Go on duty'**
  String get respDutyToggleOn;

  /// Status badge for a report the agency reviewed and did not accept. Distinct from Cancelled, which is a report the resident withdrew.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// Badge on a report the agency has asked the resident a question about.
  ///
  /// In en, this message translates to:
  /// **'Needs your reply'**
  String get statusNeedsReply;

  /// No description provided for @reportRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'The agency did not accept this report'**
  String get reportRejectedTitle;

  /// The reason the agency gave for rejecting the report.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reportRejectedReason(String reason);

  /// No description provided for @reportRejectedHelp.
  ///
  /// In en, this message translates to:
  /// **'If this is a real emergency, call the station now, or send a new report with more detail.'**
  String get reportRejectedHelp;

  /// No description provided for @reportRejectedCall.
  ///
  /// In en, this message translates to:
  /// **'Call emergency contacts'**
  String get reportRejectedCall;

  /// No description provided for @reportFileAgain.
  ///
  /// In en, this message translates to:
  /// **'Send a new report'**
  String get reportFileAgain;

  /// No description provided for @clarificationTitle.
  ///
  /// In en, this message translates to:
  /// **'The agency needs more information'**
  String get clarificationTitle;

  /// No description provided for @clarificationAsked.
  ///
  /// In en, this message translates to:
  /// **'They asked:'**
  String get clarificationAsked;

  /// No description provided for @clarificationReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get clarificationReply;

  /// No description provided for @clarificationReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Answer here. The agency is waiting on your reply before it decides what to do.'**
  String get clarificationReplyHint;

  /// No description provided for @notifRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Report not accepted'**
  String get notifRejectedTitle;

  /// No description provided for @notifClarificationTitle.
  ///
  /// In en, this message translates to:
  /// **'The agency needs more information'**
  String get notifClarificationTitle;

  /// No description provided for @notifViewReport.
  ///
  /// In en, this message translates to:
  /// **'View report'**
  String get notifViewReport;

  /// No description provided for @notifReplyNow.
  ///
  /// In en, this message translates to:
  /// **'Reply now'**
  String get notifReplyNow;

  /// No description provided for @idCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'We can\'t accept this photo yet'**
  String get idCheckTitle;

  /// No description provided for @idCheckNoText.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t read any text on it. Take the photo in good light, flat, with the whole card in frame.'**
  String get idCheckNoText;

  /// No description provided for @idCheckNotAnIdTitle.
  ///
  /// In en, this message translates to:
  /// **'We will not accept this — it is not an ID'**
  String get idCheckNotAnIdTitle;

  /// Shown when the photographed thing is not an ID at all (a selfie, a wall, a screenshot).
  ///
  /// In en, this message translates to:
  /// **'We can\'t accept this photo because it is not an ID. Please upload again and make sure it is a photo of your {chosen} — the card itself, not your face or another picture.'**
  String idCheckNotAnId(String chosen);

  /// No description provided for @idCheckWrongTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'This is not a {chosen}'**
  String idCheckWrongTypeTitle(String chosen);

  /// Shown when the photo is a real ID of a different type than the one chosen.
  ///
  /// In en, this message translates to:
  /// **'We can\'t accept this. You chose {chosen}, but this photo looks like a {found}. Upload your {chosen} instead — or go back and choose the ID type that matches your card.'**
  String idCheckWrongType(String chosen, String found);

  /// No description provided for @idCheckTypeUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'We can\'t confirm that this is a {chosen}. Take a clear photo of the FRONT of your {chosen}, flat and in good light, with the printed words readable.'**
  String idCheckTypeUnconfirmed(String chosen);

  /// No description provided for @idCheckNoFace.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find your photo on the card. Use the FRONT of your ID.'**
  String get idCheckNoFace;

  /// No description provided for @idCheckNoNumber.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find an ID number on it. Make sure the number is sharp and not covered by glare.'**
  String get idCheckNoNumber;

  /// No description provided for @idCheckNumberMismatch.
  ///
  /// In en, this message translates to:
  /// **'The number you typed is not the one on your ID photo. Fix it, or retake the photo.'**
  String get idCheckNumberMismatch;

  /// No description provided for @idCheckRetakeHint.
  ///
  /// In en, this message translates to:
  /// **'Retake the photo, or skip verification and do it later from Settings.'**
  String get idCheckRetakeHint;

  /// No description provided for @idCheckRetakeOnly.
  ///
  /// In en, this message translates to:
  /// **'Retake the photo to continue.'**
  String get idCheckRetakeOnly;

  /// No description provided for @idCheckPassed.
  ///
  /// In en, this message translates to:
  /// **'ID photo accepted'**
  String get idCheckPassed;

  /// No description provided for @idCheckChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your photo…'**
  String get idCheckChecking;

  /// Shown after Use my location fills in both the municipality and the barangay.
  ///
  /// In en, this message translates to:
  /// **'Found your barangay: {barangay}, {municipality}. Check that it is right.'**
  String regLocationBarangaySet(String barangay, String municipality);

  /// No description provided for @regLocationBarangayNear.
  ///
  /// In en, this message translates to:
  /// **'Closest barangay: {barangay}, {municipality}. We are not sure, so please confirm or change it.'**
  String regLocationBarangayNear(String barangay, String municipality);

  /// No description provided for @regLocationMunicipalityOnly.
  ///
  /// In en, this message translates to:
  /// **'Found {municipality}, but could not tell your barangay. Please choose it below.'**
  String regLocationMunicipalityOnly(String municipality);

  /// The shutter button on the selfie step.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get selfieCapture;

  /// No description provided for @selfieCapturing.
  ///
  /// In en, this message translates to:
  /// **'Taking photo…'**
  String get selfieCapturing;

  /// Status label: the responder has reached the resident's location.
  ///
  /// In en, this message translates to:
  /// **'Responder arrived'**
  String get statusArrived;

  /// Status badge for a report the AGENCY cancelled (not one the resident trashed, and not one it rejected).
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the agency'**
  String get statusCancelledByAgency;

  /// No description provided for @notifAcceptedTitle.
  ///
  /// In en, this message translates to:
  /// **'Report accepted'**
  String get notifAcceptedTitle;

  /// No description provided for @notifAcceptedBody.
  ///
  /// In en, this message translates to:
  /// **'The agency confirmed your report is real and is preparing a response.'**
  String get notifAcceptedBody;

  /// No description provided for @notifEnRouteBody.
  ///
  /// In en, this message translates to:
  /// **'The responder is heading to your location now.'**
  String get notifEnRouteBody;

  /// No description provided for @notifArrivedBody.
  ///
  /// In en, this message translates to:
  /// **'The responder has arrived at your location.'**
  String get notifArrivedBody;

  /// No description provided for @notifResolvedHelp.
  ///
  /// In en, this message translates to:
  /// **'You can rate the response from My Reports.'**
  String get notifResolvedHelp;

  /// No description provided for @notifCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Report cancelled by the agency'**
  String get notifCancelledTitle;

  /// No description provided for @notifCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'The agency cancelled your report.'**
  String get notifCancelledBody;

  /// Why the agency cancelled the report.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String notifCancelledReason(String reason);

  /// No description provided for @notifCancelledHelp.
  ///
  /// In en, this message translates to:
  /// **'If you still need help, call the station or send a new report.'**
  String get notifCancelledHelp;

  /// No description provided for @notifMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'New message from the agency'**
  String get notifMessageTitle;

  /// No description provided for @notifMessageHelp.
  ///
  /// In en, this message translates to:
  /// **'Reply in the chat on this report.'**
  String get notifMessageHelp;

  /// No description provided for @notifOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get notifOpenChat;

  /// No description provided for @notifMessageFromResponder.
  ///
  /// In en, this message translates to:
  /// **'New message from the responder'**
  String get notifMessageFromResponder;

  /// No description provided for @notifFeedTitleAccepted.
  ///
  /// In en, this message translates to:
  /// **'Report accepted'**
  String get notifFeedTitleAccepted;

  /// No description provided for @notifFeedTitleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Report cancelled'**
  String get notifFeedTitleCancelled;

  /// No description provided for @notifFeedTitleMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get notifFeedTitleMessage;

  /// No description provided for @respEnRouteDone.
  ///
  /// In en, this message translates to:
  /// **'You are marked en route. The dispatcher and the resident can see it.'**
  String get respEnRouteDone;

  /// No description provided for @respArrivedDone.
  ///
  /// In en, this message translates to:
  /// **'You are marked on scene. The dispatcher and the resident can see it.'**
  String get respArrivedDone;

  /// No description provided for @settingsProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Your profile was saved.'**
  String get settingsProfileSaved;

  /// No description provided for @welcomeResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue where you left off?'**
  String get welcomeResumeTitle;

  /// No description provided for @welcomeResumeBody.
  ///
  /// In en, this message translates to:
  /// **'You started creating an account on this phone but did not finish.'**
  String get welcomeResumeBody;

  /// No description provided for @welcomeResumeContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get welcomeResumeContinue;

  /// No description provided for @welcomeResumeStartOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get welcomeResumeStartOver;

  /// No description provided for @respActiveAssignmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Active Assignment'**
  String get respActiveAssignmentTitle;

  /// No description provided for @respActiveAssignmentBody.
  ///
  /// In en, this message translates to:
  /// **'You currently have an active incident assignment. Signing out may prevent you from receiving important updates.'**
  String get respActiveAssignmentBody;

  /// No description provided for @respStaySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Stay Signed In'**
  String get respStaySignedIn;

  /// Home screen: section heading for undispatched incidents near this on-duty responder.
  ///
  /// In en, this message translates to:
  /// **'Incidents near you'**
  String get respNearbyTitle;

  /// Home screen: explains that answering does not assign the call.
  ///
  /// In en, this message translates to:
  /// **'Nobody has been sent yet. You can say whether you\'re able to go — the dispatcher decides who responds.'**
  String get respNearbySubtitle;

  /// No description provided for @respNearbyDistanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Distance unknown'**
  String get respNearbyDistanceUnknown;

  /// Shown on a nearby-incident card when this responder is busy with another call.
  ///
  /// In en, this message translates to:
  /// **'You are already on {category}'**
  String respNearbyAlreadyOn(String category);

  /// No description provided for @respNearbyNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get respNearbyNotAvailable;

  /// No description provided for @respNearbyCanRespond.
  ///
  /// In en, this message translates to:
  /// **'I can respond'**
  String get respNearbyCanRespond;

  /// No description provided for @respNearbyAnsweredYes.
  ///
  /// In en, this message translates to:
  /// **'You said you can respond'**
  String get respNearbyAnsweredYes;

  /// No description provided for @respNearbyAnsweredNo.
  ///
  /// In en, this message translates to:
  /// **'You said you are not available'**
  String get respNearbyAnsweredNo;

  /// No description provided for @respNearbySosChip.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get respNearbySosChip;

  /// No description provided for @hotlinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency hotlines'**
  String get hotlinesTitle;

  /// Title of the hotlines sheet opened from a category tile.
  ///
  /// In en, this message translates to:
  /// **'Hotlines for {category}'**
  String hotlinesForCategory(String category);

  /// No description provided for @hotlinesSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap a number to open your phone\'s dialer. The nearest town is listed first.'**
  String get hotlinesSheetSubtitle;

  /// No description provided for @hotlinesOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'No internet — call a station directly'**
  String get hotlinesOfflineTitle;

  /// No description provided for @hotlinesOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Your report can\'t be sent right now. A regular call still works with just a phone signal.'**
  String get hotlinesOfflineBody;

  /// No description provided for @hotlinesNearest.
  ///
  /// In en, this message translates to:
  /// **'Nearest'**
  String get hotlinesNearest;

  /// No description provided for @hotlinesCallNow.
  ///
  /// In en, this message translates to:
  /// **'Call now'**
  String get hotlinesCallNow;

  /// No description provided for @hotlinesCallSemantics.
  ///
  /// In en, this message translates to:
  /// **'Call {number}'**
  String hotlinesCallSemantics(String number);

  /// No description provided for @hotlinesCallFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the dialer. Dial {number} yourself.'**
  String hotlinesCallFailed(String number);

  /// No description provided for @hotlinesNational.
  ///
  /// In en, this message translates to:
  /// **'National Emergency Hotline'**
  String get hotlinesNational;

  /// No description provided for @hotlinesNationalScope.
  ///
  /// In en, this message translates to:
  /// **'Anywhere in the Philippines'**
  String get hotlinesNationalScope;

  /// No description provided for @hotlinesRhu.
  ///
  /// In en, this message translates to:
  /// **'Rural Health Unit'**
  String get hotlinesRhu;

  /// No description provided for @hotlinesSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all station hotlines'**
  String get hotlinesSeeAll;

  /// No description provided for @hotlinesScreenIntro.
  ///
  /// In en, this message translates to:
  /// **'Official numbers of every BFP, PNP and MDRRMO station in Biliran. They work without internet — only a phone signal is needed.'**
  String get hotlinesScreenIntro;

  /// No description provided for @hotlinesFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get hotlinesFilterAll;

  /// No description provided for @hotlinesHomeCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Station hotlines'**
  String get hotlinesHomeCardTitle;

  /// No description provided for @hotlinesHomeCardBody.
  ///
  /// In en, this message translates to:
  /// **'Call BFP, PNP or MDRRMO directly — works even without internet.'**
  String get hotlinesHomeCardBody;

  /// No description provided for @hotlinesCallInstead.
  ///
  /// In en, this message translates to:
  /// **'Call a station instead'**
  String get hotlinesCallInstead;

  /// No description provided for @hotlinesStationCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get hotlinesStationCall;

  /// No description provided for @homeOfflineCallHint.
  ///
  /// In en, this message translates to:
  /// **'No internet. Tap a category below to see the station numbers to call.'**
  String get homeOfflineCallHint;

  /// No description provided for @locWhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Where is the incident?'**
  String get locWhereTitle;

  /// No description provided for @locHere.
  ///
  /// In en, this message translates to:
  /// **'I\'m at the incident'**
  String get locHere;

  /// No description provided for @locElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Somewhere else'**
  String get locElsewhere;

  /// No description provided for @locPickedPoint.
  ///
  /// In en, this message translates to:
  /// **'Location placed on the map'**
  String get locPickedPoint;

  /// No description provided for @locElsewhereNote.
  ///
  /// In en, this message translates to:
  /// **'The station will be told you are reporting from somewhere else.'**
  String get locElsewhereNote;

  /// Shown under a location the resident placed on the map; {place} is where their phone is.
  ///
  /// In en, this message translates to:
  /// **'The station will be told you are reporting from {place}.'**
  String locElsewhereNoteFrom(String place);

  /// No description provided for @locChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get locChange;

  /// No description provided for @locRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh location'**
  String get locRefresh;

  /// No description provided for @locDeniedPickHint.
  ///
  /// In en, this message translates to:
  /// **'No GPS? Choose \"Somewhere else\" and place the incident on the map.'**
  String get locDeniedPickHint;

  /// No description provided for @locLandmarkRequired.
  ///
  /// In en, this message translates to:
  /// **'Landmark (required)'**
  String get locLandmarkRequired;

  /// No description provided for @locLandmarkMissing.
  ///
  /// In en, this message translates to:
  /// **'Add a landmark so the responders can find the place.'**
  String get locLandmarkMissing;

  /// No description provided for @locLandmarkAutoFilled.
  ///
  /// In en, this message translates to:
  /// **'Filled in from the nearest landmark on the map — check that it is right.'**
  String get locLandmarkAutoFilled;

  /// No description provided for @locPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Where is the incident?'**
  String get locPickTitle;

  /// No description provided for @locPickHint.
  ///
  /// In en, this message translates to:
  /// **'Move the map until the pin is on the incident, or search a barangay or landmark.'**
  String get locPickHint;

  /// No description provided for @locPickConfirm.
  ///
  /// In en, this message translates to:
  /// **'Use this location'**
  String get locPickConfirm;

  /// No description provided for @locSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search barangay or landmark'**
  String get locSearchHint;

  /// No description provided for @locSearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get locSearchClear;

  /// No description provided for @locKindLandmark.
  ///
  /// In en, this message translates to:
  /// **'Landmark'**
  String get locKindLandmark;

  /// No description provided for @locKindPlace.
  ///
  /// In en, this message translates to:
  /// **'Barangay / place'**
  String get locKindPlace;

  /// No description provided for @locNearLandmark.
  ///
  /// In en, this message translates to:
  /// **'Near {landmark}'**
  String locNearLandmark(String landmark);

  /// No description provided for @locReviewReporterLabel.
  ///
  /// In en, this message translates to:
  /// **'You are reporting from'**
  String get locReviewReporterLabel;

  /// No description provided for @locReviewReporterUnknown.
  ///
  /// In en, this message translates to:
  /// **'Your location is unknown'**
  String get locReviewReporterUnknown;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'How to use Ziren'**
  String get helpTitle;

  /// No description provided for @helpIntroResident.
  ///
  /// In en, this message translates to:
  /// **'Short guides to the things you will do in Ziren. Tap a topic to open its steps.'**
  String get helpIntroResident;

  /// No description provided for @helpIntroResponder.
  ///
  /// In en, this message translates to:
  /// **'Short guides for responders: duty, assignments, status updates and your own safety. Tap a topic to open its steps.'**
  String get helpIntroResponder;

  /// No description provided for @helpStillStuck.
  ///
  /// In en, this message translates to:
  /// **'Still need help? Call your station'**
  String get helpStillStuck;

  /// No description provided for @helpHomeLink.
  ///
  /// In en, this message translates to:
  /// **'How to use Ziren?'**
  String get helpHomeLink;

  /// The mascot introducing itself above its message on Home; typed out letter by letter on a loop.
  ///
  /// In en, this message translates to:
  /// **'Hi! I\'m Ziren'**
  String get mascotName;

  /// No description provided for @mascotResidentIntro.
  ///
  /// In en, this message translates to:
  /// **'{name}, in an emergency, tap the big button below and I\'ll get your report to the nearest station.'**
  String mascotResidentIntro(String name);

  /// No description provided for @mascotResidentOpen.
  ///
  /// In en, this message translates to:
  /// **'{count} of your reports are still being handled. I\'m right here with you, {name}.'**
  String mascotResidentOpen(String count, String name);

  /// No description provided for @mascotResidentThanks.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent {count} reports so far. Thank you for looking out for your community, {name}!'**
  String mascotResidentThanks(String count, String name);

  /// No description provided for @mascotResidentOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline right now. Tap an emergency type below to see the station numbers you can call.'**
  String get mascotResidentOffline;

  /// No description provided for @mascotResponderOffDuty.
  ///
  /// In en, this message translates to:
  /// **'You\'re off duty, {name}. Turn on Duty Status below to receive dispatches.'**
  String mascotResponderOffDuty(String name);

  /// No description provided for @mascotResponderQueue.
  ///
  /// In en, this message translates to:
  /// **'You have {count} assigned incidents, {critical} critical. Stay safe out there, {name}!'**
  String mascotResponderQueue(String count, String critical, String name);

  /// No description provided for @mascotResponderReady.
  ///
  /// In en, this message translates to:
  /// **'You\'re on duty and ready, {name}. Nothing is assigned to you right now.'**
  String mascotResponderReady(String name);

  /// Label beside the floating Ziren help button on Home (also its screen-reader name); opens How to use Ziren.
  ///
  /// In en, this message translates to:
  /// **'Ask Ziren for help'**
  String get helpButtonLabel;

  /// No description provided for @helpSheetClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get helpSheetClose;

  /// No description provided for @homeProfileButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Open your profile'**
  String get homeProfileButtonLabel;

  /// Status chip: dispatched to this responder, not yet answered.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get respStatusNew;

  /// No description provided for @respStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get respStatusAccepted;

  /// No description provided for @respStatusEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get respStatusEnRoute;

  /// No description provided for @respStatusOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get respStatusOnScene;

  /// No description provided for @respStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get respStatusResolved;

  /// No description provided for @respStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get respStatusCancelled;

  /// No description provided for @respStepAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get respStepAssigned;

  /// No description provided for @respDutyOnTitle.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get respDutyOnTitle;

  /// No description provided for @respDutyOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Off duty'**
  String get respDutyOffTitle;

  /// No description provided for @respDutyOnBody.
  ///
  /// In en, this message translates to:
  /// **'Receiving dispatches · {station}'**
  String respDutyOnBody(String station);

  /// No description provided for @respDutyOnBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Receiving dispatches'**
  String get respDutyOnBodyPlain;

  /// No description provided for @respDutyOffBody.
  ///
  /// In en, this message translates to:
  /// **'You will not receive dispatches. Turn it on to start your shift.'**
  String get respDutyOffBody;

  /// No description provided for @respNextUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Do this first'**
  String get respNextUpTitle;

  /// No description provided for @respNextUpCount.
  ///
  /// In en, this message translates to:
  /// **'1 of {count}'**
  String respNextUpCount(String count);

  /// No description provided for @respOtherAssignments.
  ///
  /// In en, this message translates to:
  /// **'Other assignments ({count})'**
  String respOtherAssignments(String count);

  /// No description provided for @respOpenAssignment.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get respOpenAssignment;

  /// No description provided for @respAnswerNow.
  ///
  /// In en, this message translates to:
  /// **'Answer now'**
  String get respAnswerNow;

  /// No description provided for @respWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting {time}'**
  String respWaitingFor(String time);

  /// No description provided for @respAssignedAgo.
  ///
  /// In en, this message translates to:
  /// **'Assigned {time} ago'**
  String respAssignedAgo(String time);

  /// No description provided for @respClosedAgo.
  ///
  /// In en, this message translates to:
  /// **'Closed {time} ago'**
  String respClosedAgo(String time);

  /// No description provided for @respReportedAgo.
  ///
  /// In en, this message translates to:
  /// **'Reported {time} ago'**
  String respReportedAgo(String time);

  /// No description provided for @respRecentClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently closed'**
  String get respRecentClosedTitle;

  /// No description provided for @respNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No location'**
  String get respNoLocation;

  /// No description provided for @respReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get respReportsTitle;

  /// No description provided for @respReportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything a dispatcher has sent you.'**
  String get respReportsSubtitle;

  /// No description provided for @respViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get respViewList;

  /// No description provided for @respViewRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get respViewRecord;

  /// No description provided for @respFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get respFilterAll;

  /// No description provided for @respFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get respFilterOpen;

  /// No description provided for @respFilterClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get respFilterClosed;

  /// No description provided for @respSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search barangay, INC or words'**
  String get respSearchHint;

  /// No description provided for @respSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\".'**
  String respSearchEmpty(String query);

  /// No description provided for @respSectionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open, needs you ({count})'**
  String respSectionOpen(String count);

  /// No description provided for @respSectionThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Closed this week'**
  String get respSectionThisWeek;

  /// No description provided for @respSectionLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Closed last week'**
  String get respSectionLastWeek;

  /// No description provided for @respSectionOlder.
  ///
  /// In en, this message translates to:
  /// **'Closed earlier'**
  String get respSectionOlder;

  /// No description provided for @respHistoryCapNote.
  ///
  /// In en, this message translates to:
  /// **'Showing your 50 most recent closed incidents.'**
  String get respHistoryCapNote;

  /// No description provided for @respEmptyOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing open'**
  String get respEmptyOpenTitle;

  /// No description provided for @respEmptyOpenBody.
  ///
  /// In en, this message translates to:
  /// **'No assignment is waiting on you right now.'**
  String get respEmptyOpenBody;

  /// No description provided for @respEmptyClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing closed yet'**
  String get respEmptyClosedTitle;

  /// No description provided for @respEmptyClosedBody.
  ///
  /// In en, this message translates to:
  /// **'Incidents you finish will be filed here.'**
  String get respEmptyClosedBody;

  /// No description provided for @respEmptyAllTitle.
  ///
  /// In en, this message translates to:
  /// **'No reports yet'**
  String get respEmptyAllTitle;

  /// No description provided for @respEmptyAllBody.
  ///
  /// In en, this message translates to:
  /// **'Anything a dispatcher sends you will appear here, open or closed.'**
  String get respEmptyAllBody;

  /// No description provided for @respRecTotalClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed in total'**
  String get respRecTotalClosed;

  /// No description provided for @respRecThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Closed this week'**
  String get respRecThisWeek;

  /// No description provided for @respRecCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical handled'**
  String get respRecCritical;

  /// No description provided for @respRecTypical.
  ///
  /// In en, this message translates to:
  /// **'Typical response'**
  String get respRecTypical;

  /// No description provided for @respRecChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Closed incidents'**
  String get respRecChartTitle;

  /// No description provided for @respRec7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get respRec7Days;

  /// No description provided for @respRec8Weeks.
  ///
  /// In en, this message translates to:
  /// **'8 weeks'**
  String get respRec8Weeks;

  /// No description provided for @respRecNoneInRange.
  ///
  /// In en, this message translates to:
  /// **'None closed in this period. Your last one was closed {time} ago.'**
  String respRecNoneInRange(String time);

  /// No description provided for @respRecNoneEver.
  ///
  /// In en, this message translates to:
  /// **'None closed in this period.'**
  String get respRecNoneEver;

  /// No description provided for @respRecMixTitle.
  ///
  /// In en, this message translates to:
  /// **'Severity of what you closed'**
  String get respRecMixTitle;

  /// No description provided for @respRecCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Types of incident'**
  String get respRecCategoryTitle;

  /// No description provided for @respRecTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} total'**
  String respRecTotal(String count);

  /// No description provided for @respRecReports.
  ///
  /// In en, this message translates to:
  /// **'reports'**
  String get respRecReports;

  /// No description provided for @respRecEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show yet'**
  String get respRecEmptyTitle;

  /// No description provided for @respRecEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Close your first incident and your record will show up here.'**
  String get respRecEmptyBody;

  /// No description provided for @respRecTruncated.
  ///
  /// In en, this message translates to:
  /// **'Your history is capped at 50 incidents, so the earliest part of this chart may be undercounted.'**
  String get respRecTruncated;

  /// Short axis label prefix for a week bar.
  ///
  /// In en, this message translates to:
  /// **'wk'**
  String get respRecWeekOf;

  /// No description provided for @respStepsTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get respStepsTitle;

  /// No description provided for @respNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get respNextStep;

  /// No description provided for @respCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get respCall;

  /// No description provided for @respCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get respCopy;

  /// No description provided for @respGpsCopied.
  ///
  /// In en, this message translates to:
  /// **'Coordinates copied.'**
  String get respGpsCopied;

  /// No description provided for @respVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get respVerified;

  /// No description provided for @respUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get respUnverified;

  /// No description provided for @respReporterUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown reporter'**
  String get respReporterUnknown;

  /// No description provided for @respCardReport.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get respCardReport;

  /// No description provided for @respCardLocation.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get respCardLocation;

  /// No description provided for @respCardReporter.
  ///
  /// In en, this message translates to:
  /// **'Who reported'**
  String get respCardReporter;

  /// No description provided for @respCardStation.
  ///
  /// In en, this message translates to:
  /// **'Your station'**
  String get respCardStation;

  /// No description provided for @respClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'This incident is closed. Nothing else to do here.'**
  String get respClosedBanner;

  /// No description provided for @respEmergencyContactShort.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get respEmergencyContactShort;

  /// Profile header chip: the resident's identity is verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileChipVerified;

  /// Profile header chip: verification submitted, being reviewed.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get profileChipInReview;

  /// Profile header chip: verification not started.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get profileChipNotVerified;

  /// Profile section: hotlines, help guide, safety guide, announcements.
  ///
  /// In en, this message translates to:
  /// **'Safety & help'**
  String get profileSafetyHelp;

  /// Responder profile row: the station's own phone number.
  ///
  /// In en, this message translates to:
  /// **'Station contact'**
  String get profileStationContact;

  /// Responder profile section: agency, municipality, station contact.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get profileStationSection;

  /// Profile row that opens Settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// Sheet title: pick which of the station's numbers to call.
  ///
  /// In en, this message translates to:
  /// **'Call the station'**
  String get profileCallStation;

  /// Settings: line under the name on the account card.
  ///
  /// In en, this message translates to:
  /// **'View and edit your details'**
  String get settingsAccountCardHint;

  /// No description provided for @settingsNotifDesc.
  ///
  /// In en, this message translates to:
  /// **'Updates on your reports and alerts'**
  String get settingsNotifDesc;

  /// No description provided for @settingsLocationDesc.
  ///
  /// In en, this message translates to:
  /// **'Sends your location with a report'**
  String get settingsLocationDesc;

  /// No description provided for @settingsReduceMotionDesc.
  ///
  /// In en, this message translates to:
  /// **'Fewer moving animations'**
  String get settingsReduceMotionDesc;

  /// No description provided for @settingsHighContrastDesc.
  ///
  /// In en, this message translates to:
  /// **'Stronger text and borders'**
  String get settingsHighContrastDesc;

  /// No description provided for @settingsSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get settingsSaveChanges;

  /// No description provided for @settingsDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get settingsDiscardTitle;

  /// No description provided for @settingsDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'You have edits that are not saved yet.'**
  String get settingsDiscardBody;

  /// No description provided for @settingsDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get settingsDiscard;

  /// No description provided for @settingsKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get settingsKeepEditing;

  /// No description provided for @settingsEditorIntro.
  ///
  /// In en, this message translates to:
  /// **'Stations see these details when you send a report.'**
  String get settingsEditorIntro;

  /// No description provided for @cpIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password, then choose a new one.'**
  String get cpIntro;

  /// No description provided for @cpCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get cpCurrent;

  /// No description provided for @cpNew.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get cpNew;

  /// No description provided for @cpConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get cpConfirm;

  /// No description provided for @cpEnterCurrent.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password.'**
  String get cpEnterCurrent;

  /// No description provided for @cpMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two new passwords do not match.'**
  String get cpMismatch;

  /// No description provided for @cpSameAsOld.
  ///
  /// In en, this message translates to:
  /// **'Your new password must be different from your current one.'**
  String get cpSameAsOld;

  /// No description provided for @cpWrongCurrent.
  ///
  /// In en, this message translates to:
  /// **'Your current password is not correct.'**
  String get cpWrongCurrent;

  /// No description provided for @cpFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change your password. Check your connection and try again.'**
  String get cpFailed;

  /// No description provided for @cpDone.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed.'**
  String get cpDone;

  /// No description provided for @cpForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot your current password?'**
  String get cpForgot;

  /// No description provided for @faqIntro.
  ///
  /// In en, this message translates to:
  /// **'Quick answers to common questions.'**
  String get faqIntro;

  /// No description provided for @faqStillNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Still need help?'**
  String get faqStillNeedHelp;

  /// No description provided for @settingsFaqLandmarkQ.
  ///
  /// In en, this message translates to:
  /// **'Why is a landmark required?'**
  String get settingsFaqLandmarkQ;

  /// No description provided for @settingsFaqLandmarkA.
  ///
  /// In en, this message translates to:
  /// **'GPS can be off by tens of metres. A landmark (a store, a chapel, a court) lets the responder find the place fast. Ziren fills in the nearest one for you; correct it if it is wrong.'**
  String get settingsFaqLandmarkA;

  /// No description provided for @settingsFaqElsewhereQ.
  ///
  /// In en, this message translates to:
  /// **'The emergency is not where I am. What do I do?'**
  String get settingsFaqElsewhereQ;

  /// No description provided for @settingsFaqElsewhereA.
  ///
  /// In en, this message translates to:
  /// **'In the report, choose \"Somewhere else\" and move the map pin to where the incident is. Responders go to the pin, not to you, and the station is told you are reporting from elsewhere.'**
  String get settingsFaqElsewhereA;

  /// No description provided for @settingsFaqTrackQ.
  ///
  /// In en, this message translates to:
  /// **'How do I know help is coming?'**
  String get settingsFaqTrackQ;

  /// No description provided for @settingsFaqTrackA.
  ///
  /// In en, this message translates to:
  /// **'Open My Reports. Each report shows how far it has gone — received, dispatched, on the way, on scene, resolved — and you get a notification each time it changes.'**
  String get settingsFaqTrackA;

  /// No description provided for @settingsFaqVerifyQ.
  ///
  /// In en, this message translates to:
  /// **'Do I have to verify my account?'**
  String get settingsFaqVerifyQ;

  /// No description provided for @settingsFaqVerifyA.
  ///
  /// In en, this message translates to:
  /// **'No, it is optional. A verified account (a photo of a valid ID) helps stations trust your reports faster.'**
  String get settingsFaqVerifyA;

  /// No description provided for @safetyGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'What to do before help arrives. Works without internet.'**
  String get safetyGuideIntro;

  /// No description provided for @safetyGuideSteps.
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String safetyGuideSteps(String count);

  /// No description provided for @safetyGuideCallHotline.
  ///
  /// In en, this message translates to:
  /// **'Call a hotline'**
  String get safetyGuideCallHotline;

  /// No description provided for @aboutAgencies.
  ///
  /// In en, this message translates to:
  /// **'Connects residents with the BFP, PNP and MDRRMO stations of Biliran.'**
  String get aboutAgencies;

  /// No description provided for @sosWhereSection.
  ///
  /// In en, this message translates to:
  /// **'Where you are (auto-detected)'**
  String get sosWhereSection;

  /// No description provided for @sosLandmarkFinding.
  ///
  /// In en, this message translates to:
  /// **'Finding the nearest landmark…'**
  String get sosLandmarkFinding;

  /// No description provided for @sosLandmarkNear.
  ///
  /// In en, this message translates to:
  /// **'Near {landmark}'**
  String sosLandmarkNear(String landmark);

  /// No description provided for @sosLandmarkAuto.
  ///
  /// In en, this message translates to:
  /// **'Nearest landmark on the map · tap to change'**
  String get sosLandmarkAuto;

  /// No description provided for @sosLandmarkTyped.
  ///
  /// In en, this message translates to:
  /// **'Landmark you added · tap to change'**
  String get sosLandmarkTyped;

  /// No description provided for @sosLandmarkNone.
  ///
  /// In en, this message translates to:
  /// **'No landmark found nearby'**
  String get sosLandmarkNone;

  /// No description provided for @sosLandmarkNoneHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to add one — optional'**
  String get sosLandmarkNoneHint;

  /// No description provided for @sosLandmarkEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Landmark near you'**
  String get sosLandmarkEditTitle;

  /// No description provided for @sosLandmarkEditBody.
  ///
  /// In en, this message translates to:
  /// **'What can the responders look for? Leave it empty to use the one found on the map.'**
  String get sosLandmarkEditBody;

  /// No description provided for @sosLandmarkEditHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. beside the barangay hall'**
  String get sosLandmarkEditHint;

  /// No description provided for @sosLandmarkEditSave.
  ///
  /// In en, this message translates to:
  /// **'Use this'**
  String get sosLandmarkEditSave;

  /// No description provided for @sosLandmarkEditCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sosLandmarkEditCancel;

  /// No description provided for @mapStationsOnMap.
  ///
  /// In en, this message translates to:
  /// **'Stations on the map: {count}'**
  String mapStationsOnMap(String count);

  /// No description provided for @mapRecenter.
  ///
  /// In en, this message translates to:
  /// **'Go to my location'**
  String get mapRecenter;

  /// No description provided for @mapNearestStation.
  ///
  /// In en, this message translates to:
  /// **'Nearest station'**
  String get mapNearestStation;

  /// No description provided for @mapSelectedStation.
  ///
  /// In en, this message translates to:
  /// **'Selected station'**
  String get mapSelectedStation;

  /// No description provided for @mapOtherStations.
  ///
  /// In en, this message translates to:
  /// **'Other stations ({count})'**
  String mapOtherStations(String count);

  /// No description provided for @stageShortReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get stageShortReceived;

  /// No description provided for @stageShortChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get stageShortChecking;

  /// No description provided for @stageShortOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get stageShortOnTheWay;

  /// No description provided for @stageShortResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get stageShortResolved;

  /// No description provided for @reportSentAt.
  ///
  /// In en, this message translates to:
  /// **'Sent {when}'**
  String reportSentAt(String when);

  /// No description provided for @reportSectionYourReport.
  ///
  /// In en, this message translates to:
  /// **'What you reported'**
  String get reportSectionYourReport;

  /// No description provided for @reportSectionProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get reportSectionProgress;

  /// No description provided for @reportSectionLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get reportSectionLocation;

  /// No description provided for @reportSectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get reportSectionDetails;

  /// No description provided for @reportFactId.
  ///
  /// In en, this message translates to:
  /// **'Report number'**
  String get reportFactId;

  /// No description provided for @reportFactVia.
  ///
  /// In en, this message translates to:
  /// **'Sent through'**
  String get reportFactVia;

  /// No description provided for @reportFactAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get reportFactAddress;

  /// No description provided for @reportFactDistance.
  ///
  /// In en, this message translates to:
  /// **'From where you are now'**
  String get reportFactDistance;

  /// No description provided for @reportDistanceKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km away'**
  String reportDistanceKm(String km);

  /// No description provided for @reportViaApp.
  ///
  /// In en, this message translates to:
  /// **'Ziren app'**
  String get reportViaApp;

  /// No description provided for @reportViaSos.
  ///
  /// In en, this message translates to:
  /// **'Emergency SOS'**
  String get reportViaSos;

  /// No description provided for @reportViaSms.
  ///
  /// In en, this message translates to:
  /// **'Text message (SMS)'**
  String get reportViaSms;

  /// No description provided for @reportNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next: {step}'**
  String reportNextStep(String step);

  /// No description provided for @mapYourReportLabel.
  ///
  /// In en, this message translates to:
  /// **'Your report'**
  String get mapYourReportLabel;

  /// No description provided for @onbStep.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onbStep(String step, String total);

  /// No description provided for @onbLangGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m Ziren! Which language would you like me to use?'**
  String get onbLangGreeting;

  /// No description provided for @onbLangTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onbLangTitle;

  /// No description provided for @onbLangSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The whole app will use it. You can change it any time in Settings.'**
  String get onbLangSubtitle;

  /// No description provided for @onbLangMoreSoon.
  ///
  /// In en, this message translates to:
  /// **'Waray and Bisaya are coming once a native speaker has reviewed them.'**
  String get onbLangMoreSoon;

  /// No description provided for @onbLangContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onbLangContinue;

  /// No description provided for @onbLangSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get onbLangSelected;

  /// No description provided for @consentAgreedCount.
  ///
  /// In en, this message translates to:
  /// **'{done} of 2 agreed'**
  String consentAgreedCount(String done);

  /// No description provided for @consentNeedsReading.
  ///
  /// In en, this message translates to:
  /// **'Open to read'**
  String get consentNeedsReading;

  /// No description provided for @consentAgreed.
  ///
  /// In en, this message translates to:
  /// **'Agreed'**
  String get consentAgreed;

  /// No description provided for @welcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Help, one tap away.'**
  String get welcomeHeadline;

  /// No description provided for @welcomeFeatureReport.
  ///
  /// In en, this message translates to:
  /// **'Report a fire, accident or medical emergency in seconds'**
  String get welcomeFeatureReport;

  /// No description provided for @welcomeFeatureStation.
  ///
  /// In en, this message translates to:
  /// **'Your report goes straight to the nearest BFP, PNP or MDRRMO station'**
  String get welcomeFeatureStation;

  /// No description provided for @welcomeFeatureTrack.
  ///
  /// In en, this message translates to:
  /// **'See when a responder is on the way'**
  String get welcomeFeatureTrack;

  /// No description provided for @welcomeNewHere.
  ///
  /// In en, this message translates to:
  /// **'New to Ziren?'**
  String get welcomeNewHere;

  /// No description provided for @legalMeta.
  ///
  /// In en, this message translates to:
  /// **'{sections} sections · about {minutes} min read'**
  String legalMeta(String sections, String minutes);

  /// No description provided for @legalProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% read'**
  String legalProgress(String percent);

  /// No description provided for @legalReachedEnd.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the end'**
  String get legalReachedEnd;

  /// No description provided for @legalBackToTop.
  ///
  /// In en, this message translates to:
  /// **'Back to top'**
  String get legalBackToTop;

  /// No description provided for @welcomeMascotLine.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set! Create an account, or sign in if you already have one.'**
  String get welcomeMascotLine;

  /// No description provided for @categoryMissingPerson.
  ///
  /// In en, this message translates to:
  /// **'Missing person'**
  String get categoryMissingPerson;

  /// No description provided for @categoryEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get categoryEmergency;

  /// No description provided for @respStatusDispatchedRespond.
  ///
  /// In en, this message translates to:
  /// **'Dispatched — Respond Now'**
  String get respStatusDispatchedRespond;

  /// No description provided for @respNextEnRoute.
  ///
  /// In en, this message translates to:
  /// **'On my way (En Route)'**
  String get respNextEnRoute;

  /// No description provided for @respNextOnScene.
  ///
  /// In en, this message translates to:
  /// **'Arrived (On Scene)'**
  String get respNextOnScene;

  /// No description provided for @respNextResolved.
  ///
  /// In en, this message translates to:
  /// **'Done (Resolved)'**
  String get respNextResolved;

  /// No description provided for @respNoAddress.
  ///
  /// In en, this message translates to:
  /// **'No address recorded'**
  String get respNoAddress;

  /// No description provided for @respAlertOverdueNote.
  ///
  /// In en, this message translates to:
  /// **'The dispatcher now sees this as unanswered. You can still accept it.'**
  String get respAlertOverdueNote;

  /// No description provided for @respAlertTimeoutNote.
  ///
  /// In en, this message translates to:
  /// **'If nobody answers, it goes back to the dispatcher so they can send someone else.'**
  String get respAlertTimeoutNote;

  /// No description provided for @respNoMapApp.
  ///
  /// In en, this message translates to:
  /// **'No map app could be opened on this phone.'**
  String get respNoMapApp;

  /// No description provided for @respJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get respJustNow;

  /// No description provided for @wizardSpeakDetails.
  ///
  /// In en, this message translates to:
  /// **'Speak the details'**
  String get wizardSpeakDetails;

  /// No description provided for @wizardListening.
  ///
  /// In en, this message translates to:
  /// **'Listening… (tap to stop)'**
  String get wizardListening;

  /// No description provided for @wizardNext.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get wizardNext;

  /// No description provided for @respNavByRoad.
  ///
  /// In en, this message translates to:
  /// **'by road'**
  String get respNavByRoad;

  /// No description provided for @respNavRoadNote.
  ///
  /// In en, this message translates to:
  /// **'The route follows the roads on the map. Watch for closed or flooded roads.'**
  String get respNavRoadNote;

  /// No description provided for @accountNoticeEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Account notice'**
  String get accountNoticeEyebrow;

  /// No description provided for @accountWarnedTitle.
  ///
  /// In en, this message translates to:
  /// **'You received a warning'**
  String get accountWarnedTitle;

  /// Which rule was broken.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}.'**
  String accountWarnedBody(String reason);

  /// How many warnings are left before an automatic suspension.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One more warning and your account will be suspended from reporting.} other{{count} more warnings and your account will be suspended from reporting.}}'**
  String accountWarnedLeft(int count);

  /// No description provided for @accountSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Reporting is suspended'**
  String get accountSuspendedTitle;

  /// When the suspension ends.
  ///
  /// In en, this message translates to:
  /// **'You cannot send reports until {date}.'**
  String accountSuspendedUntil(String date);

  /// No description provided for @accountSuspendedIndefinite.
  ///
  /// In en, this message translates to:
  /// **'You cannot send reports until further notice.'**
  String get accountSuspendedIndefinite;

  /// No description provided for @accountSuspendedHelp.
  ///
  /// In en, this message translates to:
  /// **'In a real emergency, call 911 or a hotline. To appeal, contact your municipal MDRRMO office.'**
  String get accountSuspendedHelp;

  /// No description provided for @accountOpenHotlines.
  ///
  /// In en, this message translates to:
  /// **'Emergency hotlines'**
  String get accountOpenHotlines;

  /// No description provided for @accountReinstatedTitle.
  ///
  /// In en, this message translates to:
  /// **'You can send reports again'**
  String get accountReinstatedTitle;

  /// No description provided for @accountReinstatedBody.
  ///
  /// In en, this message translates to:
  /// **'Your suspension was lifted.'**
  String get accountReinstatedBody;

  /// No description provided for @accountWarningsClearedBody.
  ///
  /// In en, this message translates to:
  /// **'Your warnings were cleared.'**
  String get accountWarningsClearedBody;

  /// No description provided for @violationFalseReport.
  ///
  /// In en, this message translates to:
  /// **'Sending a false or prank report'**
  String get violationFalseReport;

  /// No description provided for @violationFalseSos.
  ///
  /// In en, this message translates to:
  /// **'Misusing the SOS button'**
  String get violationFalseSos;

  /// No description provided for @violationSpam.
  ///
  /// In en, this message translates to:
  /// **'Sending repeated or duplicate reports'**
  String get violationSpam;

  /// No description provided for @violationAbusive.
  ///
  /// In en, this message translates to:
  /// **'Abusive or threatening messages'**
  String get violationAbusive;

  /// No description provided for @violationFakeIdentity.
  ///
  /// In en, this message translates to:
  /// **'Using a false or borrowed identity'**
  String get violationFakeIdentity;

  /// No description provided for @violationOther.
  ///
  /// In en, this message translates to:
  /// **'A violation of the reporting rules'**
  String get violationOther;

  /// No description provided for @annWholeProvince.
  ///
  /// In en, this message translates to:
  /// **'Whole province'**
  String get annWholeProvince;

  /// No description provided for @annKindEvacuation.
  ///
  /// In en, this message translates to:
  /// **'Evacuation order'**
  String get annKindEvacuation;

  /// No description provided for @annKindWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather advisory'**
  String get annKindWeather;

  /// No description provided for @annKindHazard.
  ///
  /// In en, this message translates to:
  /// **'Hazard warning'**
  String get annKindHazard;

  /// No description provided for @annKindRoadClosure.
  ///
  /// In en, this message translates to:
  /// **'Road closure'**
  String get annKindRoadClosure;

  /// No description provided for @annKindMissingPerson.
  ///
  /// In en, this message translates to:
  /// **'Missing person'**
  String get annKindMissingPerson;

  /// No description provided for @annKindAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get annKindAllClear;

  /// No description provided for @annKindRelief.
  ///
  /// In en, this message translates to:
  /// **'Relief distribution'**
  String get annKindRelief;

  /// No description provided for @annKindHealth.
  ///
  /// In en, this message translates to:
  /// **'Health advisory'**
  String get annKindHealth;

  /// No description provided for @annKindDrill.
  ///
  /// In en, this message translates to:
  /// **'Drill'**
  String get annKindDrill;

  /// No description provided for @annKindUtility.
  ///
  /// In en, this message translates to:
  /// **'Power / water interruption'**
  String get annKindUtility;

  /// No description provided for @annHazardFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get annHazardFlood;

  /// No description provided for @annHazardLandslide.
  ///
  /// In en, this message translates to:
  /// **'Landslide'**
  String get annHazardLandslide;

  /// No description provided for @annHazardStormSurge.
  ///
  /// In en, this message translates to:
  /// **'Storm surge'**
  String get annHazardStormSurge;

  /// No description provided for @annHazardEarthquake.
  ///
  /// In en, this message translates to:
  /// **'Earthquake'**
  String get annHazardEarthquake;

  /// No description provided for @annHazardTsunami.
  ///
  /// In en, this message translates to:
  /// **'Tsunami'**
  String get annHazardTsunami;

  /// No description provided for @annHazardVolcanic.
  ///
  /// In en, this message translates to:
  /// **'Volcanic activity'**
  String get annHazardVolcanic;

  /// No description provided for @annHazardFire.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get annHazardFire;

  /// No description provided for @annHazardOther.
  ///
  /// In en, this message translates to:
  /// **'Other hazard'**
  String get annHazardOther;

  /// No description provided for @annRainfallYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow rainfall warning'**
  String get annRainfallYellow;

  /// No description provided for @annRainfallOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange rainfall warning'**
  String get annRainfallOrange;

  /// No description provided for @annRainfallRed.
  ///
  /// In en, this message translates to:
  /// **'Red rainfall warning'**
  String get annRainfallRed;

  /// No description provided for @annSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal No. {n}'**
  String annSignal(int n);

  /// No description provided for @annEvacForced.
  ///
  /// In en, this message translates to:
  /// **'Forced'**
  String get annEvacForced;

  /// No description provided for @annEvacPreemptive.
  ///
  /// In en, this message translates to:
  /// **'Pre-emptive'**
  String get annEvacPreemptive;

  /// No description provided for @annReopens.
  ///
  /// In en, this message translates to:
  /// **'Reopens {when}'**
  String annReopens(String when);

  /// No description provided for @annAge.
  ///
  /// In en, this message translates to:
  /// **'Age {age}'**
  String annAge(int age);

  /// No description provided for @annGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get annGoTo;

  /// No description provided for @annBring.
  ///
  /// In en, this message translates to:
  /// **'Bring'**
  String get annBring;

  /// No description provided for @annArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get annArea;

  /// No description provided for @annClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get annClosed;

  /// No description provided for @annUseInstead.
  ///
  /// In en, this message translates to:
  /// **'Use instead'**
  String get annUseInstead;

  /// No description provided for @annName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get annName;

  /// No description provided for @annLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get annLastSeen;

  /// No description provided for @annLooksLike.
  ///
  /// In en, this message translates to:
  /// **'Looks like'**
  String get annLooksLike;

  /// No description provided for @annCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get annCall;

  /// No description provided for @annWhere.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get annWhere;

  /// No description provided for @annFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get annFrom;

  /// No description provided for @annNeedHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for help'**
  String get annNeedHelpTitle;

  /// No description provided for @annNeedHelpBody.
  ///
  /// In en, this message translates to:
  /// **'The stations of your town are told at once, with where your phone is. Add a line if you can - how many of you, what is happening.'**
  String get annNeedHelpBody;

  /// No description provided for @annNeedHelpHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Three of us on the roof, water rising'**
  String get annNeedHelpHint;

  /// No description provided for @annNeedHelpSend.
  ///
  /// In en, this message translates to:
  /// **'Send: I need help'**
  String get annNeedHelpSend;

  /// No description provided for @annCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get annCancel;

  /// No description provided for @annSentSafe.
  ///
  /// In en, this message translates to:
  /// **'Sent: you are safe. Thank you.'**
  String get annSentSafe;

  /// No description provided for @annSentHelp.
  ///
  /// In en, this message translates to:
  /// **'Sent. The stations of your town have been told.'**
  String get annSentHelp;

  /// No description provided for @annEndedTitle.
  ///
  /// In en, this message translates to:
  /// **'This alert has ended'**
  String get annEndedTitle;

  /// No description provided for @annEndedBody.
  ///
  /// In en, this message translates to:
  /// **'An all clear was sent or it expired, so it takes no more answers. If you still need help, call a hotline.'**
  String get annEndedBody;

  /// No description provided for @annNotSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Your answer was not sent'**
  String get annNotSentTitle;

  /// No description provided for @annNotSentHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Ziren could not reach the server. If you need help now, call a hotline - a call needs only signal.'**
  String get annNotSentHelpBody;

  /// No description provided for @annNotSentBody.
  ///
  /// In en, this message translates to:
  /// **'Ziren could not reach the server. Try again when you have a connection.'**
  String get annNotSentBody;

  /// No description provided for @annAreYouSafe.
  ///
  /// In en, this message translates to:
  /// **'Are you safe?'**
  String get annAreYouSafe;

  /// No description provided for @annImSafe.
  ///
  /// In en, this message translates to:
  /// **'I am safe'**
  String get annImSafe;

  /// No description provided for @annINeedHelp.
  ///
  /// In en, this message translates to:
  /// **'I need help'**
  String get annINeedHelp;

  /// No description provided for @annYouSaidSafe.
  ///
  /// In en, this message translates to:
  /// **'You said you are safe.'**
  String get annYouSaidSafe;

  /// No description provided for @annYouAskedHelp.
  ///
  /// In en, this message translates to:
  /// **'You asked for help. The stations have been told.'**
  String get annYouAskedHelp;

  /// No description provided for @annHelpReached.
  ///
  /// In en, this message translates to:
  /// **'A station has your call for help and is responding.'**
  String get annHelpReached;

  /// No description provided for @annHelpWhileWaiting.
  ///
  /// In en, this message translates to:
  /// **'Stay where it is safest. If it gets worse, call a hotline.'**
  String get annHelpWhileWaiting;

  /// No description provided for @annChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get annChange;

  /// No description provided for @annSafetyAlerts.
  ///
  /// In en, this message translates to:
  /// **'Safety alerts'**
  String get annSafetyAlerts;

  /// No description provided for @annUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get annUpdates;

  /// No description provided for @annIssuedBy.
  ///
  /// In en, this message translates to:
  /// **'From {office}'**
  String annIssuedBy(String office);

  /// No description provided for @annUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String annUntil(String date);

  /// No description provided for @annEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get annEnded;

  /// No description provided for @annEndsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ends: {title}'**
  String annEndsTitle(String title);

  /// No description provided for @annEndedBy.
  ///
  /// In en, this message translates to:
  /// **'Ended by: {title}'**
  String annEndedBy(String title);

  /// No description provided for @annNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get annNotFoundTitle;

  /// No description provided for @annNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'This announcement was taken down, or it is not for your area.'**
  String get annNotFoundBody;

  /// No description provided for @annHomeMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more alert} other{{count} more alerts}}'**
  String annHomeMore(int count);

  /// No description provided for @annSeeDetails.
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get annSeeDetails;

  /// No description provided for @annNoticeEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Safety alert'**
  String get annNoticeEyebrow;

  /// No description provided for @annNoticeEyebrowInfo.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get annNoticeEyebrowInfo;

  /// No description provided for @annRespondNow.
  ///
  /// In en, this message translates to:
  /// **'Answer: are you safe?'**
  String get annRespondNow;

  /// No description provided for @annOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get annOpen;

  /// No description provided for @annHelpAckTitle.
  ///
  /// In en, this message translates to:
  /// **'Your call for help was received'**
  String get annHelpAckTitle;

  /// No description provided for @annHelpAckBody.
  ///
  /// In en, this message translates to:
  /// **'{station} has your request and is responding. Stay where it is safest.'**
  String annHelpAckBody(String station);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'fil': return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
