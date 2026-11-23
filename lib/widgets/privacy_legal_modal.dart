import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import 'frosted_inspection_modal.dart';
import 'glass_card.dart';

/// Opens a clean, theme-aware floating bottom sheet displaying Tinta Napló's
/// unofficial-client legal disclaimer, CC BY-NC-SA 4.0 license summary,
/// strictly local data-handling guarantee, optional integrations, and user
/// control / data-deletion details.
Future<void> showPrivacyAndLegalModal(
  BuildContext context, {
  UserProfilePrefs? prefs,
}) {
  final effectivePrefs =
      prefs ?? AppProvidersScope.maybeOf(context)?.settings.prefs;
  String uwu(String input) => UwuHelper.transform(
        input,
        enabled: effectivePrefs?.uwuModeEnabled,
      );

  return showFloatingGlassSheet<void>(
    context: context,
    prefs: effectivePrefs,
    barrierColor: resolveSoftBlurBarrierColor(context, prefs: effectivePrefs),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final closeMode =
          effectivePrefs?.modalCloseMode ?? UserProfilePrefs.activeModalCloseMode;

      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
          ),
          child: FrostedBottomSheetSurface(
            prefs: effectivePrefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Icon(
                        Icons.privacy_tip_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwu('Adatvédelem és jogi nyilatkozat'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (closeMode.showTopX) ...[
                      const SizedBox(width: 8),
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PrivacyLegalSection(
                          icon: Icons.gavel_rounded,
                          title: uwu('Nem hivatalos kliens'),
                          body: uwu(
                            'A Tinta Napló egy független, nem hivatalos kliens, amely nem áll kapcsolatban az e-KRÉTA rendszerrel vagy az eKRÉTA Informatikai Zrt.-vel. Az alkalmazás jelen állapotában („as-is”), bármiféle garancia nélkül érhető el, és független a Pacuka-féle Tinta alkalmazástól (tinta.pacuka.hu).',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.copyright_rounded,
                          title: uwu('Licenc (CC BY-NC-SA 4.0)'),
                          body: uwu(
                            'A Tinta Napló forráskódja Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0) licenc alatt jelenik meg: nem kereskedelmi célra szabadon használható, megosztható és átdolgozható megfelelő forrásmegjelöléssel és ugyanilyen licenc alatt. A harmadik féltől származó függőségek saját nyílt forráskódú licenceik hatálya alatt maradnak.',
                          ),
                          linkLabel:
                              'https://creativecommons.org/licenses/by-nc-sa/4.0/',
                          onLinkTap: () async {
                            try {
                              await launchUrl(
                                Uri.parse(
                                  'https://creativecommons.org/licenses/by-nc-sa/4.0/',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {}
                          },
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.lock_person_rounded,
                          title: uwu('Adatkezelés & Biztonság'),
                          body: uwu(
                            'KRÉTA bejelentkezési adataid, tokenjeid, jegyeid, órarended, üzeneteid és gyorsítótárazott adataid kizárólag helyileg, a saját készülékeden tárolódnak (valamint párosított Wear OS órád esetén közvetlenül oda szinkronizálódnak). Az alkalmazás közvetlenül a hivatalos KRÉTA végpontokkal kommunikál, köztes proxy vagy fejlesztői szerver nélkül.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.bug_report_outlined,
                          title: uwu('Hibajelentések'),
                          body: uwu(
                            'Hibajelentés csak akkor kerül elküldésre, ha azt kifejezetten beküldöd. Ilyenkor kizárólag minimalizált technikai metaadatok (teljes név helyett monogram, alkalmazás- és Android-verzió, aktív téma), az általad írt leírás, valamint az opcionálisan csatolt képernyőkép vagy videó továbbítódik a https://ticket.tintanaplo.hu címre – KRÉTA jelszó, token vagy tanulói azonosító soha nem kerül bele.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.extension_outlined,
                          title: uwu('Opcionális integrációk'),
                          body: uwu(
                            '• Naptárszinkron: A kiválasztott számonkéréseket, házikat és órarendi eseményeket közvetlenül a készüléken választott helyi vagy Google-naptárba írja.\n'
                            '• MenetrendGO & Tanév rendje: Útvonal- vagy iskolai naptárlekérdezést kizárólag akkor küld, ha ezeket a funkciókat aktívan használod.\n'
                            '• GitHub OTA frissítő: Új verziók keresésekor a GitHub Releases felületét (github.com/mlnlbrt10/tinta-naplo) ellenőrzi.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.delete_sweep_outlined,
                          title: uwu('Felhasználói kontroll és adattörlés'),
                          body: uwu(
                            'Bármikor törölheted a gyorsítótárazott adatokat, visszavonhatod a naptár- vagy értesítési engedélyeket az Android beállításaiban, illetve kijelentkezéssel azonnal és véglegesen törölheted a készüléken tárolt helyi munkamenet-tokeneket.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 14),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    label: 'Rendben',
                    uwuEnabled: effectivePrefs?.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PrivacyLegalSection extends StatelessWidget {
  const _PrivacyLegalSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.scheme,
    required this.dividerColor,
    required this.isDark,
    this.linkLabel,
    this.onLinkTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final ColorScheme scheme;
  final Color dividerColor;
  final bool isDark;
  final String? linkLabel;
  final VoidCallback? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(
          alpha: isDark ? 0.55 : 0.72,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
                if (linkLabel != null && onLinkTap != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onLinkTap,
                    child: Text(
                      linkLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: scheme.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
