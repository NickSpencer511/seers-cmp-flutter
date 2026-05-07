library seers_cmp;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Seers CMP registered ID (IAB TCF)
const int _seersCmpId      = 158;
const int _seersCmpVersion = 1;
// Google Consent Mode v2 developer ID (reserved for future use)
// ignore: unused_element
const String _seersGoogleDevId = 'dNmU0M2';
// Allowlist of trusted Seers hosts — prevents SSRF
const List<String> _seersAllowedHosts = [
  'consents.dev',
  'seers.ai',
  'seersco.com',
  'cdn.consents.dev',
  'cdn.seersco.com',
];

bool _isAllowedHost(String urlString) {
  try {
    final uri = Uri.parse(urlString);
    return _seersAllowedHosts.any((h) =>
        uri.host == h || uri.host.endsWith('.$h'));
  } catch (_) {
    return false;
  }
}
const String _seersDefaultBadgeBase64 =
    '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';
const _seersDefaultLogoUrl =
    'https://seers-application-assets.s3.amazonaws.com/images/logo/seersco-logo.png';

// ─────────────────────────────────────────────────────────────
// IAB TCF v2.3 — IABTCF_* SharedPreferences keys
// Spec: https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework
// ─────────────────────────────────────────────────────────────

class SeersIABTCF {
  static const _statisticsPurposes  = [7, 8, 9];
  static const _marketingPurposes   = [1, 2, 3, 4];
  static const _preferencesPurposes = [5, 6];
  static const _base64url = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static Future<void> store({
    required bool necessary,
    required bool preferences,
    required bool statistics,
    required bool marketing,
    int cmpId = _seersCmpId,
    int cmpVersion = _seersCmpVersion,
  }) async {
    final pc = List.filled(10, '0');
    pc[0] = '1'; // necessary
    if (marketing)   { for (final p in _marketingPurposes)   { if (p <= 10) pc[p-1] = '1'; } }
    if (statistics)  { for (final p in _statisticsPurposes)  { if (p <= 10) pc[p-1] = '1'; } }
    if (preferences) { for (final p in _preferencesPurposes) { if (p <= 10) pc[p-1] = '1'; } }
    final pcStr = pc.join();

    final li = List.filled(10, '0');
    if (statistics)  { li[6] = '1'; li[7] = '1'; }
    if (preferences) { li[5] = '1'; }
    final liStr = li.join();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('IABTCF_CmpSdkID',                      cmpId);
    await prefs.setInt('IABTCF_CmpSdkVersion',                 cmpVersion);
    await prefs.setInt('IABTCF_PolicyVersion',                 1);
    await prefs.setInt('IABTCF_gdprApplies',                   1);
    await prefs.setInt('IABTCF_UseNonStandardTexts',           1);
    await prefs.setString('IABTCF_PurposeConsents',            pcStr);
    await prefs.setString('IABTCF_PurposeLegitimateInterests', liStr);
    await prefs.setString('IABTCF_SpecialFeaturesOptIns',      '00');
    await prefs.setString('IABTCF_VendorConsents',             '');
    await prefs.setString('IABTCF_VendorLegitimateInterests',  '');
    await prefs.setString('IABTCF_PublisherConsent',           pcStr);
    await prefs.setString('IABTCF_PublisherLegitimateInterests', liStr);
    await prefs.setString('IABTCF_TCString',                   _buildTCString(pc, cmpId, cmpVersion));
    await prefs.setInt('IABTCF_ConsentTimestamp',
        DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  static Future<Map<String, dynamic>> getTCData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'tcString':                    prefs.getString('IABTCF_TCString') ?? '',
      'cmpId':                       prefs.getInt('IABTCF_CmpSdkID') ?? 0,
      'cmpVersion':                  prefs.getInt('IABTCF_CmpSdkVersion') ?? 0,
      'gdprApplies':                 (prefs.getInt('IABTCF_gdprApplies') ?? 0) == 1,
      'purposeConsents':             prefs.getString('IABTCF_PurposeConsents') ?? '',
      'purposeLegitimateInterests':  prefs.getString('IABTCF_PurposeLegitimateInterests') ?? '',
      'specialFeaturesOptIns':       prefs.getString('IABTCF_SpecialFeaturesOptIns') ?? '',
      'vendorConsents':              prefs.getString('IABTCF_VendorConsents') ?? '',
      'publisherConsent':            prefs.getString('IABTCF_PublisherConsent') ?? '',
      'consentTimestamp':            prefs.getInt('IABTCF_ConsentTimestamp') ?? 0,
    };
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'IABTCF_CmpSdkID', 'IABTCF_CmpSdkVersion', 'IABTCF_PolicyVersion',
      'IABTCF_gdprApplies', 'IABTCF_UseNonStandardTexts', 'IABTCF_PurposeConsents',
      'IABTCF_PurposeLegitimateInterests', 'IABTCF_SpecialFeaturesOptIns',
      'IABTCF_VendorConsents', 'IABTCF_VendorLegitimateInterests',
      'IABTCF_PublisherConsent', 'IABTCF_PublisherLegitimateInterests',
      'IABTCF_TCString', 'IABTCF_ConsentTimestamp',
    ]) { await prefs.remove(key); }
  }

  static String _buildTCString(List<String> pc, int cmpId, int cmpVersion) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 100; // deciseconds
    var bits = '';
    bits += _intToBits(2,          6);
    bits += _intToBits(now,        36);
    bits += _intToBits(now,        36);
    bits += _intToBits(cmpId,      12);
    bits += _intToBits(cmpVersion, 12);
    bits += _intToBits(0,          6);
    bits += _langToBits('EN');
    bits += _intToBits(48,         12);
    bits += _intToBits(4,          6);
    bits += '0'; // isServiceSpecific
    bits += '0'; // useNonStandardTexts
    bits += '0' * 12; // specialFeatureOptIns
    bits += pc.join() + '0' * 14; // purposeConsents 24 bits
    bits += '0' * 24; // purposeLegitimateInterests
    bits += '0'; // purposeOneTreatment
    bits += _langToBits('AA'); // publisherCC
    bits += _intToBits(0, 16) + '0'; // vendorConsents
    bits += _intToBits(0, 16) + '0'; // vendorLI
    bits += _intToBits(0, 12); // numRestrictions
    return _base64urlEncode(bits);
  }

  static String _intToBits(int value, int length) {
    final bin = value.toRadixString(2);
    final padded = bin.padLeft(length, '0');
    return padded.length > length ? padded.substring(padded.length - length) : padded;
  }

  static String _langToBits(String lang) {
    final upper = lang.toUpperCase();
    final a = (upper.codeUnitAt(0) - 65).clamp(0, 25);
    final b = (upper.codeUnitAt(1) - 65).clamp(0, 25);
    return _intToBits(a, 6) + _intToBits(b, 6);
  }

  static String _base64urlEncode(String bits) {
    final rem = bits.length % 6;
    final padded = rem == 0 ? bits : bits + '0' * (6 - rem);
    final sb = StringBuffer();
    for (var i = 0; i < padded.length; i += 6) {
      final idx = int.parse(padded.substring(i, i + 6), radix: 2);
      if (idx < _base64url.length) sb.write(_base64url[idx]);
    }
    return sb.toString();
  }
}

