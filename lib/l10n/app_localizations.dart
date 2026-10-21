import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_mg.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('mg'),
    Locale('pt'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// The app's name; not translated.
  ///
  /// In en, this message translates to:
  /// **'Linksy'**
  String get appTitle;

  /// First screen title.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Linksy'**
  String get onboardingWelcome;

  /// No description provided for @onboardingChooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onboardingChooseLanguage;

  /// No description provided for @onboardingLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'You can change it later in Settings.'**
  String get onboardingLanguageHint;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up Linksy'**
  String get onboardingSetUpTitle;

  /// No description provided for @onboardingSetUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what Linksy may do. Nothing leaves this phone until you say so.'**
  String get onboardingSetUpSubtitle;

  /// No description provided for @onboardingNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get onboardingNotifications;

  /// No description provided for @onboardingNotificationsDetail.
  ///
  /// In en, this message translates to:
  /// **'Files arriving, and when a computer uses your screen, camera or microphone, with a button to stop.'**
  String get onboardingNotificationsDetail;

  /// No description provided for @onboardingCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get onboardingCamera;

  /// No description provided for @onboardingCameraDetail.
  ///
  /// In en, this message translates to:
  /// **'Scans pairing QR codes, and lets a computer use it as a webcam when you allow it.'**
  String get onboardingCameraDetail;

  /// No description provided for @onboardingAway.
  ///
  /// In en, this message translates to:
  /// **'Away from home'**
  String get onboardingAway;

  /// No description provided for @onboardingAwayDetail.
  ///
  /// In en, this message translates to:
  /// **'Reach your computers over the internet when you\'re not on the same Wi-Fi. Encrypted end to end.'**
  String get onboardingAwayDetail;

  /// No description provided for @onboardingBackground.
  ///
  /// In en, this message translates to:
  /// **'Keep running in the background'**
  String get onboardingBackground;

  /// No description provided for @onboardingBackgroundDetail.
  ///
  /// In en, this message translates to:
  /// **'Files and calls keep working when Linksy is closed. Shows a quiet notification.'**
  String get onboardingBackgroundDetail;

  /// No description provided for @onboardingFolder.
  ///
  /// In en, this message translates to:
  /// **'Share a folder with computers'**
  String get onboardingFolder;

  /// No description provided for @onboardingFolderDetail.
  ///
  /// In en, this message translates to:
  /// **'Your computers can open one folder you choose in their Files app.'**
  String get onboardingFolderDetail;

  /// No description provided for @onboardingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photo backup folder'**
  String get onboardingPhotos;

  /// No description provided for @onboardingPhotosDetail.
  ///
  /// In en, this message translates to:
  /// **'Choose your camera folder to back up new photos to a computer. Turned on per computer.'**
  String get onboardingPhotosDetail;

  /// No description provided for @onboardingLocate.
  ///
  /// In en, this message translates to:
  /// **'Let computers locate this phone'**
  String get onboardingLocate;

  /// No description provided for @onboardingLocateDetail.
  ///
  /// In en, this message translates to:
  /// **'A computer can ask where this phone is, once. Nothing is kept.'**
  String get onboardingLocateDetail;

  /// No description provided for @onboardingAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get onboardingAllow;

  /// No description provided for @onboardingAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get onboardingAllowed;

  /// Button to pick a folder.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get onboardingChooseFolder;

  /// No description provided for @onboardingFolderChosen.
  ///
  /// In en, this message translates to:
  /// **'“{folder}”'**
  String onboardingFolderChosen(String folder);

  /// No description provided for @onboardingAnytime.
  ///
  /// In en, this message translates to:
  /// **'You can turn any of these on or off anytime in Settings.'**
  String get onboardingAnytime;

  /// No description provided for @onboardingStart.
  ///
  /// In en, this message translates to:
  /// **'Start using Linksy'**
  String get onboardingStart;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get languageDone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'mg',
    'pt',
    'ru',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'mg':
      return AppLocalizationsMg();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
