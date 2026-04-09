# seers_cmp

Seers Consent Management Platform SDK for Flutter.

## Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  seers_cmp: ^1.0.3
```

Then run:
```bash
flutter pub get
```

## Usage

```dart
import 'package:seers_cmp/seers_cmp.dart';

void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SeersCMP.initialize(settingsId: 'YOUR_SETTINGS_ID');
    runApp(const MyApp());
}
```

Get your **Settings ID** from [seers.ai](https://seers.ai) dashboard → Mobile Apps → Get Code.

## What it does automatically
- ✅ Shows consent banner based on your dashboard settings
- ✅ Detects user region (GDPR / CPRA / none)
- ✅ Blocks trackers until consent is given
- ✅ Saves consent to SharedPreferences
- ✅ Logs consent to your Seers dashboard
