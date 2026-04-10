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
    final map = getConsentMap();
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

  static bool _shouldShow(dynamic dialogue, Map<String, dynamic>? region) {
    if (dialogue == null) return false;
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
          'sdk_key':    sdkKey,
          'platform':   _config?['platform'] ?? 'flutter',
          'consent':    consent.value,
          'categories': {
            'necessary':   consent.necessary,
            'preferences': consent.preferences,
            'statistics':  consent.statistics,
            'marketing':   consent.marketing,
          },
          'timestamp': consent.timestamp,
        }),
      );
    } catch (_) {}
  }
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
  Color get _prefClr  => _bodyClr;

  // ── Font size from banner.font_size ──
  // Preview uses font_size directly (6-8px in 190px frame)
  // Real app: use font_size as-is (user sets it in dashboard, e.g. 14)
  double get _fs      => double.tryParse(_b?['font_size']?.toString() ?? '14') ?? 14;
  double get _titleFs => _fs + 2; // titleStyle: font_size + 2

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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // banner-body: margin: 0 0 7px, line-height: 1.5, opacity: 0.9
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        const SizedBox(height: 7),
        _stkOutline(_btnPref, () => setState(() => _showPref = true)),
        const SizedBox(height: 5),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false)), const SizedBox(height: 5)],
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
        if (_poweredBy) ...[const SizedBox(height: 3),
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // sheet-handle: width:32px, height:4px, background:#ccc, border-radius:2px, margin:0 auto 6px
        if (_handle) Center(child: Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: const Color(0xFFcccccc), borderRadius: BorderRadius.circular(2)))),
        // banner-title: font-weight:700, margin:0 0 4px, line-height:1.3
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 4),
        // banner-body: margin:0 0 7px, line-height:1.5, opacity:0.9
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        const SizedBox(height: 7),
        // btn-row-primary: flex, gap:4px, margin-bottom:4px
        Row(children: [
          if (_allowReject) ...[
            Expanded(child: _btnItem(_btnDecline, _decClr, _decTxt, () => _save('disagree', false, false, false))),
            const SizedBox(width: 4),
          ],
          Expanded(child: _btnItem(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true))),
        ]),
        const SizedBox(height: 4),
        // btn-pref-full: padding:4px 6px, margin-bottom:3px, border:1px solid currentColor, font-weight:600
        _prefFullBtn(_btnPref, () => setState(() => _showPref = true)),
        if (_poweredBy) ...[const SizedBox(height: 3),
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
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_title, style: TextStyle(fontSize: _titleFs, color: _titleClr, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 4),
        Text(_body, style: TextStyle(fontSize: _fs, color: _bodyClr.withValues(alpha: 0.9), height: 1.5)),
        const SizedBox(height: 8),
        _stkOutline(_btnPref, () => setState(() => _showPref = true)),
        const SizedBox(height: 5),
        if (_allowReject) ...[_stkDark(_btnDecline, () => _save('disagree', false, false, false)), const SizedBox(height: 5)],
        _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // pref-close: font-size:10px, align-self:flex-end
                Align(alignment: Alignment.centerRight,
                  child: GestureDetector(onTap: widget.onDismiss,
                    child: Text('✕', style: TextStyle(fontSize: _fs, color: _titleClr, fontWeight: FontWeight.w700)))),
                const SizedBox(height: 2),
                // pref-title: font-weight:700, font-size:8px (scaled: titleFs)
                Text(_aboutCookies, style: TextStyle(fontSize: _titleFs, fontWeight: FontWeight.w700, color: _titleClr, height: 1.3)),
                const SizedBox(height: 4),
                // pref-body: font-size:6px, opacity:0.85, line-height:1.4
                Text(_body, style: TextStyle(fontSize: _fs - 1, color: _bodyClr.withValues(alpha: 0.85), height: 1.4)),
                const SizedBox(height: 4),
                // pref-policy-link: font-size:6px, font-weight:600, underline, color:agree_btn_color
                Text('Read Cookie Policy ↗', style: TextStyle(fontSize: _fs - 2, fontWeight: FontWeight.w600,
                    color: _agreeClr, decoration: TextDecoration.underline, decorationColor: _agreeClr)),
                const SizedBox(height: 6),
                // pref-allow-btn: padding:4px 6px, font-weight:700, border-radius:4px, font-size:7px
                _prefActionBtn(_btnAgree, _agreeClr, _agreeTxt, () => _save('agree', true, true, true)),
                const SizedBox(height: 4),
                // pref-disable-btn: background:#1a1a2e, color:#fff
                _prefActionBtn(_btnDecline, const Color(0xFF1a1a2e), Colors.white, () => _save('disagree', false, false, false)),
                const SizedBox(height: 8),
                // pref-categories: gap:3px, border-top:1px solid #e0e0e0, padding-top:4px
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFe0e0e0)))),
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(children: _cats.map(_catRow).toList()),
                ),
              ]),
            )),
            // pref-footer: padding:6px 10px 8px, border-top:1px #e0e0e0, box-shadow
            Container(
              decoration: BoxDecoration(color: _bg,
                border: const Border(top: BorderSide(color: Color(0xFFe0e0e0))),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))]),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              // pref-save-btn: padding:5px 6px, font-weight:700, border-radius:4px
              child: _prefActionBtn(_btnSave, _agreeClr, _agreeTxt,
                  () => _save('custom', _toggles['preferences']!, _toggles['statistics']!, _toggles['marketing']!)),
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
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFe0e0e0)), borderRadius: BorderRadius.circular(5)),
      child: Column(children: [
        // pref-cat-row: padding:4px 5px, justify-content:space-between
        GestureDetector(
          onTap: () => setState(() { isOpen ? _expanded.remove(key) : _expanded.add(key); }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(children: [
              // pref-cat-left: gap:3px
              // pref-cat-arrow: font-size:6px, rotates 90deg when open
              AnimatedRotation(turns: isOpen ? 0.25 : 0, duration: const Duration(milliseconds: 200),
                child: Text('▶', style: TextStyle(fontSize: _fs * 0.6, color: _agreeClr))),
              const SizedBox(width: 3),
              // pref-cat-name: font-size:6.5px, font-weight:600
              Expanded(child: Text(label, style: TextStyle(fontSize: _fs * 0.85, fontWeight: FontWeight.w600, color: _bodyClr))),
              // pref-always-active: font-size:6px, font-weight:600, color:agree_btn_color
              if (isNec)
                Text(_alwaysActive, style: TextStyle(fontSize: _fs * 0.75, fontWeight: FontWeight.w600, color: _agreeClr))
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
            padding: const EdgeInsets.fromLTRB(7, 3, 7, 4),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFf0f0f0))),
              color: Color(0x05000000),
            ),
            child: Text(desc, style: TextStyle(fontSize: _fs * 0.7, height: 1.5, color: _bodyClr.withValues(alpha: 0.8))),
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

  // stk-btn base: padding:5px 8px, font-weight:700, width:100%, line-height:1.4
  Widget _stk({required String label, required VoidCallback onTap,
      required Color bg, required Color fg, BorderSide border = BorderSide.none}) {
    return SizedBox(width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg, foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: _btnR, side: border),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs, color: fg, height: 1.4),
            textAlign: TextAlign.center),
      ),
    );
  }

  // btn-item: flex:1, padding:4px, font-weight:600 (bottom_sheet row)
  Widget _btnItem(String label, Color bg, Color fg, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: bg, foregroundColor: fg,
        padding: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: _btnR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: fg),
          textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
    );
  }

  // btn-pref-full: padding:4px 6px, border:1px solid currentColor, font-weight:600
  Widget _prefFullBtn(String label, VoidCallback onTap) {
    return SizedBox(width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent, foregroundColor: _prefBorder,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: _btnR, side: BorderSide(color: _prefBorder)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs, color: _prefBorder),
            textAlign: TextAlign.center),
      ),
    );
  }

  // pref-allow-btn / pref-disable-btn / pref-save-btn: padding:4px 6px (allow/disable), 5px 6px (save), font-weight:700, border-radius:4px
  Widget _prefActionBtn(String label, Color bg, Color fg, VoidCallback onTap) {
    return SizedBox(width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg, foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
