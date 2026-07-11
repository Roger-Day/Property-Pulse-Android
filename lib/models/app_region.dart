import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors iOS `Region` (`Region.swift`): id, display name, locale, currency.
class AppRegion {
  const AppRegion({
    required this.id,
    required this.displayName,
    required this.localeIdentifier,
    required this.currencyCode,
  });

  final String id;
  final String displayName;
  final String localeIdentifier;
  final String currencyCode;

  /// Same catalog as iOS `Region.supportedRegions`.
  static const List<AppRegion> supportedRegions = [
    AppRegion(id: 'us', displayName: 'United States', localeIdentifier: 'en_US', currencyCode: 'USD'),
    AppRegion(id: 'uk', displayName: 'United Kingdom', localeIdentifier: 'en_GB', currencyCode: 'GBP'),
    AppRegion(id: 'ca', displayName: 'Canada', localeIdentifier: 'en_CA', currencyCode: 'CAD'),
    AppRegion(id: 'au', displayName: 'Australia', localeIdentifier: 'en_AU', currencyCode: 'AUD'),
    AppRegion(id: 'nz', displayName: 'New Zealand', localeIdentifier: 'en_NZ', currencyCode: 'NZD'),
    AppRegion(id: 'ie', displayName: 'Ireland', localeIdentifier: 'en_IE', currencyCode: 'EUR'),
    AppRegion(id: 'de', displayName: 'Germany', localeIdentifier: 'de_DE', currencyCode: 'EUR'),
    AppRegion(id: 'fr', displayName: 'France', localeIdentifier: 'fr_FR', currencyCode: 'EUR'),
    AppRegion(id: 'es', displayName: 'Spain', localeIdentifier: 'es_ES', currencyCode: 'EUR'),
    AppRegion(id: 'it', displayName: 'Italy', localeIdentifier: 'it_IT', currencyCode: 'EUR'),
    AppRegion(id: 'nl', displayName: 'Netherlands', localeIdentifier: 'nl_NL', currencyCode: 'EUR'),
    AppRegion(id: 'be', displayName: 'Belgium', localeIdentifier: 'nl_BE', currencyCode: 'EUR'),
    AppRegion(id: 'ch', displayName: 'Switzerland', localeIdentifier: 'de_CH', currencyCode: 'CHF'),
    AppRegion(id: 'at', displayName: 'Austria', localeIdentifier: 'de_AT', currencyCode: 'EUR'),
    AppRegion(id: 'se', displayName: 'Sweden', localeIdentifier: 'sv_SE', currencyCode: 'SEK'),
    AppRegion(id: 'no', displayName: 'Norway', localeIdentifier: 'nb_NO', currencyCode: 'NOK'),
    AppRegion(id: 'dk', displayName: 'Denmark', localeIdentifier: 'da_DK', currencyCode: 'DKK'),
    AppRegion(id: 'fi', displayName: 'Finland', localeIdentifier: 'fi_FI', currencyCode: 'EUR'),
    AppRegion(id: 'pl', displayName: 'Poland', localeIdentifier: 'pl_PL', currencyCode: 'PLN'),
    AppRegion(id: 'jp', displayName: 'Japan', localeIdentifier: 'ja_JP', currencyCode: 'JPY'),
    AppRegion(id: 'cn', displayName: 'China', localeIdentifier: 'zh_CN', currencyCode: 'CNY'),
    AppRegion(id: 'in', displayName: 'India', localeIdentifier: 'en_IN', currencyCode: 'INR'),
    AppRegion(id: 'sg', displayName: 'Singapore', localeIdentifier: 'en_SG', currencyCode: 'SGD'),
    AppRegion(id: 'hk', displayName: 'Hong Kong', localeIdentifier: 'zh_HK', currencyCode: 'HKD'),
    AppRegion(id: 'ae', displayName: 'United Arab Emirates', localeIdentifier: 'ar_AE', currencyCode: 'AED'),
    AppRegion(id: 'sa', displayName: 'Saudi Arabia', localeIdentifier: 'ar_SA', currencyCode: 'SAR'),
    AppRegion(id: 'za', displayName: 'South Africa', localeIdentifier: 'en_ZA', currencyCode: 'ZAR'),
    AppRegion(id: 'br', displayName: 'Brazil', localeIdentifier: 'pt_BR', currencyCode: 'BRL'),
    AppRegion(id: 'mx', displayName: 'Mexico', localeIdentifier: 'es_MX', currencyCode: 'MXN'),
    AppRegion(id: 'ar', displayName: 'Argentina', localeIdentifier: 'es_AR', currencyCode: 'ARS'),
    AppRegion(id: 'jm', displayName: 'Jamaica', localeIdentifier: 'en_JM', currencyCode: 'JMD'),
    AppRegion(id: 'tt', displayName: 'Trinidad and Tobago', localeIdentifier: 'en_TT', currencyCode: 'TTD'),
    AppRegion(id: 'bb', displayName: 'Barbados', localeIdentifier: 'en_BB', currencyCode: 'BBD'),
    AppRegion(id: 'bs', displayName: 'Bahamas', localeIdentifier: 'en_BS', currencyCode: 'BSD'),
    AppRegion(id: 'do', displayName: 'Dominican Republic', localeIdentifier: 'es_DO', currencyCode: 'DOP'),
    AppRegion(id: 'pr', displayName: 'Puerto Rico', localeIdentifier: 'es_PR', currencyCode: 'USD'),
    AppRegion(id: 'cu', displayName: 'Cuba', localeIdentifier: 'es_CU', currencyCode: 'CUP'),
    AppRegion(id: 'ht', displayName: 'Haiti', localeIdentifier: 'fr_HT', currencyCode: 'HTG'),
    AppRegion(id: 'aw', displayName: 'Aruba', localeIdentifier: 'nl_AW', currencyCode: 'AWG'),
    AppRegion(id: 'cw', displayName: 'Curaçao', localeIdentifier: 'nl_CW', currencyCode: 'ANG'),
    AppRegion(id: 'ky', displayName: 'Cayman Islands', localeIdentifier: 'en_KY', currencyCode: 'KYD'),
    AppRegion(id: 'bm', displayName: 'Bermuda', localeIdentifier: 'en_BM', currencyCode: 'BMD'),
    AppRegion(id: 'vg', displayName: 'British Virgin Islands', localeIdentifier: 'en_VG', currencyCode: 'USD'),
    AppRegion(id: 'vi', displayName: 'US Virgin Islands', localeIdentifier: 'en_VI', currencyCode: 'USD'),
    AppRegion(id: 'lc', displayName: 'Saint Lucia', localeIdentifier: 'en_LC', currencyCode: 'XCD'),
    AppRegion(id: 'ag', displayName: 'Antigua and Barbuda', localeIdentifier: 'en_AG', currencyCode: 'XCD'),
    AppRegion(id: 'gd', displayName: 'Grenada', localeIdentifier: 'en_GD', currencyCode: 'XCD'),
    AppRegion(id: 'vc', displayName: 'Saint Vincent and the Grenadines', localeIdentifier: 'en_VC', currencyCode: 'XCD'),
    AppRegion(id: 'kn', displayName: 'Saint Kitts and Nevis', localeIdentifier: 'en_KN', currencyCode: 'XCD'),
    AppRegion(id: 'dm', displayName: 'Dominica', localeIdentifier: 'en_DM', currencyCode: 'XCD'),
  ];

