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
  String get controlOverBluetooth => 'Control over Bluetooth';

  @override
  String get bleNoSavedSession =>
      'No saved Bluetooth sign-in yet. Connect over Wi-Fi once to pair this phone.';

  @override
  String get bleTroubleTitle => 'Can’t reach it over Bluetooth';

  @override
  String get bleTroubleBody =>
      'Move closer to the switch and make sure Bluetooth is on.';

  @override
  String get forgotPasswordRecover => 'Forgot the password? Recover it';

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
  String get reconnect => 'Reconnect';

  @override
  String get connected => 'Connected';

  @override
  String get switchOn => 'On';

  @override
  String get switchOff => 'Off';

  @override
  String get switchOffline => 'Offline';

  @override
  String onOfTotal(int on, int total) {
    return '$on of $total on';
  }

  @override
  String get allOn => 'All on';

  @override
  String get allOff => 'All off';

  @override
  String get meshBadge => 'Mesh';

  @override
  String get viaWifi => 'Wi-Fi';

  @override
  String get viaBluetooth => 'Bluetooth';

  @override
  String get connectionSection => 'Connection';

  @override
  String get transportWifi => 'Wi-Fi';

  @override
  String get transportWifiDesc => 'Over the switch\'s own network.';

  @override
  String get transportBluetooth => 'Bluetooth';

  @override
  String get transportBluetoothDesc => 'Your phone keeps its own network.';

  @override
  String get switchTransport => 'Switch connection';

  @override
  String get btNeedsWifiLogin =>
      'Sign in over Wi-Fi first — Bluetooth mode uses that sign-in.';

  @override
  String get btPermissionDenied =>
      'Bluetooth permission is needed for this mode.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get accessResetTitle => 'Your access was reset';

  @override
  String accessResetBody(String network) {
    return 'The password was changed, so this phone was signed out. Connect to $network to sign in again.';
  }

  @override
  String get accessResetBodyGeneric =>
      'The password was changed, so this phone was signed out. Connect to the switch\'s Wi-Fi to sign in again.';

  @override
  String get wifiOnlyTitle => 'Wi-Fi needed for this';

  @override
  String get wifiOnlyBody =>
      'This action isn\'t available over Bluetooth. Join the switch\'s Wi-Fi network to continue.';

  @override
  String get joinWifi => 'Add / join Wi-Fi';

  @override
  String get menuExtensions => 'Extensions';

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
