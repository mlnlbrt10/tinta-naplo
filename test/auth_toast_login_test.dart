import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinta_naplo/screens/login_screen.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/tinta_toast.dart';

void main() {
  testWidgets(
    'LoginScreen uses pure #000000 OLED canvas, seamless edge-faded screenshots, MenetrendGO link, zero AI-slop, and single CTA',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final launchedCalls = <MethodCall>[];
      const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, (call) async {
        launchedCalls.add(call);
        if (call.method == 'canLaunch') return true;
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, null);
      });

      bool webAuthTapped = false;
      const prefs = UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: LoginScreen(
            prefs: prefs,
            onLaunchWebAuth: () => webAuthTapped = true,
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('OAuth2 PKCE'), findsNothing);
      expect(find.textContaining('igazán jóra'), findsNothing);
      expect(
        find.textContaining('Lépj be biztonságosan'),
        findsNothing,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF000000));

      expect(find.text('Tinta Napló'), findsOneWidget);
      expect(find.text('Készen állsz?'), findsOneWidget);
      expect(find.text('Bejelentkezés KRÉTA-val'), findsOneWidget);

      final ctaHeadline = tester.widget<Text>(
        find.text('Készen állsz?'),
      );
      expect(ctaHeadline.style?.color, Colors.white);
      expect(ctaHeadline.style?.fontSize, 28.0);
      expect(ctaHeadline.style?.fontWeight, FontWeight.w800);
      expect(ctaHeadline.style?.letterSpacing, -0.6);
      expect(
        find.ancestor(
          of: find.text('Készen állsz?'),
          matching: find.byWidgetPredicate(
            (w) => w is ShaderMask && w.blendMode == BlendMode.srcIn,
          ),
        ),
        findsOneWidget,
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.clipBehavior, Clip.none);
      expect(pageView.controller?.viewportFraction, closeTo(0.85, 0.001));
      expect(
        find.ancestor(
          of: find.byType(PageView),
          matching: find.byWidgetPredicate(
            (w) => w is ShaderMask && w.blendMode == BlendMode.dstIn,
          ),
        ),
        findsOneWidget,
      );

      bool hasShowcaseImage(String assetPath) => find
          .byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName == assetPath,
          )
          .evaluate()
          .isNotEmpty;

      // Slide 1
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_1_lesson.webp'),
        isTrue,
      );
      expect(
        find.text(
          'Kövesd az órád, lásd a következőt. Mindig képben lehetsz a napod menetével.',
        ),
        findsOneWidget,
      );

      // Slide 2
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_2_scholarship.webp'),
        isTrue,
      );
      expect(
        find.text(
          'Tűzd ki, érd el. Az ösztöndíj-kalkulátorral semmi se lehetetlen.',
        ),
        findsOneWidget,
      );

      // Slide 3
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_3_timetable.webp'),
        isTrue,
      );
      expect(
        find.text(
          'Egyből csak a lényeg. Lásd könnyen, milyen órád marad el, és melyik lesz helyettesítve.',
        ),
        findsOneWidget,
      );

      // Slide 4
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_4_themes.webp'),
        isTrue,
      );
      expect(
        find.text(
          'A végtelen személyre szabásnak köszönhetően igazán olyan lehet az app, amilyennek Te elképzelted.',
        ),
        findsOneWidget,
      );

      // Slide 5 (Expanded MenetrendGO card + interactive caption link)
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Időben'), findsOneWidget);
      expect(find.text('MenetrendGO'), findsOneWidget);
      expect(find.text('28 perc'), findsOneWidget);
      expect(find.text('14 perccel az 1. óra előtt beérsz'), findsOneWidget);

      final richCaptionFinder = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText() ==
                'Mindig tudd, mikor kell menned, a MenetrendGO integrációnak köszönhetően.',
      );
      expect(richCaptionFinder, findsOneWidget);

      final richCaption = tester.widget<RichText>(richCaptionFinder);
      TextSpan? linkSpan;
      richCaption.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'MenetrendGO') {
          linkSpan = span;
          return false;
        }
        return true;
      });
      expect(linkSpan, isNotNull);
      expect(linkSpan!.recognizer, isA<TapGestureRecognizer>());
      expect(linkSpan!.style?.color, const Color(0xFF38BDF8));
      expect(linkSpan!.style?.decoration, TextDecoration.underline);

      (linkSpan!.recognizer! as TapGestureRecognizer).onTap?.call();
      await tester.pump();
      expect(
        launchedCalls.any(
          (c) =>
              (c.arguments as Map?)?['url'] == 'https://menetrendgo.hu' &&
              (c.method == 'launch' || c.method == 'launchUrl'),
        ),
        isTrue,
      );

      await tester.tap(find.text('Bejelentkezés KRÉTA-val'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(webAuthTapped, isTrue);
    },
  );

  testWidgets(
    'LoginScreen renders without overflow on compact 360x640 screens across slides',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const prefs = UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack);
      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: LoginScreen(
            prefs: prefs,
            onLaunchWebAuth: () {},
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      for (int i = 0; i < 4; i++) {
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('Időben'), findsOneWidget);
      expect(find.text('Bejelentkezés KRÉTA-val'), findsOneWidget);
    },
  );

  testWidgets(
    'TintaToast mounts on root overlay anchored near top and replaces previous toast cleanly',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => TintaToast.info(context, 'Első üzenet'),
                    child: const Text('First'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        TintaToast.success(context, 'Második sikeres üzenet'),
                    child: const Text('Second'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('First'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Első üzenet'), findsOneWidget);

      final rect = tester.getRect(find.text('Első üzenet'));
      expect(rect.top, lessThan(120.0));

      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Első üzenet'), findsNothing);
      expect(find.text('Második sikeres üzenet'), findsOneWidget);

      TintaToast.dismissCurrent();
      await tester.pump();
    },
  );
}