  static AppRegion get defaultRegion =>
      regionWithId('us') ?? supportedRegions.first;

  /// Firestore `users.region` → else SharedPreferences → device → US default (iOS load order).
  static AppRegion resolveEffectiveRegion({
    String? firestoreRegionId,
    required SharedPreferences prefs,
  }) {
    final fid = firestoreRegionId?.trim();
    if (fid != null && fid.isNotEmpty) {
      final r = regionWithId(fid);
      if (r != null) return r;
    }
    final sid = prefs.getString(AppRegionPrefsKeys.selectedRegionId);
    if (sid != null && sid.isNotEmpty) {
      final r = regionWithId(sid);
      if (r != null) return r;
    }
    return detectDeviceRegion() ?? defaultRegion;
  }

  static AppRegion? regionWithId(String id) {
    if (id.isEmpty) return null;
    final lower = id.toLowerCase();
    for (final r in supportedRegions) {
      if (r.id.toLowerCase() == lower) return r;
    }
    return null;
  }

  /// Matches iOS `Region.detectDeviceRegion()`.
  static AppRegion? detectDeviceRegion() {
    final locale = ui.PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toLowerCase();
    if (country != null && country.isNotEmpty) {
      for (final r in supportedRegions) {
        if (r.id.toLowerCase() == country) return r;
      }
    }
    return null;
  }

  /// Sample listing price line like iOS `RegionRow` (`250000` formatted).
  String get sampleListingPriceFormatted {
    try {
      final fmt = NumberFormat.currency(
        locale: localeIdentifier,
        name: currencyCode,
      );
      return fmt.format(250000);
    } catch (_) {
      return '$currencyCode 250,000';
    }
  }

  /// Flag emoji map aligned with iOS `RegionPickerView.regionFlag`.
  static String flagEmojiForId(String regionId) {
    const map = {
      'us': '🇺🇸', 'uk': '🇬🇧', 'ca': '🇨🇦', 'au': '🇦🇺', 'nz': '🇳🇿',
      'ie': '🇮🇪', 'de': '🇩🇪', 'fr': '🇫🇷', 'es': '🇪🇸', 'it': '🇮🇹',
      'nl': '🇳🇱', 'be': '🇧🇪', 'ch': '🇨🇭', 'at': '🇦🇹', 'se': '🇸🇪',
      'no': '🇳🇴', 'dk': '🇩🇰', 'fi': '🇫🇮', 'pl': '🇵🇱', 'jp': '🇯🇵',
      'cn': '🇨🇳', 'in': '🇮🇳', 'sg': '🇸🇬', 'hk': '🇭🇰', 'ae': '🇦🇪',
      'sa': '🇸🇦', 'za': '🇿🇦', 'br': '🇧🇷', 'mx': '🇲🇽', 'ar': '🇦🇷',
    };
    return map[regionId.toLowerCase()] ?? '🌍';
  }
}

/// Keys for local persistence (iOS `UserDefaults` parity).
abstract final class AppRegionPrefsKeys {
  static const selectedRegionId = 'property_pulse_selected_region_id';
  static const hasCompletedRegionSelection =
      'property_pulse_has_completed_region_selection';
}
