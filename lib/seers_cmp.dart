library seers_cmp;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  final String timestamp;
  final String expiry;

  SeersConsent({
    required this.sdkKey, required this.value,
    this.necessary = true, this.preferences = false,
    this.statistics = false, this.marketing = false,
    required this.timestamp, required this.expiry,
  });

  Map<String, dynamic> toJson() => {
    'sdk_key': sdkKey, 'value': value,
    'necessary': necessary, 'preferences': preferences,
    'statistics': statistics, 'marketing': marketing,
    'timestamp': timestamp, 'expiry': expiry,
  };

  factory SeersConsent.fromJson(Map<String, dynamic> j) => SeersConsent(
    sdkKey: j['sdk_key'] ?? '', value: j['value'] ?? '',
    necessary: j['necessary'] ?? true, preferences: j['preferences'] ?? false,
    statistics: j['statistics'] ?? false, marketing: j['marketing'] ?? false,
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
  final SeersBlockList blockList;
  final String? regulation;
  final String sdkKey;
  SeersBannerPayload({this.dialogue, this.banner, this.language, this.categories, required this.blockList, this.regulation, required this.sdkKey});
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
      blockList:  _buildBlockList(_config!),
      regulation: region?['regulation'],
      sdkKey:     settingsId,
    );

    // Store payload so it can be accessed via SeersCMP.lastPayload
    _lastPayload = payload;

    // Fire custom callback if provided
    _onShowBanner?.call(payload);

    // Auto-show banner if no custom callback provided and navigatorKey is set
    if (_onShowBanner == null && _navigatorKey?.currentContext != null) {
      _autoShowBanner(payload);
    }
  }

  /// Navigator key — set this to enable auto banner display without a callback.
  /// In main.dart:
  ///   SeersCMP.navigatorKey = GlobalKey<NavigatorState>();
  ///   MaterialApp(navigatorKey: SeersCMP.navigatorKey, ...)
  static GlobalKey<NavigatorState>? navigatorKey;

  static void _autoShowBanner(SeersBannerPayload payload) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => SeersBannerWidget(
        payload: payload,
        onDismiss: () => Navigator.of(context).pop(),
      ),
    );
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
  }) async {
    if (_settingsId == null) return;
    final expire = (_config?['dialogue']?['agreement_expire'] as int?) ?? 365;
    final expiry = DateTime.now().add(Duration(days: expire));
    final consent = SeersConsent(
      sdkKey: _settingsId!, value: value,
      preferences: preferences, statistics: statistics, marketing: marketing,
      timestamp: DateTime.now().toIso8601String(),
      expiry:    expiry.toIso8601String(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('SeersConsent_$_settingsId', jsonEncode(consent.toJson()));
    _logConsent(_settingsId!, consent);
    final map = SeersConsentMap(
      statistics:   SeersCategory(allowed: statistics,  sdks: _buildBlockList(_config ?? {}).statistics),
      marketing:    SeersCategory(allowed: marketing,   sdks: _buildBlockList(_config ?? {}).marketing),
      preferences:  SeersCategory(allowed: preferences, sdks: _buildBlockList(_config ?? {}).preferences),
      unclassified: SeersCategory(allowed: false,        sdks: _buildBlockList(_config ?? {}).unclassified),
    );
    _onConsent?.call(consent, map);
  }

  // ─────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchConfig(String sdkKey) async {
    // Add cache-busting so deleted configs are not served from CDN cache
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 60000; // changes every minute
    final urls = [
      'https://cdn.consents.dev/mobile/configs/$sdkKey.json?v=$ts',
    ];
    for (final url in urls) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (r.statusCode == 404) return {'eligible': false, 'message': 'App not found'};
        if (r.statusCode == 200) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map<String, dynamic>) {
            // If eligible is explicitly false, stop here
            if (decoded['eligible'] == false) return decoded;
            return decoded;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _checkRegion(String sdkKey) async {
    final host = _config?['cx_host'];
    if (host == null || host.toString().isEmpty) {
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

  static SeersConsentMap _buildConsentMap() {
    final list = _buildBlockList(_config ?? {});
    return SeersConsentMap(
      statistics:   SeersCategory(allowed: false, sdks: list.statistics),
      marketing:    SeersCategory(allowed: false, sdks: list.marketing),
      preferences:  SeersCategory(allowed: false, sdks: list.preferences),
      unclassified: SeersCategory(allowed: false, sdks: list.unclassified),
    );
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

  static Future<void> _logConsent(String sdkKey, SeersConsent consent) async {
    final host = _config?['cx_host'] ?? '';
    try {
      await http.post(
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
          'timestamp':   consent.timestamp,
          'app_version': appVersion,   // set via SeersCMP.appVersion = '1.0.0'
          'email':       userEmail,    // set via SeersCMP.userEmail = 'user@example.com'
        }),
      );
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
  // preferences starts checked — matches :checked="cat.key === 'preferences'"
  final Map<String, bool> _toggles = {'preferences': true, 'statistics': false, 'marketing': false};
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
  // Scale factor: maps Vue's 190px preview frame to real screen width.
  // e.g. 360dp phone → scale≈1.89, capped at 2.0
  double get _scale    => (MediaQuery.of(context).size.width / 190.0).clamp(1.0, 2.0);
  double get _fs        => (double.tryParse(_b?['font_size']?.toString() ?? '14') ?? 14) * _scale;
  double get _titleFs   => _fs + 2 * _scale;
  double get _catNameFs => _fs + 1 * _scale;
  double get _catBodyFs => _fs - 1 * _scale;
  double get _arrowFs   => _fs * 0.75;
  double get _p         => 12 * _scale;  // base padding

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

  // ── Container border radius — matches CSS exactly ──
  BorderRadius _radius() {
    if (_tmpl == 'dialog') {
      if (_lay == 'rounded') return BorderRadius.circular(20);
      if (_lay == 'flat')    return BorderRadius.zero;
      return BorderRadius.circular(10);
    }
    if (_lay == 'flat') return BorderRadius.zero;
    if (_lay == 'rounded') return _pos == 'top'
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : const BorderRadius.vertical(top: Radius.circular(16));
    // default
    if (_pos == 'top') return const BorderRadius.vertical(bottom: Radius.circular(14));
    return const BorderRadius.vertical(top: Radius.circular(12));
  }

  @override
  Widget build(BuildContext context) {
    if (_showPref) return _prefPanel();
    if (_tmpl == 'dialog') {
      return Material(color: Colors.black54, child: Center(child: _dialogBanner()));
    }
    return Material(
      color: Colors.black54,
      child: Align(
        alignment: _pos == 'top' ? Alignment.topCenter : Alignment.bottomCenter,
        child: _tmpl == 'bottom_sheet' ? _bottomSheet() : _popup(),
      ),
    );
  }

  // ══════════════════════════════════════════
  // POPUP — .consent-popup
  // padding: 12px 12px 10px
  // 3 stacked buttons: stk-btn (padding: 5px 8px, margin-bottom: 5px, font-weight:700, line-height:1.4)
  // ══════════════════════════════════════════
  Widget _popup() {
    return Container(
      decoration: BoxDecoration(color: _bg, borderRadius: _radius(),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, -4))]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        SizedBox(height: _p * 0.58),
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false))],
        _stkOutline(_btnPref, () => setState(() => _showPref = true)),
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
      decoration: BoxDecoration(color: _bg, borderRadius: _radius(),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, -2))]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_handle) Center(child: Container(width: _p * 2.67, height: _p * 0.33, margin: EdgeInsets.only(bottom: _p * 0.5),
            decoration: BoxDecoration(color: const Color(0xFFcccccc), borderRadius: BorderRadius.circular(_p * 0.17)))),
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.3)),
        SizedBox(height: _p * 0.33),
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        SizedBox(height: _p * 0.58),
        Row(children: [
          if (_allowReject) ...[
            Expanded(child: _btnItem(_btnDecline, _decClr, _decTxt, () => _save('disagree', false, false, false))),
            SizedBox(width: _p * 0.33),
          ],
          Expanded(child: _btnItem(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true))),
        ]),
        SizedBox(height: _p * 0.33),
        _prefFullBtn(_btnPref, () => setState(() => _showPref = true)),
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
      decoration: BoxDecoration(color: _bg, borderRadius: _radius(),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24)]),
      padding: EdgeInsets.all(_p),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.3)),
        SizedBox(height: _p * 0.33),
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        SizedBox(height: _p * 0.67),
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false))],
        _stkOutline(_btnPref, () => setState(() => _showPref = true)),
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
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Column(children: [
            // pref-scroll
            Expanded(child: SingleChildScrollView(
              padding: EdgeInsets.all(_p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(alignment: Alignment.centerRight,
                  child: GestureDetector(onTap: widget.onDismiss,
                    child: Text('✕', style: TextStyle(fontSize: _fs, color: _titleClr, fontWeight: FontWeight.w700)))),
                SizedBox(height: _p * 0.17),
                Text(_aboutCookies, style: TextStyle(fontSize: _titleFs, fontWeight: FontWeight.w700, color: _titleClr, height: 1.3)),
                SizedBox(height: _p * 0.33),
                Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.85), height: 1.4)),
                SizedBox(height: _p * 0.33),
                Text('Read Cookie Policy ↗', style: TextStyle(fontSize: _fs, fontWeight: FontWeight.w600,
                    color: _agreeClr, decoration: TextDecoration.underline, decorationColor: _agreeClr)),
                SizedBox(height: _p * 0.5),
                _prefActionBtn(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true)),
                SizedBox(height: _p * 0.33),
                _prefActionBtn(_btnDecline, const Color(0xFF1a1a2e), Colors.white, () => _save('disagree', false, false, false)),
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
                  () => _save('custom', _toggles['preferences']!, _toggles['statistics']!, _toggles['marketing']!), isSave: true),
            ),
          ]),
        ),
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
        GestureDetector(
          onTap: () => setState(() { isOpen ? _expanded.remove(key) : _expanded.add(key); }),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _p * 0.42, vertical: _p * 0.33),
            child: Row(children: [
              // pref-cat-left: gap:3px
              // pref-cat-arrow: font-size:6px, rotates 90deg when open
              AnimatedRotation(turns: isOpen ? 0.25 : 0, duration: const Duration(milliseconds: 200),
                child: Text('▶', style: TextStyle(fontSize: _arrowFs, color: _agreeClr))),
              const SizedBox(width: 3),
              // pref-cat-name: font-size: fs+1, font-weight:600
              Expanded(child: Text(label, style: TextStyle(fontSize: _catNameFs, fontWeight: FontWeight.w600, color: _bodyClr))), // catNameFs = fs+1
              // pref-always-active: font-size: fs, font-weight:600
              if (isNec)
                Text(_alwaysActive, style: TextStyle(fontSize: _fs, fontWeight: FontWeight.w600, color: _agreeClr))
              else
                // pref-toggle: width:22px, height:12px
                _toggle(togOn, key),
            ]),
          ),
        ),
        // pref-cat-body: padding:3px 7px 4px, font-size:5.5px, opacity:0.8, border-top:1px #f0f0f0, bg:rgba(0,0,0,0.02)
        if (isOpen)
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(_p * 0.58, _p * 0.25, _p * 0.58, _p * 0.33),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFf0f0f0))),
              color: Color(0x05000000),
            ),
            child: Text(desc, style: TextStyle(fontSize: _catBodyFs, height: 1.5, color: _bodyClr.withValues(alpha: 0.8))),
          ),
      ]),
    );
  }

  // ── Toggle — .pref-toggle: width:22px, height:12px, border-radius:12px ──
  // thumb: top:2px, left:2px, width:8px, height:8px
  Widget _toggle(bool value, String key) {
    return GestureDetector(
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
    );
  }

  // ─────────────────────────────────────────────────────────
  // Button builders — exact CSS match
  // ─────────────────────────────────────────────────────────

  // stk-outline: background:transparent, border:1.5px solid currentColor (body_text_color)
  // padding:5px 8px, font-weight:700, line-height:1.4
  Widget _stkOutline(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap,
    bg: Colors.transparent, fg: _prefBorder,
    border: BorderSide(color: _prefBorder, width: 1.5),
    isLast: true,
  );

  // stk-dark: background:#1a1a2e, color:#fff
  Widget _stkDark(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap, bg: _decClr, fg: _decTxt,
  );

  // stk-primary: agreeStyle colors, stroke support
  Widget _stkPrimary(String label, VoidCallback onTap) => _stk(
    label: label, onTap: onTap,
    bg: _isStroke ? Colors.transparent : _agreeClr,
    fg: _isStroke ? _agreeClr : _agreeTxt,
    border: _isStroke ? BorderSide(color: _agreeClr) : BorderSide.none,
  );

  Widget _stk({required String label, required VoidCallback onTap,
      required Color bg, required Color fg, BorderSide border = BorderSide.none, bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : _p * 0.42),
      child: SizedBox(width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: bg, foregroundColor: fg,
            padding: EdgeInsets.symmetric(vertical: _p * 0.42, horizontal: _p * 0.67),
            shape: RoundedRectangleBorder(borderRadius: _btnR, side: border),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs, color: fg, height: 1.4),
              textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _btnItem(String label, Color bg, Color fg, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: bg, foregroundColor: fg,
        padding: EdgeInsets.all(_p * 0.33),
        shape: RoundedRectangleBorder(borderRadius: _btnR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: fg),
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
            padding: EdgeInsets.symmetric(vertical: _p * 0.33, horizontal: _p * 0.5),
            shape: RoundedRectangleBorder(borderRadius: _btnR, side: BorderSide(color: _prefBorder)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: _prefBorder),
              textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _prefActionBtn(String label, Color bg, Color fg, VoidCallback onTap, {bool isSave = false}) {
    return SizedBox(width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg, foregroundColor: fg,
          padding: EdgeInsets.symmetric(vertical: isSave ? _p * 0.42 : _p * 0.33, horizontal: _p * 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_p * 0.33)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs, color: fg),
            textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _save(String value, bool pref, bool stat, bool mkt) async {
    await SeersCMP.saveConsent(value: value, preferences: pref, statistics: stat, marketing: mkt);
    widget.onDismiss();
  }

  Color _c(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    return Colors.black;
  }
}
