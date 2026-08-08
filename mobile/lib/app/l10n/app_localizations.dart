import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Unisync'**
  String get appTitle;

  /// No description provided for @sessionLoading.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get sessionLoading;

  /// No description provided for @unreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'Can’t reach your switch'**
  String get unreachableTitle;

  /// No description provided for @unreachableBody.
  ///
  /// In en, this message translates to:
  /// **'Join the switch’s Wi-Fi network and try again. The network name is on the card in the box.'**
  String get unreachableBody;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @addASwitch.
  ///
  /// In en, this message translates to:
  /// **'Add a switch'**
  String get addASwitch;

  /// No description provided for @forgotPasswordRecover.
  ///
  /// In en, this message translates to:
  /// **'Forgot the password? Recover it'**
  String get forgotPasswordRecover;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @masterIdentity.
  ///
  /// In en, this message translates to:
  /// **'Master {uid} · firmware {fw}'**
  String masterIdentity(String uid, String fw);

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordHelper.
  ///
  /// In en, this message translates to:
  /// **'The same password you used to join the Wi-Fi.'**
  String get passwordHelper;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInButton;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @errorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. It is on the card in the box.'**
  String get errorWrongPassword;

  /// No description provided for @errorLockedOut.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Locked for about {minutes} minutes.'**
  String errorLockedOut(int minutes);

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests — give it a few seconds.'**
  String get errorRateLimited;

  /// No description provided for @errorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Lost the connection to the switch. Check that you are still on its Wi-Fi.'**
  String get errorUnreachable;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'The switch replied with an error ({status}). Try again.'**
  String errorServer(int status);

  /// No description provided for @dashboardEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No switches yet'**
  String get dashboardEmptyTitle;

  /// No description provided for @dashboardEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Snap an Extension onto the bus next to your Master and it will appear here.'**
  String get dashboardEmptyBody;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get reconnecting;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @switchOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get switchOn;

  /// No description provided for @switchOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get switchOff;

  /// No description provided for @switchOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get switchOffline;

  /// No description provided for @onOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{on} of {total} on'**
  String onOfTotal(int on, int total);

  /// No description provided for @allOn.
  ///
  /// In en, this message translates to:
  /// **'All on'**
  String get allOn;

  /// No description provided for @allOff.
  ///
  /// In en, this message translates to:
  /// **'All off'**
  String get allOff;

  /// No description provided for @meshBadge.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get meshBadge;

  /// No description provided for @menuReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder switches'**
  String get menuReorder;

  /// No description provided for @menuExtensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get menuExtensions;

  /// No description provided for @menuMesh.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get menuMesh;

  /// No description provided for @menuFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get menuFirmware;

  /// No description provided for @menuAudit.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get menuAudit;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @menuKillAll.
  ///
  /// In en, this message translates to:
  /// **'Turn everything off'**
  String get menuKillAll;

  /// No description provided for @killAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn everything off?'**
  String get killAllTitle;

  /// No description provided for @killAllBody.
  ///
  /// In en, this message translates to:
  /// **'Every switch on every master in the mesh will turn off.'**
  String get killAllBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @turnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get turnOff;

  /// No description provided for @yourSwitches.
  ///
  /// In en, this message translates to:
  /// **'Your switches'**
  String get yourSwitches;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
