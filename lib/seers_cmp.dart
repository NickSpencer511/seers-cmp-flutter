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
    final urls = [
      'https://cdn.consents.dev/mobile/configs/$sdkKey.json',
    ];
    for (final url in urls) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final decoded = jsonDecode(r.body);
          if (decoded is Map<String, dynamic>) return decoded;
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
// Flutter Banner Widget — exact match to frontend MobileDefaultBanner.vue
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
  bool _prefOn   = true;
  bool _statOn   = false;
  bool _mktOn    = false;
  final Set<String> _expanded = {};

  Map<String, dynamic>? get _b => widget.payload.banner;
  Map<String, dynamic>? get _l => widget.payload.language;
  Map<String, dynamic>? get _d => widget.payload.dialogue;

  // ── Colors — exact same fields as frontend banner object ──
  Color get _bgColor      => _c(_b?['banner_bg_color']        ?? '#ffffff');
  Color get _titleColor   => _c(_b?['title_text_color']       ?? '#1a1a1a');
  Color get _bodyColor    => _c(_b?['body_text_color']        ?? '#1a1a1a');
  Color get _agreeColor   => _c(_b?['agree_btn_color']        ?? '#3b6ef8');
  Color get _agreeText    => _c(_b?['agree_text_color']       ?? '#ffffff');
  Color get _declineColor => _c(_b?['disagree_btn_color']     ?? '#1a1a2e');
  Color get _declineText  => _c(_b?['disagree_text_color']    ?? '#ffffff');
  Color get _prefTextColor=> _c(_b?['preferences_text_color'] ?? '#3b6ef8');

  // ── Font size from banner.font_size ──
  double get _fs => double.tryParse(_b?['font_size']?.toString() ?? '14') ?? 14;

  // ── Button shape from banner.button_type ──
  // shape-default → radius 4, shape-flat → 0, shape-rounded → 20, shape-stroke → 4 + outline
  String get _btnType => (_b?['button_type'] ?? 'default').toString();
  BorderRadius get _btnRadius {
    if (_btnType.contains('rounded')) return BorderRadius.circular(20);
    if (_btnType.contains('flat'))    return BorderRadius.zero;
    return BorderRadius.circular(4); // default + stroke
  }
  bool get _isStroke => _btnType.contains('stroke');

  // ── Display style + layout + position ──
  String get _template => (_d?['mobile_template'] ?? 'popup').toString();
  String get _layout   => (_b?['layout']   ?? 'default').toString();
  String get _position => (_b?['position'] ?? 'bottom').toString();

  // ── Language from mobile_dialogue_languages ──
  String get _body        => _l?['body']                ?? 'We use SDKs and other tracking technologies to improve your in-app experience.';
  String get _title       => _l?['title']               ?? 'This app uses tracking technologies';
  String get _btnAgree    => _l?['btn_agree_title']     ?? 'Allow All';
  String get _btnDecline  => _l?['btn_disagree_title']  ?? 'Disable All';
  String get _btnPref     => _l?['btn_preference_title']?? 'Cookie Settings';
  String get _btnSave     => _l?['btn_save_my_choices'] ?? 'Save my choices';
  String get _aboutCookies=> _l?['about_cookies']       ?? 'About Our Cookies';
  String get _necTitle    => _l?['necessory_title']     ?? 'Necessary';
  String get _necBody     => _l?['necessory_body']      ?? 'Required for the app to function. Cannot be switched off.';
  String get _prefTitle   => _l?['preference_title']    ?? 'Preferences';
  String get _prefBody    => _l?['preference_body']     ?? 'Allow the app to remember choices you make.';
  String get _statTitle   => _l?['statistics_title']    ?? 'Statistics';
  String get _statBody    => _l?['statistics_body']     ?? 'Help us understand how users interact with the app.';
  String get _mktTitle    => _l?['marketing_title']     ?? 'Marketing';
  String get _mktBody     => _l?['marketing_body']      ?? 'Used to track visitors and display relevant advertisements.';
  String get _alwaysActive=> _l?['always_active']       ?? 'Always Active';

  bool get _allowReject => _d?['allow_reject'] == true || _d?['allow_reject'] == 1;
  bool get _poweredBy   => _d?['powered_by']   == true || _d?['powered_by']   == 1;
  bool get _showHandle  => _layout == 'rounded';

  // ── Container border radius — matches frontend CSS exactly ──
  BorderRadius _sheetRadius() {
    // bottom_sheet
    if (_template == 'bottom_sheet') {
      if (_layout == 'flat')    return BorderRadius.zero;
      if (_layout == 'rounded') return const BorderRadius.vertical(top: Radius.circular(16));
      if (_position == 'top')   return const BorderRadius.vertical(bottom: Radius.circular(14));
      return const BorderRadius.vertical(top: Radius.circular(14)); // bottom (default)
    }
    // dialog
    if (_template == 'dialog') {
      if (_layout == 'rounded') return BorderRadius.circular(20);
      if (_layout == 'flat')    return BorderRadius.zero;
      return BorderRadius.circular(10);
    }
    // popup — always bottom sheet style
    return const BorderRadius.vertical(top: Radius.circular(12));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: _showPref ? _prefCenter() : _banner(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // MAIN BANNER — 3 display styles matching frontend exactly
  // ─────────────────────────────────────────────────────────
  Widget _banner() {
    final container = Container(
      key: const ValueKey('banner'),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: _sheetRadius(),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: _template == 'bottom_sheet' ? _bottomSheetContent() : _popupContent(),
    );

    if (_template == 'dialog') {
      // Centered modal
      return Center(
        child: Container(
          key: const ValueKey('dialog'),
          width: MediaQuery.of(context).size.width * 0.88,
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: _sheetRadius(),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24)],
          ),
          padding: const EdgeInsets.all(12),
          child: _popupContent(),
        ),
      );
    }

    // popup + bottom_sheet — anchored to bottom or top
    return Align(
      alignment: _position == 'top' ? Alignment.topCenter : Alignment.bottomCenter,
      child: container,
    );
  }

  // ── Popup content: body text + 3 stacked full-width buttons ──
  // Matches frontend: stk-outline → stk-dark → stk-primary
  Widget _popupContent() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_body, style: TextStyle(fontSize: _fs, color: _bodyColor, height: 1.5)),
      const SizedBox(height: 10),
      // Cookie Settings — outline (stk-outline)
      _stkOutline(_btnPref, () => setState(() => _showPref = true)),
      const SizedBox(height: 5),
      // Disable All — dark (stk-dark)
      if (_allowReject) _stkDark(_btnDecline, () => _save('disagree', false, false, false)),
      if (_allowReject) const SizedBox(height: 5),
      // Allow All — primary (stk-primary)
      _stkPrimary(_btnAgree, () => _save('agree', true, true, true)),
      if (_poweredBy) ...[
        const SizedBox(height: 6),
        Text('Powered by Seers', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    ]);
  }

  // ── Bottom sheet content: title + body + [Decline|Accept] row + Preferences full-width ──
  // Matches frontend: btn-row-primary + btn-pref-full
  Widget _bottomSheetContent() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_showHandle)
        Center(child: Container(width: 32, height: 4,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
      Text(_title, style: TextStyle(fontSize: _fs + 2, fontWeight: FontWeight.w700, color: _titleColor)),
      const SizedBox(height: 4),
      Text(_body, style: TextStyle(fontSize: _fs, color: _bodyColor, height: 1.4)),
      const SizedBox(height: 8),
      // Row 1: Decline + Accept side by side (btn-row-primary)
      Row(children: [
        if (_allowReject) ...[
          Expanded(child: _btnItem(_btnDecline, _declineColor, _declineText, () => _save('disagree', false, false, false))),
          const SizedBox(width: 4),
        ],
        Expanded(child: _btnItem(_btnAgree, _agreeColor, _agreeText, () => _save('agree', true, true, true))),
      ]),
      const SizedBox(height: 4),
      // Row 2: Preferences full-width outline (btn-pref-full)
      _prefFullBtn(_btnPref, () => setState(() => _showPref = true)),
      if (_poweredBy) ...[
        const SizedBox(height: 4),
        Text('Powered by Seers', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    ]);
  }

  // ─────────────────────────────────────────────────────────
  // PREFERENCE CENTER — full screen, sticky Save footer
  // ─────────────────────────────────────────────────────────
  Widget _prefCenter() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        key: const ValueKey('pref'),
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(color: _bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(children: [
              Expanded(child: Text(_aboutCookies,
                  style: TextStyle(fontSize: _fs + 2, fontWeight: FontWeight.bold, color: _titleColor))),
              GestureDetector(onTap: widget.onDismiss,
                  child: Icon(Icons.close, color: _bodyColor, size: 18)),
            ]),
          ),
          // Scrollable body
          Expanded(child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_body, style: TextStyle(fontSize: _fs - 1, color: _bodyColor, height: 1.5))),
            const SizedBox(height: 10),
            // Allow All
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _stkPrimary(_btnAgree, () => _save('agree', true, true, true))),
            const SizedBox(height: 6),
            // Disable All
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _stkDark(_btnDecline, () => _save('disagree', false, false, false))),
            const SizedBox(height: 10),
            const Divider(height: 1),
            // Categories with accordion
            _catRow('necessary',   _necTitle,  _necBody,  alwaysActive: true,  val: true,   onChange: (_) {}),
            _catRow('preferences', _prefTitle, _prefBody, alwaysActive: false, val: _prefOn, onChange: (v) => setState(() => _prefOn = v)),
            _catRow('statistics',  _statTitle, _statBody, alwaysActive: false, val: _statOn, onChange: (v) => setState(() => _statOn = v)),
            _catRow('marketing',   _mktTitle,  _mktBody,  alwaysActive: false, val: _mktOn,  onChange: (v) => setState(() => _mktOn  = v)),
            const SizedBox(height: 80),
          ]))),
          // Sticky Save my choices footer
          Container(
            decoration: BoxDecoration(color: _bgColor,
                border: const Border(top: BorderSide(color: Color(0xFFe0e0e0)))),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _stkPrimary(_btnSave, () => _save('custom', _prefOn, _statOn, _mktOn)),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Category accordion row
  // ─────────────────────────────────────────────────────────
  Widget _catRow(String key, String title, String desc,
      {required bool alwaysActive, required bool val, required ValueChanged<bool> onChange}) {
    final open = _expanded.contains(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: GestureDetector(
          onTap: () => setState(() { open ? _expanded.remove(key) : _expanded.add(key); }),
          child: Icon(open ? Icons.expand_circle_down : Icons.chevron_right,
              color: _agreeColor, size: 20),
        ),
        title: Text(title, style: TextStyle(fontSize: _fs, fontWeight: FontWeight.w600, color: _bodyColor)),
        trailing: alwaysActive
            ? Text(_alwaysActive, style: TextStyle(fontSize: _fs - 2, fontWeight: FontWeight.w600, color: _agreeColor))
            : Switch(value: val, onChanged: onChange, activeTrackColor: _agreeColor, activeThumbColor: Colors.white),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(52, 0, 16, 8),
          child: Text(desc, style: TextStyle(fontSize: _fs - 2, color: _bodyColor.withValues(alpha: 0.75))),
        ),
      const Divider(height: 1, indent: 12),
    ]);
  }

  // ─────────────────────────────────────────────────────────
  // Button builders — match frontend button shapes exactly
  // ─────────────────────────────────────────────────────────

  // stk-outline: transparent bg, border = preferences_text_color
  Widget _stkOutline(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _prefTextColor,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: _prefTextColor, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        minimumSize: const Size(double.infinity, 0),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs)),
    );
  }

  // stk-dark: #1a1a2e bg, white text
  Widget _stkDark(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _declineColor,
        foregroundColor: _declineText,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        elevation: 0,
        minimumSize: const Size(double.infinity, 0),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs)),
    );
  }

  // stk-primary: agree_btn_color bg
  Widget _stkPrimary(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isStroke ? Colors.transparent : _agreeColor,
        foregroundColor: _isStroke ? _agreeColor : _agreeText,
        side: _isStroke ? BorderSide(color: _agreeColor) : null,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        elevation: 0,
        minimumSize: const Size(double.infinity, 0),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _fs)),
    );
  }

  // btn-item: equal-width side-by-side (bottom_sheet row 1)
  Widget _btnItem(String label, Color bg, Color fg, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        elevation: 0,
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs),
          overflow: TextOverflow.ellipsis),
    );
  }

  // btn-pref-full: full-width outline (bottom_sheet row 2)
  Widget _prefFullBtn(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _prefTextColor,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: _prefTextColor),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        minimumSize: const Size(double.infinity, 0),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _fs)),
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
