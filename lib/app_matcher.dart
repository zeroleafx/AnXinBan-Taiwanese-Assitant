import 'voice_command.dart';

/// An app on the phone that can be opened from its home screen.
class InstalledApp {
  const InstalledApp({required this.label, required this.package});

  /// The name under its icon.
  final String label;
  final String package;
}

/// The installed app a spoken name most likely means, or null.
InstalledApp? matchApp(String spoken, Iterable<InstalledApp> apps) {
  final asked = normalizeTranscript(spoken);
  if (asked.isEmpty) return null;
  // Everything the spoken name may be called on a home screen.
  final names = {
    asked,
    for (final group in _sameApp)
      if (group.contains(asked)) ...group,
  };
  InstalledApp? best;
  var bestScore = 0;
  for (final app in apps) {
    final label = normalizeTranscript(app.label);
    if (label.isEmpty) continue;
    var score = 0;
    for (final name in names) {
      // The word that was said counts for more than another name for it.
      final exact = name == asked ? 100 : 70;
      final fit = label == name
          ? exact
          : name.length >= 2 && label.contains(name)
          ? exact - 15
          : label.length >= 2 && name.contains(label)
          ? exact - 25
          : 0;
      if (fit > score) score = fit;
    }
    final shorter =
        score == bestScore &&
        best != null &&
        app.label.length < best.label.length;
    if (score > bestScore || (score > 0 && shorter)) {
      best = app;
      bestScore = score;
    }
  }
  return best;
}

/// Names that mean the same app. Phone makers label their own apps
/// differently ("相簿", "圖庫", "媒體瀏覽器").
const _sameApp = [
  {'相機', '照相機', 'camera'},
  {'相簿', '相片', '照片', '圖庫', '圖片庫', '媒體瀏覽器', 'photos', 'gallery'},
  {'時鐘', '鬧鐘', 'clock'},
  {'計算機', '計算器', 'calculator'},
  {'行事曆', '日曆', 'calendar'},
  {'設定', 'settings'},
  {'電話', '撥號', 'phone'},
  {'聯絡人', '通訊錄', 'contacts'},
  {'瀏覽器', '網際網路', '上網', 'chrome', 'internet'},
  {'信箱', '郵件', '電子郵件', 'gmail', 'mail'},
  {'蝦皮', '蝦皮購物', 'shopee'},
  {'ig', 'instagram'},
  {'賴', 'line'},
  {'臉書', 'facebook'},
  {'地圖', 'maps', 'google地圖'},
  {'play商店', '商店', 'playstore', 'googleplay商店'},
];
