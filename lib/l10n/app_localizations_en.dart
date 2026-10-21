// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Linksy';

  @override
  String get onboardingWelcome => 'Welcome to Linksy';

  @override
  String get onboardingChooseLanguage => 'Choose your language';

  @override
  String get onboardingLanguageHint => 'You can change it later in Settings.';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingSetUpTitle => 'Set up Linksy';

  @override
  String get onboardingSetUpSubtitle =>
      'Choose what Linksy may do. Nothing leaves this phone until you say so.';

  @override
  String get onboardingNotifications => 'Notifications';

  @override
  String get onboardingNotificationsDetail =>
      'Files arriving, and when a computer uses your screen, camera or microphone, with a button to stop.';

  @override
  String get onboardingCamera => 'Camera';

  @override
  String get onboardingCameraDetail =>
      'Scans pairing QR codes, and lets a computer use it as a webcam when you allow it.';

  @override
  String get onboardingAway => 'Away from home';

  @override
  String get onboardingAwayDetail =>
      'Reach your computers over the internet when you\'re not on the same Wi-Fi. Encrypted end to end.';

  @override
  String get onboardingBackground => 'Keep running in the background';

  @override
  String get onboardingBackgroundDetail =>
      'Files and calls keep working when Linksy is closed. Shows a quiet notification.';

  @override
  String get onboardingFolder => 'Share a folder with computers';

  @override
  String get onboardingFolderDetail =>
      'Your computers can open one folder you choose in their Files app.';

  @override
  String get onboardingPhotos => 'Photo backup folder';

  @override
  String get onboardingPhotosDetail =>
      'Choose your camera folder to back up new photos to a computer. Turned on per computer.';

  @override
  String get onboardingLocate => 'Let computers locate this phone';

  @override
  String get onboardingLocateDetail =>
      'A computer can ask where this phone is, once. Nothing is kept.';

  @override
  String get onboardingAllow => 'Allow';

  @override
  String get onboardingAllowed => 'Allowed';

  @override
  String get onboardingChooseFolder => 'Choose';

  @override
  String onboardingFolderChosen(String folder) {
    return '“$folder”';
  }

  @override
  String get onboardingAnytime =>
      'You can turn any of these on or off anytime in Settings.';

  @override
  String get onboardingStart => 'Start using Linksy';

  @override
  String get onboardingBack => 'Back';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageDone => 'Done';
}
