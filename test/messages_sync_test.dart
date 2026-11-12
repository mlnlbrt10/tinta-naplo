import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/token_storage_service.dart';

StoredSession _buildSession({
  String inst = 'klik-test-001',
  String user = 'tanulo1',
}) {
  return StoredSession(
    accessToken: 'test_access_token',
    refreshToken: 'test_refresh_token',
    idToken: 'test_id_token',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    instituteCode: inst,
    userName: user,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'KretaClient.fetchMessages merges e-Ugyintezes inbox/sajat/sent and system notices sorted newest-first',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final requestedUrls = <String>[];

      final mockHttp = MockClient((req) async {
        requestedUrls.add(req.url.toString());
        final path = req.url.path;
        if (path.endsWith('/postaladaelemek/sajat')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'azonosito': 501,
                  'isElolvasva': false,
                  'isToroltElem': false,
                  'tipus': {'kod': 'BEERKEZETT', 'nev': 'Beérkezett'},
                  'uzenet': {
                    'azonosito': 9501,
                    'kuldesDatum': '2026-11-12T10:15:00Z',
                    'feladoNev': 'Kovács Tanárnő',
                    'feladoTitulus': 'Osztályfőnök',
                    'targy': 'Osztálypénz emlékeztető',
                    'szoveg': '<p>Előnézet szöveg...</p>',
                    'hasCsatolmany': true,
                  },
                },
                {
                  'azonosito': 502,
                  'isElolvasva': true,
                  'isToroltElem': false,
                  'tipus': {'kod': 'ELKULDOTT', 'nev': 'Elküldött'},
                  'uzenet': {
                    'azonosito': 9502,
                    'kuldesDatum': '2026-11-10T08:00:00Z',
                    'feladoNev': 'Teszt Tanuló',
                    'targy': 'Igazolás',
                    'szoveg': 'Mellékeltem az igazolást.',
                  },
                },
              ]),
            ),
            200,
          );
        }
        if (path.endsWith('/postaladaelemek/beerkezett')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'azonosito': 503,
                  'uzenetAzonosito': 9503,
                  'uzenetKuldesDatum': '2026-11-11T14:30:00Z',
                  'uzenetFeladoNev': 'Nagy Igazgató',
                  'uzenetFeladoTitulus': 'Igazgató',
                  'uzenetTargy': 'Pályaválasztási nap',
                  'hasCsatolmany': false,
                  'isElolvasva': true,
                },
              ]),
            ),
            200,
          );
        }
        if (path.endsWith('/postaladaelemek/elkuldott')) {
          // Simulates Kréta returning HTTP 500 when a folder is empty/unavailable
          return http.Response('{"Message":"An error has occured!"}', 500);
        }
        if (path.endsWith('/FaliujsagElemek')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'Uid': 'sys_notice_1',
                  'RogzitoNeve': 'Titkárság',
                  'ErvenyessegKezdete': '2026-11-12T07:00:00Z',
                  'Cim': 'Fűtési karbantartás',
                  'TartalomText': 'Pénteken rövidített órák lesznek.',
                },
              ]),
            ),
            200,
          );
        }
        if (path.endsWith('/Feljegyzesek')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'Uid': 'sys_info_1',
                  'KeszitoTanarNeve': 'Ofő',
                  'KeszitesDatuma': '2026-11-09T09:00:00Z',
                  'Datum': '2026-11-09T09:00:00Z',
                  'Cim': 'Szülői értekezlet',
                  'Tartalom': 'November 20-án 17:00-kor.',
                },
              ]),
            ),
            200,
          );
        }
        return http.Response('[]', 404);
      });

      final client = KretaClient(
        httpClient: mockHttp,
        storage: const TokenStorageService(),
      );
      final messages = await client.fetchMessages(_buildSession());

      expect(requestedUrls, contains(KretaEndpoints.getEugyintezesSajatMessages()));
      expect(requestedUrls, contains(KretaEndpoints.getEugyintezesInboxMessages()));
      expect(requestedUrls, contains(KretaEndpoints.getEugyintezesSentMessages()));

      expect(messages.length, 5);
      // Sorted newest-first:
      // 1) 501 (Nov 12 10:15)
      // 2) sys_notice_1 (Nov 12 07:00)
      // 3) 503 (Nov 11 14:30)
      // 4) 502 (Nov 10 08:00, sent)
      // 5) sys_info_1 (Nov 09 09:00)
      expect(messages[0].uid, '501');
      expect(messages[0].isRead, isFalse);
      expect(messages[0].isSent, isFalse);
      expect(messages[0].isSystemMessage, isFalse);
      expect(messages[0].hasAttachments, isTrue);
      expect(messages[0].senderTitle, 'Osztályfőnök');
      expect(messages[0].detailsLoaded, isFalse);

      expect(messages[1].uid, 'sys_notice_1');
      expect(messages[1].isSystemMessage, isTrue);
      expect(messages[1].isRead, isFalse);

      expect(messages[2].uid, '503');
      expect(messages[2].isRead, isTrue);
      expect(messages[2].messageId, '9503');
      expect(messages[2].detailsLoaded, isFalse);

      expect(messages[3].uid, '502');
      expect(messages[3].isSent, isTrue);

      expect(messages[4].uid, 'sys_info_1');
      expect(messages[4].isSystemMessage, isTrue);
    },
  );

  test(
    'markMessageAsRead persists across app restarts for both e-Ugyintezes and system messages, isolated per account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final readRequests = <Map<String, dynamic>>[];

      final mockHttp = MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/uzenetek/olvasott')) {
          readRequests.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('', 200);
        }
        if (path.endsWith('/postaladaelemek/sajat')) {
          // Server always returns isElolvasva: false to simulate system messages or stale backend
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'azonosito': 777,
                  'isElolvasva': false,
                  'tipus': {'kod': 'BEERKEZETT'},
                  'uzenet': {
                    'azonosito': 88777,
                    'kuldesDatum': '2026-11-12T12:00:00Z',
                    'feladoNev': 'Tanár Úr',
                    'targy': 'Dolgozat időpont',
                    'szoveg': 'Holnap írunk.',
                  },
                },
              ]),
            ),
            200,
          );
        }
        if (path.endsWith('/FaliujsagElemek')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'Uid': 'notice_99',
                  'RogzitoNeve': 'Iskola',
                  'ErvenyessegKezdete': '2026-11-12T06:00:00Z',
                  'Cim': 'Rendszer hír',
                  'TartalomText': 'Szöveg',
                },
              ]),
            ),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final sessionA = _buildSession(inst: 'inst-a', user: 'user-a');
      final sessionB = _buildSession(inst: 'inst-b', user: 'user-b');

      // Run 1: Load and mark both messages as read in Session A
      final clientRun1 = KretaClient(
        httpClient: mockHttp,
        storage: const TokenStorageService(),
      );
      final initialList = await clientRun1.fetchMessages(sessionA);
      expect(initialList.where((m) => !m.isRead).length, 2);

      final inboxMsg = initialList.firstWhere((m) => m.uid == '777');
      final sysMsg = initialList.firstWhere((m) => m.uid == 'notice_99');

      await clientRun1.markMessageAsRead(sessionA, inboxMsg);
      await clientRun1.markMessageAsRead(sessionA, sysMsg);

      // Server olvasott endpoint called only for e-Ügyintézés message (with uzenetAzonosito)
      expect(readRequests.length, 1);
      expect(readRequests.first['isOlvasott'], isTrue);
      expect(readRequests.first['uzenetAzonositoLista'], [88777]);

      // Run 2: Brand-new KretaClient & TokenStorageService (simulating cold app restart)
      final clientRun2 = KretaClient(
        httpClient: mockHttp,
        storage: const TokenStorageService(),
      );
      final reloadedA = await clientRun2.fetchMessages(sessionA);
      expect(reloadedA.every((m) => m.isRead), isTrue);

      // Session B must NOT inherit Session A's read cache
      final loadedB = await clientRun2.fetchMessages(sessionB);
      expect(loadedB.where((m) => !m.isRead).length, 2);
    },
  );

  test(
    'fetchMessageDetail loads full body, recipients, and attachments from /postaladaelemek/{id}',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final mockHttp = MockClient((req) async {
        if (req.url.path.endsWith('/postaladaelemek/503')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'azonosito': 503,
                'isElolvasva': true,
                'tipus': {'kod': 'BEERKEZETT'},
                'uzenet': {
                  'azonosito': 9503,
                  'kuldesDatum': '2026-11-11T14:30:00Z',
                  'feladoNev': 'Nagy Igazgató',
                  'feladoTitulus': 'Igazgató',
                  'targy': 'Pályaválasztási nap',
                  'szoveg': '<p>Teljes részletes szöveg a csatolmányban.</p>',
                  'cimzettLista': [
                    {'nev': '11.A osztály'},
                  ],
                  'csatolmanyok': [
                    {'azonosito': 4412, 'fajlNev': 'programfuzet.pdf'},
                  ],
                },
              }),
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final client = KretaClient(
        httpClient: mockHttp,
        storage: const TokenStorageService(),
      );
      final summary = KretaMessage.fromJson({
        'azonosito': 503,
        'uzenetAzonosito': 9503,
        'uzenetKuldesDatum': '2026-11-11T14:30:00Z',
        'uzenetFeladoNev': 'Nagy Igazgató',
        'uzenetTargy': 'Pályaválasztási nap',
        'hasCsatolmany': true,
        'isElolvasva': false,
      });
      expect(summary.detailsLoaded, isFalse);
      expect(summary.body, isEmpty);

      final detailed = await client.fetchMessageDetail(_buildSession(), summary);
      expect(detailed.detailsLoaded, isTrue);
      expect(detailed.cleanBody, 'Teljes részletes szöveg a csatolmányban.');
      expect(detailed.recipients, ['11.A osztály']);
      expect(detailed.attachments.length, 1);
      expect(detailed.attachments.first.id, '4412');
      expect(detailed.attachments.first.fileName, 'programfuzet.pdf');
    },
  );
}