// ─────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────

class SeersConsent {
  final String sdkKey;
  final String value; // 'agree' | 'disagree' | 'custom'
  final bool necessary;
  final bool preferences;
  final bool statistics;
  final bool marketing;
  final bool doNotSell;
  final Map<String, dynamic>? privacySignals;
  final String timestamp;
  final String expiry;

  SeersConsent({
    required this.sdkKey, required this.value,
    this.necessary = true, this.preferences = false,
    this.statistics = false, this.marketing = false,
    this.doNotSell = false, this.privacySignals,
    required this.timestamp, required this.expiry,
  });

  Map<String, dynamic> toJson() => {
    'sdk_key': sdkKey, 'value': value,
    'necessary': necessary, 'preferences': preferences,
    'statistics': statistics, 'marketing': marketing,
    'do_not_sell': doNotSell, 'privacy_signals': privacySignals,
    'timestamp': timestamp, 'expiry': expiry,
  };

  factory SeersConsent.fromJson(Map<String, dynamic> j) => SeersConsent(
    sdkKey: j['sdk_key'] ?? '', value: j['value'] ?? '',
    necessary: j['necessary'] ?? true, preferences: j['preferences'] ?? false,
    statistics: j['statistics'] ?? false, marketing: j['marketing'] ?? false,
    doNotSell: j['do_not_sell'] ?? false,
    privacySignals: j['privacy_signals'] is Map ? Map<String, dynamic>.from(j['privacy_signals']) : null,
    timestamp: j['timestamp'] ?? '', expiry: j['expiry'] ?? '',
  );
}

class SeersConsentMap {
  final SeersCategory statistics;
  final SeersCategory marketing;
  final SeersCategory preferences;
  final SeersCategory unclassified;
  SeersConsentMap({required this.statistics, required this.marketing, required this.preferences, required this.unclassified});
}

class SeersCategory {
  final bool allowed;
  final List<String> sdks;
  SeersCategory({required this.allowed, required this.sdks});
}

class SeersBannerPayload {
  final Map<String, dynamic>? dialogue;
  final Map<String, dynamic>? banner;
  final Map<String, dynamic>? language;
  final List<dynamic>? categories;
  final Map<String, dynamic> privacyFrameworks;
  final SeersBlockList blockList;
  final String? regulation;
  final String sdkKey;
  final List<Map<String, dynamic>> dpsList;
  SeersBannerPayload({this.dialogue, this.banner, this.language, this.categories, required this.privacyFrameworks, required this.blockList, this.regulation, required this.sdkKey, this.dpsList = const []});
}

class SeersBlockList {
  List<String> statistics   = [];
  List<String> marketing    = [];
  List<String> preferences  = [];
  List<String> unclassified = [];
}

// ─────────────────────────────────────────────────────────────
// SeersCMP
// ─────────────────────────────────────────────────────────────

class SeersCMP {
  
  SeersCMP._();

  static String? _settingsId;
  static Map<String, dynamic>? _config;
  static SeersBannerPayload? _lastPayload;
  static OverlayEntry? _bannerOverlay;
  static final _catMap = {3: 'statistics', 4: 'marketing', 5: 'preferences', 6: 'unclassified'};

  /// Last banner payload fetched from CDN — use this to show banner manually.
  static SeersBannerPayload? get lastPayload => _lastPayload;

  static Function(SeersBannerPayload)? _onShowBanner;
  static Function(SeersConsent, SeersConsentMap)? _onConsent;
  static Function(SeersConsent, SeersConsentMap)? _onConsentRestored;

  /// Initialize the SDK. Call once in main() before runApp().
  ///
  ///   await SeersCMP.initialize(
  ///     settingsId: 'YOUR_SDK_KEY',
  ///     onShowBanner: (payload) => showBanner(payload),
  ///   );
  static Future<void> initialize({
    required String settingsId,
    Function(SeersBannerPayload)? onShowBanner,
    Function(SeersConsent, SeersConsentMap)? onConsent,
    Function(SeersConsent, SeersConsentMap)? onConsentRestored,
  }) async {
    _settingsId       = settingsId;
    _onShowBanner     = onShowBanner;
    _onConsent        = onConsent;
    _onConsentRestored = onConsentRestored;

    // Check stored consent
    final stored = await getConsent();
    if (stored != null && !_isExpired(stored)) {
      final map = getConsentMap();
      _onConsentRestored?.call(stored, map);
      // Retry any queued consent in background
      _startRetryLoop(settingsId).ignore();
      return;
    }

    // Fetch config
    _config = await _fetchConfig(settingsId);
    if (_config == null || _config!['eligible'] != true) return;

    // Region check
    final region = await _checkRegion(settingsId);
    if (!_shouldShow(_config!['dialogue'], region)) return;

    final lang    = _resolveLanguage(_config!, region);
    final payload = SeersBannerPayload(
      dialogue:   _config!['dialogue'],
      banner:     _config!['banner'],
      language:   lang,
      categories: _config!['categories'],
      privacyFrameworks: getPrivacyFrameworks(),
      blockList:  _buildBlockList(_config!),
      regulation: region?['regulation'],
      sdkKey:     settingsId,
      dpsList:    (_config!['dps_list'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
    _lastPayload = payload;
    _onShowBanner?.call(payload);
    if (_onShowBanner == null && _navigatorKey?.currentContext != null) {
      _autoShowBanner(payload);
    }
  }

  static Future<void> _startRetryLoop(String sdkKey) async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('SeersConsentQueue_$sdkKey') == null) return;
      await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
      await retryQueuedConsent();
    }
  }

  /// Navigator key — set this to enable auto banner display without a callback.
  /// In main.dart:
  ///   SeersCMP.navigatorKey = GlobalKey<NavigatorState>();
  ///   MaterialApp(navigatorKey: SeersCMP.navigatorKey, ...)
  static GlobalKey<NavigatorState>? navigatorKey;

  static void _autoShowBanner(SeersBannerPayload payload) {
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    _bannerOverlay?.remove();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SeersBannerWidget(
        payload: payload,
        onDismiss: () {
          if (entry.mounted) entry.remove();
          if (identical(_bannerOverlay, entry)) _bannerOverlay = null;
        },
      ),
    );

