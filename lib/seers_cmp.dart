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
  static final _catMap = {3: 'statistics', 4: 'marketing', 5: 'preferences', 6: 'unclassified'};

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
    _onShowBanner?.call(payload);
  }

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
      '${_config?['cx_host'] ?? ''}/api/mobile/sdk/config/$sdkKey',
    ];
    for (final url in urls) {
      try {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) return jsonDecode(r.body);
      } catch (_) {}
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _checkRegion(String sdkKey) async {
    final host = _config?['cx_host'] ?? '';
    try {
      final r = await http.get(Uri.parse('$host/api/mobile/sdk/$sdkKey'));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return {'regulation': 'gdpr', 'eligible': true};
  }

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
    final code = region?['data']?['country_iso_code'] ?? config['dialogue']?['default_language'] ?? 'GB';
    final langs = config['languages'] as List?;
    return langs?.firstWhere((l) => l['country_code'] == code, orElse: () => langs.first);
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

class SeersBannerWidget extends StatefulWidget {
  final SeersBannerPayload payload;
  final VoidCallback onDismiss;
  const SeersBannerWidget({Key? key, required this.payload, required this.onDismiss}) : super(key: key);

  @override
  State<SeersBannerWidget> createState() => _SeersBannerWidgetState();
}

class _SeersBannerWidgetState extends State<SeersBannerWidget> {
  bool _showPreferences = false;
  bool _prefOn  = true;
  bool _statOn  = false;
  bool _mktOn   = false;
  final Set<String> _expanded = {};

  Map<String, dynamic>? get _banner   => widget.payload.banner;
  Map<String, dynamic>? get _lang     => widget.payload.language;
  Map<String, dynamic>? get _dialogue => widget.payload.dialogue;

  Color get _bgColor      => _hexColor(_banner?['banner_bg_color']        ?? '#ffffff');
  Color get _agreeColor   => _hexColor(_banner?['agree_btn_color']        ?? '#3b6ef8');
  Color get _agreeText    => _hexColor(_banner?['agree_text_color']       ?? '#ffffff');
  Color get _declineColor => _hexColor(_banner?['disagree_btn_color']     ?? '#1a1a2e');
  Color get _declineText  => _hexColor(_banner?['disagree_text_color']    ?? '#ffffff');
  Color get _prefText     => _hexColor(_banner?['preferences_text_color'] ?? '#3b6ef8');
  Color get _bodyColor    => _hexColor(_banner?['body_text_color']        ?? '#1a1a1a');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showPreferences ? _preferencesView() : _mainBanner(),
        ),
      ),
    );
  }

  Widget _mainBanner() {
    return Container(
      key: const ValueKey('main'),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_lang?['body'] ?? 'We use cookies to personalize content and ads.',
            style: TextStyle(fontSize: 13, color: _bodyColor)),
        const SizedBox(height: 12),
        // Cookie settings (outline)
        OutlinedButton(
          onPressed: () => setState(() => _showPreferences = true),
          style: OutlinedButton.styleFrom(foregroundColor: _prefText, side: BorderSide(color: _prefText)),
          child: Text(_lang?['btn_preference_title'] ?? 'Cookie settings', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        // Disable All
        if (_dialogue?['allow_reject'] == true)
          ElevatedButton(
            onPressed: () => _save('disagree', false, false, false),
            style: ElevatedButton.styleFrom(backgroundColor: _declineColor, foregroundColor: _declineText),
            child: Text(_lang?['btn_disagree_title'] ?? 'Disable All', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 8),
        // Allow All
        ElevatedButton(
          onPressed: () => _save('agree', true, true, true),
          style: ElevatedButton.styleFrom(backgroundColor: _agreeColor, foregroundColor: _agreeText),
          child: Text(_lang?['btn_agree_title'] ?? 'Allow All', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_dialogue?['powered_by'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Powered by Seers', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ),
      ]),
    );
  }

  Widget _preferencesView() {
    return Container(
      key: const ValueKey('prefs'),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(color: _bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Text(_lang?['about_cookies'] ?? 'About Our Cookies',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _bodyColor)),
            const Spacer(),
            GestureDetector(onTap: widget.onDismiss, child: Icon(Icons.close, color: _bodyColor, size: 18)),
          ]),
        ),
        // Scrollable content
        Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_lang?['body'] ?? 'We use cookies to personalize content and ads.',
                style: TextStyle(fontSize: 12, color: _bodyColor)),
          ),
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ElevatedButton(
            onPressed: () => _save('agree', true, true, true),
            style: ElevatedButton.styleFrom(backgroundColor: _agreeColor, foregroundColor: _agreeText),
            child: Text(_lang?['btn_agree_title'] ?? 'Allow All', style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ElevatedButton(
            onPressed: () => _save('disagree', false, false, false),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1a1a2e), foregroundColor: Colors.white),
            child: Text(_lang?['btn_disagree_title'] ?? 'Disable All', style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 12),
          const Divider(height: 1),
          _categoryRow('necessary',   _lang?['necessory_title']  ?? 'Necessary',   alwaysActive: true,  value: true,  onChanged: (_) {}),
          _categoryRow('preferences', _lang?['preference_title'] ?? 'Preferences', alwaysActive: false, value: _prefOn, onChanged: (v) => setState(() => _prefOn = v)),
          _categoryRow('statistics',  _lang?['statistics_title'] ?? 'Statistics',  alwaysActive: false, value: _statOn, onChanged: (v) => setState(() => _statOn = v)),
          _categoryRow('marketing',   _lang?['marketing_title']  ?? 'Marketing',   alwaysActive: false, value: _mktOn,  onChanged: (v) => setState(() => _mktOn  = v)),
          const SizedBox(height: 80),
        ]))),
        // Sticky footer
        Container(
          decoration: BoxDecoration(color: _bgColor, border: const Border(top: BorderSide(color: Color(0xFFe0e0e0)))),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: () => _save('custom', _prefOn, _statOn, _mktOn),
            style: ElevatedButton.styleFrom(backgroundColor: _agreeColor, foregroundColor: _agreeText, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(_lang?['btn_save_my_choices'] ?? 'Save my choices', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _categoryRow(String key, String label, {required bool alwaysActive, required bool value, required ValueChanged<bool> onChanged}) {
    final isExpanded = _expanded.contains(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: GestureDetector(
          onTap: () => setState(() { isExpanded ? _expanded.remove(key) : _expanded.add(key); }),
          child: Icon(isExpanded ? Icons.expand_circle_down : Icons.chevron_right, color: _agreeColor),
        ),
        title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _bodyColor)),
        trailing: alwaysActive
            ? Text('Always Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _agreeColor))
            : Switch(value: value, onChanged: onChanged, activeTrackColor: _agreeColor, activeThumbColor: Colors.white),
        dense: true,
      ),
      if (isExpanded)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
          child: Text(_descFor(key), style: TextStyle(fontSize: 11, color: _bodyColor.withValues(alpha: 0.7))),
        ),
      const Divider(height: 1, indent: 16),
    ]);
  }

  String _descFor(String key) {
    switch (key) {
      case 'necessary':   return 'Required for the website to function. Cannot be switched off.';
      case 'preferences': return 'Allow the website to remember choices you make.';
      case 'statistics':  return 'Help us understand how visitors interact with the website.';
      case 'marketing':   return 'Used to track visitors and display relevant advertisements.';
      default:            return '';
    }
  }

  Future<void> _save(String value, bool pref, bool stat, bool mkt) async {
    await SeersCMP.saveConsent(value: value, preferences: pref, statistics: stat, marketing: mkt);
    widget.onDismiss();
  }

  Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    return Colors.black;
  }
}
