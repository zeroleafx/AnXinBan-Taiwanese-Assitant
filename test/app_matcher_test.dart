import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/app_matcher.dart';

InstalledApp app(String label) =>
    InstalledApp(label: label, package: 'pkg.$label');

void main() {
  final apps = [
    app('LINE'),
    app('LINE Bank'),
    app('YouTube'),
    app('YouTube Music'),
    app('地圖'),
    app('圖庫'),
    app('Google 相簿'),
    app('相機'),
    app('時鐘'),
    app('設定'),
    app('蝦皮購物'),
    app('健保快易通'),
  ];
  String? open(String spoken) => matchApp(spoken, apps)?.label;

  test('the exact name wins over longer names that contain it', () {
    expect(open('LINE'), 'LINE');
    expect(open('youtube'), 'YouTube');
    expect(open('相機'), '相機');
  });

  test('part of a name is enough', () {
    expect(open('健保'), '健保快易通');
    expect(open('蝦皮'), '蝦皮購物');
    expect(open('YouTube Music'), 'YouTube Music');
  });

  test('everyday words find the phone maker\'s own app', () {
    expect(open('相簿'), 'Google 相簿');
    expect(open('照片'), '圖庫');
    expect(open('鬧鐘'), '時鐘');
    expect(open('賴'), 'LINE');
    expect(open('Google 地圖'), '地圖');
  });

  test('things that are not apps match nothing', () {
    expect(open('冷氣'), isNull);
    expect(open('門'), isNull);
    expect(open(''), isNull);
    expect(matchApp('LINE', const []), isNull);
  });
}
