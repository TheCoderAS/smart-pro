// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Unisync';

  @override
  String get sessionLoading => 'Connecting…';

  @override
  String get unreachableTitle => 'Can’t reach your switch';

  @override
  String get unreachableBody =>
      'Join the switch’s Wi-Fi network and try again. The network name is on the card in the box.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get addASwitch => 'Add a switch';

  @override
  String get signInTitle => 'Sign in';

  @override
  String masterIdentity(String uid, String fw) {
    return 'Master $uid · firmware $fw';
  }

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHelper => 'The same password you used to join the Wi-Fi.';

  @override
  String get signInButton => 'Sign in';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get errorWrongPassword =>
      'Wrong password. It is on the card in the box.';

  @override
  String errorLockedOut(int minutes) {
    return 'Too many attempts. Locked for about $minutes minutes.';
  }

  @override
  String get errorRateLimited => 'Too many requests — give it a few seconds.';

  @override
  String get errorUnreachable =>
      'Lost the connection to the switch. Check that you are still on its Wi-Fi.';

  @override
  String errorServer(int status) {
    return 'The switch replied with an error ($status). Try again.';
  }

  @override
  String get dashboardEmptyTitle => 'No switches yet';

  @override
  String get dashboardEmptyBody =>
      'Snap an Extension onto the bus next to your Master and it will appear here.';

  @override
  String get reconnecting => 'Reconnecting';

  @override
  String get switchOn => 'On';

  @override
  String get switchOff => 'Off';

  @override
  String get switchOffline => 'Offline';

  @override
  String get menuReorder => 'Reorder switches';

  @override
  String get menuExtensions => 'Extensions';

  @override
  String get menuMesh => 'Mesh';

  @override
  String get menuFirmware => 'Firmware';

  @override
  String get menuAudit => 'Activity log';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuKillAll => 'Turn everything off';

  @override
  String get killAllTitle => 'Turn everything off?';

  @override
  String get killAllBody =>
      'Every switch on every master in the mesh will turn off.';

  @override
  String get cancel => 'Cancel';

  @override
  String get turnOff => 'Turn off';

  @override
  String get yourSwitches => 'Your switches';
}
