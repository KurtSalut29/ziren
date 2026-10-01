import 'package:flutter/widgets.dart';

/// The poses on branding/Demo_Mascots.png that a demo uses, cut out into
/// assets/images/demo/ (see the cutout notes in that folder's history).
///
/// The side, back and three-quarter turnarounds are left out on purpose: a
/// mascot looking away from the person it is teaching teaches nothing.
enum DemoPose {
  pointLeft('point_left'),
  pointRight('point_right'),
  pointUp('point_up'),
  pointDown('point_down'),
  pointYou('point_you'),
  thinking('thinking'),
  excited('excited'),
  confused('confused'),
  wink('wink'),
  ok('ok'),
  front('front'),
  running('running'),
  jumping('jumping'),
  sitting('sitting');

  const DemoPose(this.file);

  final String file;

  String get asset => 'assets/images/demo/$file.png';
}

/// One thing the mascot shows: a part of the screen (by its [DemoAnchor] id)
/// and what it says about it, in both languages.
///
/// With no [anchor], or when that part of the screen is not there right now
/// (an empty list, an account in a state that hides it), the mascot says the
/// line in the middle of the screen instead of pointing at nothing.
class DemoStep {
  const DemoStep({this.anchor, required this.fil, required this.en, this.pose});

  final String? anchor;
  final String fil;
  final String en;

  /// Leave unset to let the mascot point at the anchor from wherever its
  /// bubble ends up (up or down); set it for a line with a feeling of its own.
  final DemoPose? pose;

  String text(String languageCode) => languageCode == 'en' ? en : fil;
}

/// A walkthrough of one screen.
class DemoScript {
  const DemoScript({
    required this.id,
    required this.icon,
    required this.titleFil,
    required this.titleEn,
    required this.summaryFil,
    required this.summaryEn,
    required this.open,
    required this.steps,
    this.close,
    this.available,
    this.unavailableFil,
    this.unavailableEn,
    this.screenAnchor,
  });

  /// An anchor that is on the screen whatever it holds (its body), for a
  /// screen whose other parts can all be missing — an empty Notifications
  /// list. The tour starts as soon as this is built, instead of waiting for a
  /// part that will never appear.
  final String? screenAnchor;

  /// Where the user is taken when the demo ends: the Home they came from.
  String get homeRoute =>
      id.startsWith('responder.') ? '/responder/queue' : '/home';

  /// For a screen that needs something to show (a report of one's own, an
  /// assignment): false greys the demo out, with [unavailableFil] /
  /// [unavailableEn] saying why.
  final bool Function(BuildContext context)? available;
  final String? unavailableFil;
  final String? unavailableEn;

  String? unavailable(String languageCode) =>
      languageCode == 'en' ? unavailableEn : unavailableFil;

  final String id;
  final IconData icon;
  final String titleFil;
  final String titleEn;
  final String summaryFil;
  final String summaryEn;

  /// Brings the screen up (a tab switch, a push, or setting up a form). Gets
  /// the context of the root navigator, which outlives the help sheet.
  final Future<void> Function(BuildContext context) open;

  /// Puts things back when the demo ends: leaves a form it opened, clears
  /// anything it set. Nothing is ever sent by a demo.
  final void Function(BuildContext context)? close;

  final List<DemoStep> steps;

  String title(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFil;
  String summary(String languageCode) =>
      languageCode == 'en' ? summaryEn : summaryFil;
}
