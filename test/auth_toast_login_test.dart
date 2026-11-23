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

      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('OAuth2 PKCE'), findsNothing);
      expect(
        find.textContaining('Lépj be biztonságosan'),
        findsNothing,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF000000));

      expect(find.text('Tinta Napló'), findsOneWidget);
      expect(find.text('Bejelentkezés KRÉTA-val'), findsOneWidget);
      // Top-right slide counter pill (`01 / 07`) and category labels were removed.
      expect(find.text('01 / 07'), findsNothing);
      expect(find.text('04 / Ösztöndíj'), findsNothing);

      final alignFinder = find.ancestor(
        of: find.byKey(const ValueKey<String>('login-hero-headline')),
        matching: find.byType(Align),
      );
      expect(alignFinder, findsAtLeastNWidgets(1));
      expect(
        tester.widget<Align>(alignFinder.first).alignment,
        Alignment.center,
      );

      final ctaHeadline = tester.widget<RichText>(
        find.byKey(const ValueKey<String>('login-hero-headline')),
      );
      expect(ctaHeadline.textAlign, TextAlign.center);
      final rootSpan = ctaHeadline.text as TextSpan;
      final children = rootSpan.children!;
      expect(children.length, 2);
      expect((children[0] as TextSpan).text, 'Készen állsz valami ');
      final secondSpan = children[1] as TextSpan;
      expect(secondSpan.text, 'igazán jóra?');
      expect(secondSpan.style?.color, const Color(0xFF3B82F6));
      expect(secondSpan.style?.fontWeight, FontWeight.w900);
      expect(rootSpan.style?.fontFamily, OledTheme.defaultFontFamily);

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.clipBehavior, Clip.none);
      expect(pageView.controller?.viewportFraction, closeTo(0.85, 0.001));

      bool hasShowcaseImage(String assetPath) => find
          .byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName == assetPath &&
                w.fit == BoxFit.contain,
          )
          .evaluate()
          .isNotEmpty;

      // Frameless redesigned LoginScreen: NO fake phone bezel / status bar clock overlay
      expect(
        find.byKey(const ValueKey<String>('login-phone-mockup-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('login-phone-time-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('login-slide-dot-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('login-slide-dot-6')),
        findsOneWidget,
      );

      // Slide 1 + editorial callout & typography (numbered kickers removed)
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_home.jpg'),
        isTrue,
      );
      expect(find.text('01 / ÉLŐ FŐOLDAL'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('login-hero-headline')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Minden fontos infó egy helyen - aktuális óra, házik és jegyek átlaghatással.',
        ),
        findsOneWidget,
      );

      // Slide 2
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-1')),
        findsOneWidget,
      );
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_timetable.jpg'),
        isTrue,
      );
      expect(
        find.text(
          'Átlátható heti órarend helyettesítésekkel, elmaradt órákkal és házikkal.',
        ),
        findsOneWidget,
      );

      // Slide 3
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-2')),
        findsOneWidget,
      );
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_grades.jpg'),
        isTrue,
      );
      expect(
        find.text(
          'Tantárgyankénti átlagok és jegyek, rendezhetően és azonnal átláthatóan.',
        ),
        findsOneWidget,
      );

      // Slide 4
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-3')),
        findsOneWidget,
      );
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_scholarship.jpg'),
        isTrue,
      );
      expect(
        find.text(
          'Tűzd ki, érd el - kövesd az ösztöndíjadat és a következő sávhoz szükséges lépéseket.',
        ),
        findsOneWidget,
      );

      // Slide 5
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-4')),
        findsOneWidget,
      );
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_absences.jpg'),
        isTrue,
      );
      expect(
        find.text(
          'Hiányzások tantárgyanként és napi órarend-nézetben, pirossal kiemelve.',
        ),
        findsOneWidget,
      );

      // Slide 6
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-5')),
        findsOneWidget,
      );
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_themes.jpg'),
        isTrue,
      );
      expect(
        find.text(
          'OLED fekete, Material You és Liquid Glass - szabd teljesen magadra az appot.',
        ),
        findsOneWidget,
      );

      // Slide 7 (Expanded MenetrendGO glass card + interactive caption link)
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('login-showcase-stage-6')),
        findsOneWidget,
      );
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

      // Infinite loop: swiping past Slide 7 wraps seamlessly back to Slide 1
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        hasShowcaseImage('assets/images/showcase/showcase_home.jpg'),
        isTrue,
      );
      // Top-right pagination pill remains removed on LoginScreen
      expect(find.text('01 / 07'), findsNothing);
      expect(find.text('02 / 07'), findsNothing);

      await tester.tap(find.text('Bejelentkezés KRÉTA-val'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(webAuthTapped, isTrue);

      // Subtle footer link below CTA opens the Privacy Policy & Legal Disclaimer modal
      final footerLink = find.text('Nem hivatalos e-KRÉTA kliens • Adatvédelem');
      expect(footerLink, findsOneWidget);
      expect(
        tester.getRect(footerLink).top,
        greaterThan(tester.getRect(find.text('Bejelentkezés KRÉTA-val')).bottom),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('login-privacy-legal-link')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Adatvédelem és jogi nyilatkozat'), findsOneWidget);
      expect(find.text('Nem hivatalos kliens'), findsOneWidget);
      expect(find.text('Adatkezelés & Biztonság'), findsOneWidget);
      expect(find.text('Hibajelentések'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Adatvédelem és jogi nyilatkozat'), findsNothing);
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
      await tester.pump(const Duration(milliseconds: 600));

      for (int i = 0; i < 6; i++) {
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pump(const Duration(milliseconds: 600));
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
