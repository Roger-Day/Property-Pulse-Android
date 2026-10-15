import 'package:package_info_plus/package_info_plus.dart';

/// "1.1.0 (19)" from the installed app, read once. Falls back to an empty string
/// if the platform cannot say.
class AppVersion {
  AppVersion._();

  static Future<String>? _label;

  static Future<String> label() => _label ??= _read();

  static Future<String> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '';
    }
  }
}
