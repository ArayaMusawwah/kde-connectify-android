/// The app's languages. Widgets read their text with `context.l10n.key`;
/// code without a context (the controller's messages, notifications) uses
/// [tr], which follows the language the app shows.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

AppLocalizations _tr = lookupAppLocalizations(const Locale('en'));

/// The app's text in its current language, for code without a context.
AppLocalizations get tr => _tr;

/// One language the app speaks: its code, its own name, and its English one.
typedef Language = ({String code, String name, String english});

/// The 10 languages, in the order the picker shows them.
const languages = <Language>[
  (code: 'en', name: 'English', english: 'English'),
  (code: 'fr', name: 'Français', english: 'French'),
  (code: 'mg', name: 'Malagasy', english: 'Malagasy'),
  (code: 'es', name: 'Español', english: 'Spanish'),
  (code: 'pt', name: 'Português', english: 'Portuguese'),
  (code: 'de', name: 'Deutsch', english: 'German'),
  (code: 'it', name: 'Italiano', english: 'Italian'),
  (code: 'ru', name: 'Русский', english: 'Russian'),
  (code: 'zh', name: '中文', english: 'Chinese'),
  (code: 'ja', name: '日本語', english: 'Japanese'),
];

/// [code] if the app speaks it, else the phone's own language if it does,
/// else English.
Locale resolveLocale(String? code) {
  final codes = {for (final l in languages) l.code};
  if (code != null && codes.contains(code)) return Locale(code);
  final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return Locale(codes.contains(system) ? system : 'en');
}

/// Makes [locale] the language of [tr].
void useLocale(Locale locale) => _tr = lookupAppLocalizations(locale);

/// Flutter's own widgets have no Malagasy: they use French there.
const localizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  _Fallback<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  _Fallback<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
  _Fallback<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class _Fallback<T> extends LocalizationsDelegate<T> {
  const _Fallback(this.inner);

  final LocalizationsDelegate<T> inner;

  @override
  bool isSupported(Locale locale) =>
      !inner.isSupported(locale) &&
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<T> load(Locale locale) => inner.load(const Locale('fr'));

  @override
  bool shouldReload(_Fallback<T> old) => false;

  @override
  Type get type => T;
}