    _bannerOverlay = entry;
    overlay.insert(entry);
  }

  static GlobalKey<NavigatorState>? get _navigatorKey => navigatorKey;

  /// Check if a specific SDK should be blocked.
  ///
  ///   final blocked = SeersCMP.shouldBlock('com.google.firebase.analytics');
  ///   if (!blocked) { await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true); }
  static bool shouldBlock(String identifier) => _checkBlock(identifier)['blocked'] == true;

  /// Returns the regulation type for the current session.
  /// Values: 'gdpr' | 'ccpa' | 'none'
  static String get regulation => _lastPayload?.regulation ?? 'gdpr';

  /// GDPR (region_selection 1 or 3): pre-block everything until user accepts.
  /// CCPA (region_selection 2): nothing pre-blocked; block only after explicit reject.
  /// none (region_selection 0): never block.
  static bool get isGdpr  => regulation == 'gdpr';
  static bool get isCcpa  => regulation == 'ccpa';
  static bool get isNone  => regulation == 'none';

  /// Call this BEFORE initialising any third-party SDK.
  /// Returns true if the SDK should be blocked right now.
  ///
  /// GDPR  → blocked until consent given (pre-block)
  /// CCPA  → NOT blocked until user explicitly opts out
  /// none  → never blocked
  ///
  /// Example:
  ///   if (!SeersCMP.shouldBlockNow('com.google.firebase.analytics')) {
  ///     await Firebase.initializeApp();
  ///   }
  static Future<bool> shouldBlockNow(String identifier) async {
    final stored = await getConsent();

    // No regulation or region_selection=0 → never block
    if (isNone) return false;

    // Consent already given — check per-category
    if (stored != null && !_isExpired(stored)) {
      return _checkBlockWithConsent(identifier, stored);
    }

    // No consent yet:
    // GDPR → pre-block everything in the block list
    if (isGdpr) return _checkBlock(identifier)['blocked'] == true;

    // CCPA → don't pre-block (opt-out model)
    return false;
  }

  /// Check block status using stored consent categories.
  static bool _checkBlockWithConsent(String identifier, SeersConsent consent) {
    final result = _checkBlock(identifier);
    if (result['blocked'] != true) return false;
    final cat = result['category'] as String?;
    switch (cat) {
      case 'statistics':  return !consent.statistics;
      case 'marketing':   return !consent.marketing;
      case 'preferences': return !consent.preferences;
      default:            return false;
    }
  }

  /// Get full consent map.
  static SeersConsentMap getConsentMap() => _buildConsentMap();

  static Map<String, dynamic> getPrivacyFrameworks() => _getPrivacyFrameworks();

  static bool frameworkEnabled(String key) {
    dynamic node = _getPrivacyFrameworks();
    for (final part in key.split('.')) {
      if (node is Map && node.containsKey(part)) {
        node = node[part];
      } else {
        return false;
      }
    }
    return node == true || (node is Map && node['enabled'] == true);
  }

  static Map<String, dynamic> getConsentSignals({
    String value = 'custom',
    bool preferences = false,
    bool statistics = false,
    bool marketing = false,
    bool? doNotSell,
    String? attStatus,
  }) => _getConsentSignals(
    value: value,
    preferences: preferences,
    statistics: statistics,
    marketing: marketing,
    doNotSell: doNotSell,
    attStatus: attStatus,
  );

  /// Get stored consent.
  static Future<SeersConsent?> getConsent() async {
    if (_settingsId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('SeersConsent_$_settingsId');
    if (raw == null) return null;
    try { return SeersConsent.fromJson(jsonDecode(raw)); } catch (e) { return null; }
  }

  /// Save consent after user makes a choice.
  static Future<void> saveConsent({
    required String value,
    bool preferences = false,
    bool statistics  = false,
    bool marketing   = false,
    bool? doNotSell,
    String? attStatus,
  }) async {
    if (_settingsId == null) return;
    final expire = (_config?['dialogue']?['agreement_expire'] as int?) ?? 365;
    final expiry = DateTime.now().add(Duration(days: expire));
    final privacySignals = _getConsentSignals(
      value: value,
      preferences: preferences,
      statistics: statistics,
      marketing: marketing,
      doNotSell: doNotSell,
      attStatus: attStatus,
    );
    final consent = SeersConsent(
      sdkKey: _settingsId!, value: value,
      preferences: preferences, statistics: statistics, marketing: marketing,
      doNotSell: privacySignals['universalOptOut']?['doNotSell'] == true,
      privacySignals: privacySignals,
      timestamp: DateTime.now().toIso8601String(),
      expiry:    expiry.toIso8601String(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('SeersConsent_$_settingsId', jsonEncode(consent.toJson()));
    // Store IAB TCF v2.3 keys (only if enabled in dashboard)
    if (_config?['dialogue']?['enable_iab_tcf'] == true) {
      await SeersIABTCF.store(
        necessary: true, preferences: preferences,
        statistics: statistics, marketing: marketing,
      );
    }
    _logConsent(_settingsId!, consent);
    final map = _buildConsentMap(consent);
    _onConsent?.call(consent, map);
  }

  /// Returns IAB TCF v2.3 consent data (IABTCF_* keys).
  static Future<Map<String, dynamic>> getTCData() => SeersIABTCF.getTCData();

  // ─────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchConfig(String sdkKey) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final url = 'https://cdn.seersco.com/mobile/configs/$sdkKey.json?v=$ts';
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (r.statusCode == 404) return {'eligible': false, 'message': 'App not found'};
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        if (decoded is Map<String, dynamic>) {
          // Cache on success
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('SeersConfig_$sdkKey', r.body);
          return decoded;
        }
      }
    } catch (_) {}
    // Network failed — use cached config
    return await _loadCachedConfig(sdkKey);
  }

  static Future<Map<String, dynamic>?> _loadCachedConfig(String sdkKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('SeersConfig_$sdkKey');
    if (raw == null) return null;
    try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>?> _checkRegion(String sdkKey) async {
    final host = _config?['cx_host'];
    if (host == null || host.toString().isEmpty || !_isAllowedHost(host.toString())) {
      return {'regulation': 'gdpr', 'eligible': true};
    }
    try {
      // Send app package name in header so backend can verify app identity
      final headers = <String, String>{};
      if (_appId != null) headers['X-App-ID'] = _appId!;
      final r = await http.get(
        Uri.parse('$host/api/mobile/sdk/$sdkKey'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return {'regulation': 'gdpr', 'eligible': true};
  }

  /// Optional: set your app's package/bundle ID for security verification.
  /// If set, the backend will reject requests from apps with a different ID.
  ///
  ///   SeersCMP.appId = 'com.company.myapp';
  static String? appId;
  static String? get _appId => appId;

  static SeersBlockList _buildBlockList(Map<String, dynamic> config) {
    final list    = SeersBlockList();
    final mode    = config['blocking_mode']    as String? ?? 'none';
    final domains = config['blocking_domains'] as List?   ?? [];
    if (mode == 'none' || domains.isEmpty) return list;

    for (final item in domains) {
      final identifier = mode == 'prior_consent' ? item['d'] : item['src'];
      final catId      = mode == 'prior_consent' ? item['c'] : item['category'];
      final cat        = _catMap[catId] ?? 'unclassified';
      if (identifier == null) continue;
      switch (cat) {
        case 'statistics':   list.statistics.add(identifier.toString());   break;
        case 'marketing':    list.marketing.add(identifier.toString());    break;
        case 'preferences':  list.preferences.add(identifier.toString());  break;
        default:             list.unclassified.add(identifier.toString()); break;
      }
    }
    return list;
  }

  static Map<String, dynamic> _checkBlock(String identifier) {
    final list = _buildBlockList(_config ?? {});
    final id   = identifier.toLowerCase();
    final cats = {
      'statistics':   list.statistics,
      'marketing':    list.marketing,
      'preferences':  list.preferences,
      'unclassified': list.unclassified,
    };
    for (final entry in cats.entries) {
      for (final sdk in entry.value) {
        if (id.contains(sdk.toLowerCase())) {
          return {'blocked': true, 'category': entry.key};
        }
      }
    }
    return {'blocked': false, 'category': null};
  }

  static SeersConsentMap _buildConsentMap([SeersConsent? consent]) {
    final list = _buildBlockList(_config ?? {});
    return SeersConsentMap(
      statistics:   SeersCategory(allowed: consent?.statistics  ?? false, sdks: list.statistics),
      marketing:    SeersCategory(allowed: consent?.marketing   ?? false, sdks: list.marketing),
      preferences:  SeersCategory(allowed: consent?.preferences ?? false, sdks: list.preferences),
      unclassified: SeersCategory(allowed: false,                          sdks: list.unclassified),
    );
  }

  static Map<String, dynamic> _getPrivacyFrameworks() {
    final d = (_config?['dialogue'] as Map?) ?? {};
    final platform = _config?['platform'];
    return (_config?['privacy_frameworks'] as Map?)?.cast<String, dynamic>() ?? {
      'google_consent_mode_v2': {'enabled': d['apply_google_consent'] == true},
      'iab_tcf': {'enabled': d['enable_iab_tcf'] == true, 'version': '2.3'},
      'apple_att': {'enabled': d['apple_att'] == true, 'applies': ['ios', 'both', 'react_native', 'flutter'].contains(platform)},
      'google_play_disclosure': {'enabled': d['google_play_disclosure'] == true, 'applies': ['android', 'both', 'react_native', 'flutter'].contains(platform)},
      'universal_opt_out': {'enabled': d['universal_opt_out'] == true, 'signal': 'do_not_sell_or_share'},
      'conditional': {
        'gpp': d['enable_gpp'] == true,
        'microsoft_clarity': d['microsoft_clarity_consent'] == true,
        'meta_facebook_sdk': d['meta_sdk_consent'] == true,
        'microsoft_ads': d['microsoft_ads_consent'] == true,
        'amazon_ads': d['amazon_ads_consent'] == true,
      },
    };
  }

  static Map<String, dynamic> _getConsentSignals({
    String value = 'custom',
    bool preferences = false,
    bool statistics = false,
    bool marketing = false,
    bool? doNotSell,
    String? attStatus,
  }) {
    final frameworks = _getPrivacyFrameworks();
    final optOut = doNotSell ?? value == 'disagree';
    return {
      'appleATT': {'enabled': frameworks['apple_att']?['enabled'] == true, 'applies': frameworks['apple_att']?['applies'] == true, 'status': attStatus},
      'googlePlayDisclosure': {'enabled': frameworks['google_play_disclosure']?['enabled'] == true, 'applies': frameworks['google_play_disclosure']?['applies'] == true},
      'googleConsentModeV2': {
        'enabled': frameworks['google_consent_mode_v2']?['enabled'] == true,
        'analytics_storage': statistics ? 'granted' : 'denied',
        'ad_storage': marketing ? 'granted' : 'denied',
        'ad_user_data': marketing ? 'granted' : 'denied',
        'ad_personalization': marketing ? 'granted' : 'denied',
      },
      'iabTCF': {'enabled': frameworks['iab_tcf']?['enabled'] == true, 'version': frameworks['iab_tcf']?['version'] ?? '2.3'},
      'universalOptOut': {'enabled': frameworks['universal_opt_out']?['enabled'] == true, 'signal': frameworks['universal_opt_out']?['signal'] ?? 'do_not_sell_or_share', 'doNotSell': optOut},
      'conditional': frameworks['conditional'] ?? {},
    };
  }

  /// Builds consent map with actual allowed values from stored consent.
  static Future<SeersConsentMap> buildConsentMapWithConsent() async {
    final list    = _buildBlockList(_config ?? {});
    final consent = await getConsent();
    return SeersConsentMap(
      statistics:   SeersCategory(allowed: consent?.statistics  ?? false, sdks: list.statistics),
      marketing:    SeersCategory(allowed: consent?.marketing   ?? false, sdks: list.marketing),
      preferences:  SeersCategory(allowed: consent?.preferences ?? false, sdks: list.preferences),
      unclassified: SeersCategory(allowed: false,                          sdks: list.unclassified),
    );
  }

  static bool _shouldShow(dynamic dialogue, Map<String, dynamic>? region) {
    if (dialogue == null) return false;

    // region_selection=0 → never show banner
    final regionSelection = dialogue['region_selection'];
    final selectionInt = regionSelection is int
        ? regionSelection
        : int.tryParse(regionSelection?.toString() ?? '') ?? 1;
    if (selectionInt == 0) return false;

    if (dialogue['region_detection'] == true || dialogue['region_detection'] == 1) {
      return region?['eligible'] == true && region?['regulation'] != 'none';
    }
    return true;
  }

  static Map<String, dynamic>? _resolveLanguage(Map<String, dynamic> config, Map<String, dynamic>? region) {
    if (config['language'] != null) return config['language'];
    final langs = config['languages'] as List?;
    if (langs == null || langs.isEmpty) return null;
    final code = region?['data']?['country_iso_code']
        ?? config['dialogue']?['default_language']
        ?? 'GB';
    try {
      return langs.firstWhere(
        (l) => l['country_code'] == code,
        orElse: () => langs.first,
      ) as Map<String, dynamic>?;
    } catch (_) {
      return langs.isNotEmpty ? langs.first as Map<String, dynamic>? : null;
    }
  }

  static bool _isExpired(SeersConsent consent) {
    try { return DateTime.now().isAfter(DateTime.parse(consent.expiry)); } catch (e) { return true; }
  }

  // Returns a stable anonymous device ID scoped to this sdk_key.
  // Generated once, stored in SharedPreferences, never changes.
  // Used for MAU deduplication — not linked to any PII.
  static Future<String> _getOrCreateDeviceId(String sdkKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'SeersDeviceId_$sdkKey';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final newId = _generateUuid();
    await prefs.setString(key, newId);
    return newId;
  }

  static String _generateUuid() {
    final r = Random.secure();
    String hex(int n) => r.nextInt(256).toRadixString(16).padLeft(2, '0');
    return '${hex(0)}${hex(0)}${hex(0)}${hex(0)}-${hex(0)}${hex(0)}-4${hex(0).substring(1)}-'
        '${(8 + r.nextInt(4)).toRadixString(16)}${hex(0).substring(1)}-'
        '${hex(0)}${hex(0)}${hex(0)}${hex(0)}${hex(0)}${hex(0)}';
  }

  static Future<void> _logConsent(String sdkKey, SeersConsent consent) async {
    final host = _config?['cx_host'] ?? '';
    if (host.toString().isEmpty || !_isAllowedHost(host.toString())) { await _queueConsent(sdkKey, consent); return; }
    try {
      final deviceId = await _getOrCreateDeviceId(sdkKey);
      final resp = await http.post(
        Uri.parse('$host/api/mobile/sdk/save-consent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sdk_key':     sdkKey,
          'platform':    _config?['platform'] ?? 'flutter',
          'consent':     consent.value,
          'categories':  {
            'necessary':   consent.necessary,
            'preferences': consent.preferences,
            'statistics':  consent.statistics,
            'marketing':   consent.marketing,
          },
          'do_not_sell': consent.doNotSell,
          'privacy_signals': consent.privacySignals,
          'timestamp':   consent.timestamp,
          // Stable anonymous device ID for MAU deduplication — not PII
          'device_id':   deviceId,
          'app_version': appVersion,
          'email':       userEmail,
        }),
      );
      if (resp.statusCode == 200) {
        await _clearQueuedConsent(sdkKey);
      } else {
        await _queueConsent(sdkKey, consent);
      }
    } catch (_) {
      await _queueConsent(sdkKey, consent);
    }
  }

  static Future<void> _queueConsent(String sdkKey, SeersConsent consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('SeersConsentQueue_$sdkKey', jsonEncode(consent.toJson()));
  }

  static Future<void> _clearQueuedConsent(String sdkKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('SeersConsentQueue_$sdkKey');
  }

  /// Call when app regains connectivity to flush any queued consent log.
  static Future<void> retryQueuedConsent() async {
    if (_settingsId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('SeersConsentQueue_$_settingsId');
    if (raw == null) return;
    try {
      final consent = SeersConsent.fromJson(jsonDecode(raw));
      await _logConsent(_settingsId!, consent);
    } catch (_) {}
  }

  /// Optional: set app version for consent log enrichment.
  ///   SeersCMP.appVersion = '2.1.0';
  static String? appVersion;

  /// Optional: set user email for consent log enrichment.
  ///   SeersCMP.userEmail = 'user@example.com';
  static String? userEmail;
}

// ─────────────────────────────────────────────────────────────
// Flutter Banner Widget
// ─────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────
// SeersBannerWidget — pixel-perfect match to MobileDefaultBanner.vue
// CSS values scaled from 190px preview to real screen proportions
// ─────────────────────────────────────────────────────────────

class SeersBannerWidget extends StatefulWidget {
  final SeersBannerPayload payload;
  final VoidCallback onDismiss;
  const SeersBannerWidget({Key? key, required this.payload, required this.onDismiss}) : super(key: key);

  @override
  State<SeersBannerWidget> createState() => _SeersBannerWidgetState();
}

class _SeersBannerWidgetState extends State<SeersBannerWidget> {
  bool _showPref = false;
  bool _dpsView   = false;   // true = showing DPS detail for a category
  String _dpsCat  = '';      // which category's DPS is shown
  String _dpsSearch = '';    // search query inside DPS detail view
  bool _bannerVisible = true;
  bool _badgeVisible = false;
  Timer? _badgeTimer;
  final Map<String, bool> _toggles = {'preferences': false, 'statistics': false, 'marketing': false};
  final Set<String> _expanded = {};

  Map<String, dynamic>? get _b => widget.payload.banner;
  Map<String, dynamic>? get _l => widget.payload.language;
  Map<String, dynamic>? get _d => widget.payload.dialogue;

  // ── Colors — exact same fields as frontend ──
  Color get _bg       => _c(_b?['banner_bg_color']        ?? '#ffffff');
  Color get _titleClr => _c(_b?['title_text_color']       ?? '#1a1a1a');
  Color get _bodyClr  => _c(_b?['body_text_color']        ?? '#1a1a1a');
  Color get _agreeClr => _c(_b?['agree_btn_color']        ?? '#3b6ef8');
  Color get _agreeTxt => _c(_b?['agree_text_color']       ?? '#ffffff');
  Color get _decClr   => _c(_b?['disagree_btn_color']     ?? '#1a1a2e');
  Color get _decTxt   => _c(_b?['disagree_text_color']    ?? '#ffffff');
  // prefFullStyle uses body_text_color for both color and border

  // ── Font size from banner.font_size ──
  // Keep mobile output aligned with the Vue preview instead of scaling it up.
  double get _scale    => 1.0;
  double get _fs        => (double.tryParse(_b?['font_size']?.toString() ?? '12') ?? 12).clamp(10, 16).toDouble();
  double get _titleFs   => _fs + 2;
  double get _catBodyFs => _fs - 1;
  double get _p         => 12 * _scale;  // base padding
  double get _prefFs        => _fs;
  double get _prefTitleFs   => _prefFs + 2;
  double get _prefCatNameFs => _prefFs + 1;
  double get _prefCatBodyFs => _prefFs - 1;
  double get _prefArrowFs   => max(_prefFs * 0.75, 9.0);
  String? get _fontFamily {
    final value = (_b?['font_style'] ?? '').toString().trim().toLowerCase();
    if (value.isEmpty || value == 'none' || value == 'inherit') return null;
    if (value == 'arial' || value == 'inter' || value == 'spezia') return 'Arial';
    return value;
  }

  // ── Button shape from button_type ──
  String get _btnType => (_b?['button_type'] ?? 'default').toString();
  BorderRadius get _btnR {
    if (_btnType.contains('rounded')) return BorderRadius.circular(20); // shape-rounded
    if (_btnType.contains('flat'))    return BorderRadius.zero;          // shape-flat
    return BorderRadius.circular(4);                                      // shape-default + stroke
  }
  bool get _isStroke => _btnType.contains('stroke');

  // ── prefFullStyle border color = body_text_color ──
  Color get _prefBorder => _bodyClr;

  // ── Display style / layout / position ──
  String get _tmpl => (_d?['mobile_template'] ?? 'popup').toString();
  String get _lay  => (_b?['layout']   ?? 'default').toString();
  String get _pos  => (_b?['position'] ?? 'bottom').toString();

  // showHandle only when layout === 'rounded'
  bool get _handle => _lay == 'rounded';

  bool get _allowReject => _d?['allow_reject'] == true || _d?['allow_reject'] == 1;
  bool get _poweredBy   => _d?['powered_by']   == true || _d?['powered_by']   == 1;
  bool get _hasBadge    => _d?['has_badge']    == true || _d?['has_badge']    == 1;
  int get _bannerTimeout => int.tryParse(_d?['banner_timeout']?.toString() ?? '') ?? 0;
  String get _logoSrc => (_d?['logo_link']?.toString().isNotEmpty ?? false)
      ? _d!['logo_link'].toString()
      : _seersDefaultLogoUrl;
  bool get _showLogo => (_d?['logo_status'] ?? 'default').toString() != 'none';
  String? get _customBadgeSrc {
    final badgeStatus = (_d?['badge_status'] ?? '').toString();
    final badgeLink = _d?['badge_link']?.toString();
    if (badgeStatus == 'custom' && badgeLink != null && badgeLink.isNotEmpty) {
      return badgeLink;
    }
    return null;
  }

  // ── Language fields ──
  String get _body        => _l?['body']                ?? 'We use cookies to personalize content and ads, to provide social media features and to analyze our traffic.';
  String get _title       => _l?['title']               ?? 'We use cookies';
  String get _btnAgree    => _l?['btn_agree_title']     ?? 'Allow All';
  String get _btnDecline  => _l?['btn_disagree_title']  ?? 'Disable All';
  String get _btnPref     => _l?['btn_preference_title']?? 'Cookie settings';
  String get _btnSave     => _l?['btn_save_my_choices'] ?? 'Save my choices';
  String get _aboutCookies=> _l?['about_cookies']       ?? 'About Our Cookies';
  String get _alwaysActive=> _l?['always_active']       ?? 'Always Active';

  List<Map<String, String>> get _cats => [
    {'key': 'necessary',   'label': _l?['necessory_title']  ?? 'Necessary',   'desc': _l?['necessory_body']  ?? 'Required for the website to function. Cannot be switched off.'},
    {'key': 'preferences', 'label': _l?['preference_title'] ?? 'Preferences', 'desc': _l?['preference_body'] ?? 'Allow the website to remember choices you make.'},
    {'key': 'statistics',  'label': _l?['statistics_title'] ?? 'Statistics',  'desc': _l?['statistics_body'] ?? 'Help us understand how visitors interact with the website.'},
    {'key': 'marketing',   'label': _l?['marketing_title']  ?? 'Marketing',   'desc': _l?['marketing_body']  ?? 'Used to track visitors and display relevant advertisements.'},
  ];

  // DPS list from config — grouped by category key
  static const _catIdMap = {1: 'necessary', 2: 'unclassified', 3: 'statistics', 4: 'marketing', 5: 'preferences'};

  List<Map<String, dynamic>> _getDpsForCat(String catKey) {
    final dpsList = widget.payload.dpsList;
    return dpsList.where((d) {
      final cat = _catIdMap[d['script_category_id'] as int? ?? 0] ?? 'unclassified';
      return cat == catKey;
    }).toList();
  }

  BorderRadius get _dialogRadius {
    if (_lay == 'rounded') return BorderRadius.circular(20);
    if (_lay == 'flat') return BorderRadius.zero;
    return BorderRadius.circular(10);
  }

  BorderRadius get _sheetRadius {
    if (_lay == 'flat') return BorderRadius.zero;
    if (_lay == 'rounded') {
      return _pos == 'top'
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : const BorderRadius.vertical(top: Radius.circular(16));
    }
    return _pos == 'top'
        ? const BorderRadius.vertical(bottom: Radius.circular(14))
        : const BorderRadius.vertical(top: Radius.circular(14));
  }

  BorderRadius get _popupRadius => const BorderRadius.vertical(top: Radius.circular(12));

  @override
  void initState() {
    super.initState();
    _syncToggleDefaults();
  }

  @override
  void didUpdateWidget(covariant SeersBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      _resetBannerState();
      _syncToggleDefaults();
    }
  }

  @override
  void dispose() {
    _clearBadgeTimer();
    super.dispose();
  }

  void _clearBadgeTimer() {
    _badgeTimer?.cancel();
    _badgeTimer = null;
  }

  bool _boolValue(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return fallback;
  }

  void _syncToggleDefaults() {
    _toggles
      ..['preferences'] = _boolValue(_d?['preferences_checked'])
      ..['statistics'] = _boolValue(_d?['statistics_checked'])
      ..['marketing'] = _boolValue(_d?['targeting_checked']);
  }

  void _resetBannerState() {
    _clearBadgeTimer();
    if (!mounted) return;
    setState(() {
      _showPref  = false;
      _dpsView   = false;
      _dpsCat    = '';
      _dpsSearch = '';
      _bannerVisible = true;
      _badgeVisible  = false;
    });
  }

  void _showBadgeOnly() {
    _clearBadgeTimer();
    if (_hasBadge) {
      setState(() {
        _showPref = false;
        _bannerVisible = false;
        _badgeVisible = true;
      });
      return;
    }

    widget.onDismiss();
  }

  void _scheduleBannerTimeout() {
    if (!_hasBadge || _bannerTimeout <= 0) return;
    _badgeTimer = Timer(Duration(seconds: _bannerTimeout), () {
      if (!mounted) return;
      setState(() {
        _showPref = false;
        _bannerVisible = false;
        _badgeVisible = true;
      });
    });
  }

  void _reopenBannerFromBadge() {
    _clearBadgeTimer();
    setState(() {
      _badgeVisible = false;
      _bannerVisible = true;
    });
    _scheduleBannerTimeout();
  }

  @override
  Widget build(BuildContext context) {
    if (_showPref) return _withBannerFont(_prefPanel());
    if (_dpsView)   return _withBannerFont(_dpsPanel());
    if (_badgeVisible && _hasBadge) return _withBannerFont(_badgeOverlay());
    if (!_bannerVisible) return const SizedBox.shrink();
    if (_tmpl == 'dialog') {
      return _withBannerFont(Material(color: Colors.transparent, child: Center(child: _dialogBanner())));
    }
    return _withBannerFont(Material(
      color: Colors.transparent,
      child: Align(
        alignment: _tmpl == 'bottom_sheet' && _pos == 'top'
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        child: _tmpl == 'bottom_sheet' ? _bottomSheet() : _popup(),
      ),
    ));
  }

  Widget _withBannerFont(Widget child) {
    if (_fontFamily == null) return child;
    return DefaultTextStyle.merge(
      style: TextStyle(fontFamily: _fontFamily),
      child: child,
    );
  }

  // ══════════════════════════════════════════
  // POPUP — .consent-popup
  // padding: 12px 12px 10px
  // 3 stacked buttons: stk-btn (padding: 5px 8px, margin-bottom: 5px, font-weight:700, line-height:1.4)
  // ══════════════════════════════════════════
  Widget _popup() {
    return Container(
      decoration: BoxDecoration(color: _bg, borderRadius: _popupRadius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, -4))]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.42)),
        SizedBox(height: _p * 0.58),
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false))],
        _stkOutline(_btnPref, () {
          _clearBadgeTimer();
          setState(() => _showPref = true);
        }),
        if (_poweredBy) ...[SizedBox(height: _p * 0.25),
          Text('Powered by Seers', textAlign: TextAlign.center, style: TextStyle(fontSize: _fs * 0.7, color: const Color(0xFFaaaaaa)))],
      ]),
    );
  }

  // ══════════════════════════════════════════
  // BOTTOM SHEET — .consent-sheet
  // padding: 10px 10px 8px
  // btn-row-primary: gap:4px, margin-bottom:4px
  // btn-item: padding:4px, font-weight:600
  // btn-pref-full: padding:4px 6px, margin-bottom:3px, font-weight:600
  // ══════════════════════════════════════════
  Widget _bottomSheet() {
    return Container(
      decoration: BoxDecoration(color: _bg, borderRadius: _sheetRadius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, -2))]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_handle) Center(child: Container(width: _p * 2.67, height: _p * 0.33, margin: EdgeInsets.only(bottom: _p * 0.5),
            decoration: BoxDecoration(color: const Color(0xFFcccccc), borderRadius: BorderRadius.circular(_p * 0.17)))),
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.32)),
        SizedBox(height: _p * 0.33),
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.42)),
        SizedBox(height: _p * 0.58),
        Row(children: [
          if (_allowReject) ...[
            Expanded(child: _btnItem(_btnDecline, _decClr, _decTxt, () => _save('disagree', false, false, false))),
            SizedBox(width: _p * 0.33),
          ],
          Expanded(child: _btnItem(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true))),
        ]),
        SizedBox(height: _p * 0.33),
        _prefFullBtn(_btnPref, () {
          _clearBadgeTimer();
          setState(() => _showPref = true);
        }),
        if (_poweredBy) ...[SizedBox(height: _p * 0.25),
          Text('Powered by Seers', textAlign: TextAlign.center, style: TextStyle(fontSize: _fs * 0.7, color: const Color(0xFFaaaaaa)))],
      ]),
    );
  }

  // ══════════════════════════════════════════
  // DIALOG — .consent-modal, width:82%, padding:12px
  // ══════════════════════════════════════════
  Widget _dialogBanner() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.88,
      decoration: BoxDecoration(color: _bg, borderRadius: _dialogRadius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24)]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.32)),
        SizedBox(height: _p * 0.33),
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.42)),
        SizedBox(height: _p * 0.67),
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false))],
        _stkOutline(_btnPref, () {
          _clearBadgeTimer();
          setState(() => _showPref = true);
        }),
      ]),
    );
  }

  // ══════════════════════════════════════════
  // PREFERENCE PANEL — .pref-modal (full screen)
  // .pref-scroll: padding:8px 10px 6px, gap:4px
  // .pref-footer: padding:6px 10px 8px, border-top:1px solid #e0e0e0
  // ══════════════════════════════════════════
  Widget _prefPanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, -8))],
        ),
        child: Column(children: [
            // pref-scroll
            Expanded(child: SingleChildScrollView(
              padding: EdgeInsets.all(_p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _prefLogo()),
                    GestureDetector(
                      onTap: () => setState(() => _showPref = false),
                      child: Text('✕', style: TextStyle(fontSize: _prefFs, color: _titleClr, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                SizedBox(height: _p * 0.17),
                Text(_aboutCookies, style: TextStyle(fontSize: _prefTitleFs, fontWeight: FontWeight.w700, color: _titleClr, height: 1.32)),
                SizedBox(height: _p * 0.33),
                Text(_body, style: TextStyle(fontSize: _prefFs, color: _bodyClr.withValues(alpha: 0.85), height: 1.42)),
                SizedBox(height: _p * 0.33),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Read Cookie Policy', style: TextStyle(fontSize: _prefFs, fontWeight: FontWeight.w600,
                      color: _agreeClr, decoration: TextDecoration.underline, decorationColor: _agreeClr)),
                  SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: _prefFs, color: _agreeClr),
                ]),
                SizedBox(height: _p * 0.5),
                _prefActionBtn(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true), fontSize: _prefFs),
                SizedBox(height: _p * 0.33),
                _prefActionBtn(_btnDecline, const Color(0xFF1a1a2e), Colors.white, () => _save('disagree', false, false, false), fontSize: _prefFs),
                SizedBox(height: _p * 0.67),
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFe0e0e0)))),
                  padding: EdgeInsets.only(top: _p * 0.33),
                  child: Column(children: _cats.map(_catRow).toList()),
                ),
              ]),
            )),
            Container(
              decoration: BoxDecoration(color: _bg,
                border: const Border(top: BorderSide(color: Color(0xFFe0e0e0))),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))]),
              padding: EdgeInsets.fromLTRB(_p, _p, _p, _p + MediaQuery.of(context).padding.bottom),
              // pref-save-btn: padding:5px 6px, font-weight:700, border-radius:4px
                  child: _prefActionBtn(_btnSave, _agreeClr, _agreeTxt,
                  () => _save('custom', _toggles['preferences']!, _toggles['statistics']!, _toggles['marketing']!), isSave: true, fontSize: _prefFs),
            ),
          ]),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // DPS DETAIL PANEL
  // Equivalent of default.js SeersCMPBannerCookieSearchContainer
  // Shows when user taps "Cookie Details" inside a category accordion.
  // Back button (← Cookie List) returns to preferences panel.
  // ──────────────────────────────────────────────────────
  Widget _dpsPanel() {
    final allDps    = _getDpsForCat(_dpsCat);
    final query     = _dpsSearch.toLowerCase();
    final filtered  = query.isEmpty
        ? allDps
        : allDps.where((d) {
            final title    = (d['title']    ?? '').toString().toLowerCase();
            final provider = (d['provider'] ?? '').toString().toLowerCase();
            return title.contains(query) || provider.contains(query);
          }).toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: _bg,
        child: Column(children: [
          // Header: back button + search — matches default.js SeersCMPBannerCookieSearchContainer
          Container(
            padding: EdgeInsets.fromLTRB(_p, _p * 0.75, _p, _p * 0.5),
            decoration: BoxDecoration(
              color: _bg,
              border: const Border(bottom: BorderSide(color: Color(0xFFe0e0e0))),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Back link — matches default.js back-to-seers-cmp-detail
              GestureDetector(
                onTap: () => setState(() { _dpsView = false; }),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_back_ios, size: _fs * 0.85, color: _agreeClr),
                  SizedBox(width: 4),
                  Text(
                    _l?['cookie_list'] ?? 'Cookie List',
                    style: TextStyle(fontSize: _fs, color: _agreeClr, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              SizedBox(height: _p * 0.5),
              // Search bar — matches default.js seers-cmp-search-bar
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFDBDBDB)),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _dpsSearch = v),
                  style: TextStyle(fontSize: _fs),
                  decoration: InputDecoration(
                    hintText: 'Cookie Search...',
                    hintStyle: TextStyle(fontSize: _fs, color: const Color(0xFFaaaaaa)),
                    prefixIcon: Icon(Icons.search, size: _fs * 1.1, color: const Color(0xFFaaaaaa)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ]),
          ),

          // DPS list
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No services found.', style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.5))))
                : ListView.separated(
                    padding: EdgeInsets.all(_p),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFf0f0f0)),
                    itemBuilder: (_, i) => _dpsRow(filtered[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  // Single DPS row — matches default.js cookie detail table row pattern
  Widget _dpsRow(Map<String, dynamic> dps) {
    final title      = dps['title']              ?? '';
    final provider   = dps['provider']           ?? '';
    final desc       = dps['description']        ?? '';
    final retention  = dps['retention_period']   ?? '';
    final policyUrl  = dps['privacy_policy_url'] ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: _p * 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: _fs, fontWeight: FontWeight.w600, color: _bodyClr))),
          if (policyUrl.isNotEmpty)
            GestureDetector(
              onTap: () { /* open URL via url_launcher if available */ },
              child: Text(
                'Privacy Policy',
                style: TextStyle(fontSize: _catBodyFs, color: _agreeClr,
                    decoration: TextDecoration.underline, decorationColor: _agreeClr),
              ),
            ),
        ]),
        if (provider.isNotEmpty) ...[  
          SizedBox(height: 2),
          Text(provider, style: TextStyle(fontSize: _catBodyFs, color: _bodyClr.withValues(alpha: 0.6))),
        ],
        if (desc.isNotEmpty) ...[  
          SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: _catBodyFs, height: 1.4, color: _bodyClr.withValues(alpha: 0.75))),
        ],
        if (retention.isNotEmpty) ...[  
          SizedBox(height: 4),
          Row(children: [
            Text('Retention: ', style: TextStyle(fontSize: _catBodyFs, fontWeight: FontWeight.w600, color: _bodyClr.withValues(alpha: 0.6))),
            Text(retention,     style: TextStyle(fontSize: _catBodyFs, color: _bodyClr.withValues(alpha: 0.6))),
          ]),
        ],
      ]),
    );
  }

  Widget _badgeOverlay() {
    final badgeSize = max(_p * 2.6, 34.0);

    return SizedBox.expand(
      child: Stack(
        children: [
          const IgnorePointer(child: SizedBox.expand()),
          Positioned(
            left: _p,
            bottom: _p + MediaQuery.of(context).padding.bottom * 0.25,
            child: Semantics(
              button: true,
              label: 'Open cookie settings',
              child: GestureDetector(
                onTap: _reopenBannerFromBadge,
                child: SizedBox(width: badgeSize, height: badgeSize, child: _badgeImage(badgeSize)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category row — .pref-cat-wrap: border:1px #e0e0e0, border-radius:5px ──
  Widget _catRow(Map<String, String> cat) {
    final key   = cat['key']!;
    final label = cat['label']!;
    final desc  = cat['desc']!;
    final isNec = key == 'necessary';
    final isOpen= _expanded.contains(key);
    final togOn = isNec ? true : (_toggles[key] ?? false);

    return Container(
      margin: EdgeInsets.only(bottom: _p * 0.25),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe0e0e0)), borderRadius: BorderRadius.circular(_p * 0.42)),
      child: Column(children: [
        Semantics(
          label: '$label. ${isOpen ? 'Collapse' : 'Expand'} details',
          button: true,
          child: GestureDetector(
            onTap: () => setState(() { isOpen ? _expanded.remove(key) : _expanded.add(key); }),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                AnimatedRotation(turns: isOpen ? 0.25 : 0, duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.play_arrow, size: _prefArrowFs + 4, color: _agreeClr)),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: TextStyle(fontSize: _prefCatNameFs, fontWeight: FontWeight.w600, color: _bodyClr))),
                if (isNec)
                  Text(_alwaysActive, style: TextStyle(fontSize: _prefCatBodyFs, fontWeight: FontWeight.w600, color: _agreeClr))
                else
                  _toggle(togOn, key),
              ]),
            ),
          ),
        ),
        if (isOpen)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFf0f0f0))),
              color: Color(0x05000000),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: TextStyle(fontSize: _prefCatBodyFs, height: 1.42, color: _bodyClr.withValues(alpha: 0.8))),
                // "Cookie Details" link — same as default.js seers-cmp-cookie-policy-detail-btn
                // Only show if this category has DPS entries
                if (_getDpsForCat(key).isNotEmpty) ...[  
                  SizedBox(height: _p * 0.33),
                  GestureDetector(
                    onTap: () => setState(() {
                      _dpsCat    = key;
                      _dpsSearch = '';
                      _dpsView   = true;
                    }),
                    child: Text(
                      _l?['cookie_details'] ?? 'Cookie Details',
                      style: TextStyle(
                        fontSize: _prefCatBodyFs,
                        color: _agreeClr,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: _agreeClr,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ]),
    );
  }

  Widget _toggle(bool value, String key) {
    return Semantics(
      label: '${key[0].toUpperCase()}${key.substring(1)} cookies',
      hint: value ? 'Currently enabled. Double tap to disable.' : 'Currently disabled. Double tap to enable.',
      toggled: value,
      child: GestureDetector(
        onTap: () => setState(() => _toggles[key] = !value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36, height: 20,
          decoration: BoxDecoration(
            color: value ? _agreeClr : const Color(0xFFcccccc),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16, height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Button builders — exact CSS match
  // ─────────────────────────────────────────────────────────

  Widget _prefLogo() {
    if (!_showLogo) return const SizedBox.shrink();

    final logoHeight = max(_p * 1.8, 24.0);
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.network(
        _logoSrc,
        height: logoHeight,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _badgeImage(double size) {
    if (_customBadgeSrc != null) {
      return Image.network(
        _customBadgeSrc!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.memory(
          base64Decode(_seersDefaultBadgeBase64),
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    }

    return Image.memory(
      base64Decode(_seersDefaultBadgeBase64),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  // stk-outline: background:transparent, border:1.5px solid currentColor (body_text_color)
  // padding:5px 8px, font-weight:700, line-height:1.4
  Widget _stkOutline(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap,
    bg: Colors.transparent, fg: _prefBorder,
    border: BorderSide(color: _prefBorder, width: 1.5),
    isLast: true,
    hint: 'Opens cookie preference settings',
  );

  // stk-dark: background:#1a1a2e, color:#fff
  Widget _stkDark(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap, bg: _decClr, fg: _decTxt,
    hint: 'Rejects all optional cookies and closes the banner',
  );

  // stk-primary: agreeStyle colors, stroke support
  Widget _stkPrimary(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap,
    bg: _isStroke ? Colors.transparent : _agreeClr,
    fg: _isStroke ? _agreeClr : _agreeTxt,
    border: _isStroke ? BorderSide(color: _agreeClr) : BorderSide.none,
    hint: 'Accepts all cookies and closes the banner',
  );

  Widget _stk({required String label, required VoidCallback onTap,
      required Color bg, required Color fg, BorderSide border = BorderSide.none,
      bool isLast = false, String? hint}) {
    return Semantics(
      label: label, hint: hint, button: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : _p * 0.42),
        child: SizedBox(width: double.infinity,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: bg, foregroundColor: fg,
              minimumSize: const Size.fromHeight(32),
              padding: EdgeInsets.symmetric(vertical: _p * 0.42, horizontal: _p * 0.67),
              shape: RoundedRectangleBorder(borderRadius: _btnR, side: border),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs, color: fg, height: 1.35),
                textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _btnItem(String label, Color bg, Color fg, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: bg, foregroundColor: fg,
        minimumSize: const Size.fromHeight(32),
        padding: EdgeInsets.symmetric(vertical: _p * 0.42, horizontal: _p * 0.67),
        shape: RoundedRectangleBorder(borderRadius: _btnR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: fg, height: 1.35),
          textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _prefFullBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(bottom: _p * 0.25),
      child: SizedBox(width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: Colors.transparent, foregroundColor: _prefBorder,
            minimumSize: const Size.fromHeight(32),
            padding: EdgeInsets.symmetric(vertical: _p * 0.42, horizontal: _p * 0.67),
            shape: RoundedRectangleBorder(borderRadius: _btnR, side: BorderSide(color: _prefBorder)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: _prefBorder, height: 1.35),
              textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _prefActionBtn(String label, Color bg, Color fg, VoidCallback onTap, {bool isSave = false, double? fontSize}) {
    return SizedBox(width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg, foregroundColor: fg,
          minimumSize: Size.fromHeight(isSave ? 38 : 36),
          padding: EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: fontSize ?? _fs, color: fg, height: 1.35),
            textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _save(String value, bool pref, bool stat, bool mkt) async {
    await SeersCMP.saveConsent(value: value, preferences: pref, statistics: stat, marketing: mkt);
    _showBadgeOnly();
  }

  Color _c(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    return Colors.black;
  }
}
