import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/place.dart';

void main() {
  group('formatAddress', () {
    test('joins the parts iOS returns', () {
      expect(
        formatAddress(
          administrativeArea: '彰化縣',
          locality: '彰化市',
          subLocality: '復興里',
          thoroughfare: '中山路三段185巷',
          subThoroughfare: '16號',
          street: '中山路三段185巷16號',
          name: '中山路三段185巷16號',
        ),
        '彰化縣彰化市中山路三段185巷16號',
      );
    });

    test('uses the full line Android returns, without postal code', () {
      expect(
        formatAddress(
          administrativeArea: '彰化縣',
          locality: '彰化市',
          thoroughfare: '中山路三段185巷',
          subThoroughfare: '16',
          street: '500台灣彰化縣彰化市中山路三段185巷16號',
          name: '16',
        ),
        '彰化縣彰化市中山路三段185巷16號',
      );
    });

    test('a city that is its own region is not repeated', () {
      expect(
        formatAddress(
          administrativeArea: '台北市',
          locality: '台北市',
          subLocality: '大安區',
          thoroughfare: '信義路四段',
          subThoroughfare: '1',
        ),
        '台北市大安區信義路四段1號',
      );
      expect(
        formatAddress(
          administrativeArea: '台北市',
          locality: '大安區',
          subLocality: '龍安里',
          street: '信義路四段1號',
        ),
        '台北市大安區信義路四段1號',
      );
    });

    test('falls back to the place name, then to the region alone', () {
      expect(
        formatAddress(administrativeArea: '南投縣', locality: '埔里鎮', name: '日月潭'),
        '南投縣埔里鎮日月潭',
      );
      expect(
        formatAddress(administrativeArea: '南投縣', locality: '埔里鎮', name: '12'),
        '南投縣埔里鎮',
      );
      expect(formatAddress(), isNull);
      expect(formatAddress(street: ' ', name: ''), isNull);
    });

    test('keeps the order of a phone set to English', () {
      expect(
        formatAddress(
          administrativeArea: 'Changhua County',
          locality: 'Changhua City',
          thoroughfare: 'Section 3, Zhongshan Road',
          subThoroughfare: '16',
          street: 'No. 16, Lane 185, Section 3, Zhongshan Rd',
        ),
        'No. 16, Lane 185, Section 3, Zhongshan Rd, Changhua City, '
        'Changhua County',
      );
      const line =
          'No. 16, Lane 185, Section 3, Zhongshan Rd, Changhua City, '
          'Changhua County, Taiwan 500';
      expect(
        formatAddress(
          administrativeArea: 'Changhua County',
          locality: 'Changhua City',
          street: line,
        ),
        line,
      );
    });
  });

  group('Place', () {
    const place = Place(
      latitude: 24.0812345,
      longitude: 120.5586111,
      address: '彰化縣彰化市中山路三段185巷16號',
    );

    test('links to the spot on the map', () {
      expect(
        place.mapLink,
        'https://www.google.com/maps/search/?api=1&query=24.08123,120.55861',
      );
      expect(Uri.parse(place.mapLink).queryParameters['query'], isNotNull);
    });

    test('the message says where, and that help is needed when urgent', () {
      expect(place.message(), '我在這裡：彰化縣彰化市中山路三段185巷16號 ${place.mapLink}');
      expect(place.message(urgent: true), startsWith('我需要幫忙。我在這裡：'));
    });

    test('without an address the coordinates stand in', () {
      const bare = Place(latitude: 24.0812345, longitude: 120.5586111);
      expect(bare.label, '24.0812, 120.5586');
      expect(bare.message(), '我在這裡：${bare.mapLink}');
    });
  });
}
