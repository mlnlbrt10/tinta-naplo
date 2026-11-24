import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/bug_report_service.dart';
import 'package:tinta_naplo/services/calendar_sync_service.dart';
import 'package:tinta_naplo/services/dynamic_icon_service.dart';
import 'package:tinta_naplo/services/github_updater_service.dart';
import 'package:tinta_naplo/services/home_widget_sync_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/kreta_notification_service.dart';
import 'package:tinta_naplo/services/menetrend_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/services/wear_sync_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/utils/platform_support.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';

StoredSession _iosTestSession() => StoredSession(
      accessToken: 'ios_access',
      refreshToken: 'ios_refresh',
      idToken: 'ios_id',
      instituteCode: 'klik035277001',
      userName: '71234567890',
      expiresAt: DateTime.now().add(const Duration(minutes: 45)),
    );

Student _iosTestStudent() => Student(
      uid: 'stu_ios_1',
      name: 'Nagy Eszter',
      addressDataList: const ['Budapest'],
      bankAccount: const BankAccount(
        accountNumber: null,
        isReadOnly: true,
        ownerName: null,
        ownerType: null,
      ),
      birthdate: DateTime(2008, 4, 10),
      emailAddress: 'eszter@example.com',
      phoneNumber: '+36301112233',
      schoolYearUID: '2026',
      guardianList: const [],
      instituteCode: 'klik035277001',
      instituteName: 'Radnóti Miklós Gimnázium',
      institution: Institution(
        uid: 'inst_ios',
        shortName: 'Radnóti',
        systemModuleList: const [],
        customizationSettings: const CustomizationSettings(
          delayForNotifications: 0,
          isClassAverageVisible: true,
          isLessonsThemeVisible: true,
          nextServerDeployAsString: '',
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('platform helpers reflect TargetPlatform.iOS override cleanly', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isIOSPlatform, isTrue);
    expect(isAndroidPlatform, isFalse);
    expect(BugReportService.resolveOsVersionLabel(), startsWith('iOS'));

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isIOSPlatform, isFalse);
    expect(isAndroidPlatform, isTrue);
  });

  test('iOS enforces native Liquid Glass and strips Android theme overrides', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final permissivePrefs = const UserProfilePrefs(
      themeStyle: AppThemeStyle.standardDark,
      liquidGlassEnabled: false,
      liquidGlassMode: LiquidGlassMode.smokedObsidian,
      useDynamicColor: true,
      customBackdropPath: '/tmp/custom.jpg',
      cardOpacity: 1.0,
      cardBlurSigma: 0.0,
    )
        .withMinimalistMode(true)
        .withCustomSkin(enabled: true, css: ':root { --bg: #112233; }')
        .withFitymaMode(true)
        .withLiveActivityEnabled(true);

    final effective = permissivePrefs.effectiveForPlatform();
    expect(effective.liquidGlassEnabled, isTrue);
    expect(effective.liquidGlassMode, LiquidGlassMode.classicFrost);
    expect(effective.minimalistModeEnabled, isFalse);
    expect(effective.useDynamicColor, isFalse);
    expect(effective.customSkinEnabled, isFalse);
    expect(effective.fitymaModeEnabled, isFalse);
    expect(effective.liveActivityEnabled, isFalse);
    expect(effective.customBackdropPath, isNull);
    expect(effective.cardOpacity, lessThan(1.0));
    expect(effective.cardBlurSigma, greaterThan(0.0));
    expect(resolveLiquidGlassEnabled(permissivePrefs), isTrue);
    expect(resolveSoftBlurBackdropSigma(permissivePrefs), 10.0);

    final settingsProvider = SettingsProvider(initialPrefs: permissivePrefs);
    expect(settingsProvider.prefs.liquidGlassEnabled, isTrue);
    expect(settingsProvider.prefs.minimalistModeEnabled, isFalse);
  });

  test('iOS theme follows System brightness or explicit Light/Dark mode', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final systemPrefs = const UserProfilePrefs().withFollowSystemTheme(true);
    final lightSystem = OledTheme.buildTheme(
      prefs: systemPrefs,
      platformBrightness: Brightness.light,
    );
    final darkSystem = OledTheme.buildTheme(
      prefs: systemPrefs,
      platformBrightness: Brightness.dark,
    );
    expect(lightSystem.brightness, Brightness.light);
    expect(darkSystem.brightness, Brightness.dark);

    final explicitLight = OledTheme.buildTheme(
      prefs: systemPrefs
          .withFollowSystemTheme(false)
          .copyWith(themeStyle: AppThemeStyle.light),
      platformBrightness: Brightness.dark,
    );
    expect(explicitLight.brightness, Brightness.light);
    expect(
      explicitLight.pageTransitionsTheme.builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
  });

  test('SmoothSharedAxisRoute exposes CupertinoRouteTransitionMixin for iOS swipe-back', () {
    final route = SmoothSharedAxisRoute<void>(page: const SizedBox());
    expect(route, isA<CupertinoRouteTransitionMixin<void>>());
  });

  test('Android-only MethodChannel services no-op safely without invoking native channels on iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    const wearChannel = MethodChannel('test.ios.wear.strict');
    const widgetChannel = MethodChannel('test.ios.widget.strict');
    const calendarChannel = MethodChannel('test.ios.calendar.strict');
    const notifChannel = MethodChannel('test.ios.notif.strict');
    const iconChannel = MethodChannel('test.ios.icon.strict');
    const transitChannel = MethodChannel('test.ios.transit.strict');

    for (final ch in [
      wearChannel,
      widgetChannel,
      calendarChannel,
      notifChannel,
      iconChannel,
      transitChannel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (call) async {
        fail('Unexpected Android MethodChannel call on iOS: ${ch.name}/${call.method}');
      });
    }
    addTearDown(() {
      for (final ch in [
        wearChannel,
        widgetChannel,
        calendarChannel,
        notifChannel,
        iconChannel,
        transitChannel,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ch, null);
      }
    });

    final wear = WearSyncService(channel: wearChannel);
    wear.initialize();
    expect(await wear.consumePendingWatchAuthRequest(), isFalse);
    expect(
      await wear.syncSessionToWatch(session: _iosTestSession()),
      isFalse,
    );
    expect((await wear.getConnectionStatus()).isConnected, isFalse);

    final widgetSync = HomeWidgetSyncService.forTest(widgetChannel);
    widgetSync.initialize();
    expect(await widgetSync.setLiveActivityEnabled(true), isFalse);
    expect(await widgetSync.canPostPromotedNotifications(), isFalse);

    final calendar = CalendarSyncService(channel: calendarChannel);
    expect(await calendar.hasCalendarPermissions(), isFalse);
    expect(await calendar.getAvailableCalendars(), isEmpty);

    await KretaNotificationService.instance.syncBackgroundSchedule();
    await DynamicIconService.setAppIcon('classic');
    await MenetrendService.openInMenetrendGo(prefs: const UserProfilePrefs());
  });

  testWidgets('GitHubUpdaterService opens release URL instead of APK download on iOS',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {

    const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
    const updaterChannel = MethodChannel('hu.mlnlbrt.tintanaplo/updater');
    final launchedUrls = <String>[];
    var updaterInvoked = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method == 'launch') {
        final args = call.arguments as Map<Object?, Object?>?;
        final url = args?['url']?.toString();
        if (url != null) launchedUrls.add(url);
        return true;
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(updaterChannel, (call) async {
      updaterInvoked = true;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updaterChannel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  GitHubUpdaterService.showFrostedUpdateDialog(
                    context,
                    currentVersion: '3.2.0',
                    release: const GitHubReleaseInfo(
                      tagName: 'v3.2.1',
                      title: 'Tinta Napló v3.2.1',
                      releaseNotes: '• iOS támogatás',
                      htmlUrl:
                          'https://github.com/mlnlbrt10/tinta-naplo/releases/tag/v3.2.1',
                      apkDownloadUrl:
                          'https://github.com/mlnlbrt10/tinta-naplo/releases/download/v3.2.1/tinta.apk',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Kiadás megnyitása'), findsOneWidget);
    expect(find.text('Frissítés most'), findsNothing);

    await tester.tap(find.text('Kiadás megnyitása'));
    await tester.pumpAndSettle();

    expect(updaterInvoked, isFalse);
    expect(
      launchedUrls,
      contains('https://github.com/mlnlbrt10/tinta-naplo/releases/tag/v3.2.1'),
    );
  });

  testWidgets(
      'AppSettingsScreen & DeveloperOptionsHubScreen adapt cleanly for iOS Liquid Glass rules',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    var capturedPrefs = const UserProfilePrefs();

    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          session: _iosTestSession(),
          student: _iosTestStudent(),
          kretaClient: KretaClient(),
          prefs: capturedPrefs,
          onPrefsChanged: (next) => capturedPrefs = next,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Android-only sections hidden on iOS
    expect(find.text('Naptár szinkronizálás'), findsNothing);
    expect(find.text('Rendszertéma és Liquid Glass'), findsOneWidget);

    // Open Megjelenés és témák -> pushed subscreen
    await tester.tap(find.text('Megjelenés és témák'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ios-liquid-glass-locked-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ios-theme-chip-system')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ios-theme-chip-dark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ios-theme-chip-light')),
      findsOneWidget,
    );
    // Android-only visual customization switches/options stripped
    expect(find.text('OLED Fekete'), findsNothing);
    expect(find.text('Minimalista mód'), findsNothing);
    expect(find.text('Material You (Rendszerszín követése)'), findsNothing);
    expect(find.text('Alkalmazás ikon'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('ios-theme-chip-light')));
    await tester.pumpAndSettle();
    expect(capturedPrefs.followSystemTheme, isFalse);
    expect(capturedPrefs.themeStyle, AppThemeStyle.light);
    expect(capturedPrefs.liquidGlassEnabled, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('ios-theme-chip-system')));
    await tester.pumpAndSettle();
    expect(capturedPrefs.followSystemTheme, isTrue);
    expect(capturedPrefs.liquidGlassEnabled, isTrue);
  });

  testWidgets(
      'DeveloperOptionsHubScreen hides Wear OS & CSS/icon/backdrop overrides on iOS',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeveloperOptionsHubScreen(
          prefs: const UserProfilePrefs(),
          onPrefsChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('dev-hub-tile-integrations')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-hub-tile-appearance')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('dev-hub-tile-appearance')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saját háttérkép kiválasztása'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('dev-fityma-mode-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-custom-skin-switch')),
      findsNothing,
    );
    expect(find.text('UwU mód'), findsOneWidget);
  });
}
