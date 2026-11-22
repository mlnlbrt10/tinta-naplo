import 'package:flutter/material.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'frosted_inspection_modal.dart';
import 'glass_card.dart';

/// Opens a clean, theme-aware floating bottom sheet displaying Tinta Napló's
/// unofficial-client legal disclaimer, strictly local data-handling guarantee,
/// and anonymized bug-report notice.
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
                    TactileBounce(
                      onTap: () => Navigator.of(sheetContext).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.onSurface.withValues(
                            alpha: isDark ? 0.08 : 0.06,
                          ),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
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
                            'A Tinta Napló egy független, nyílt forráskódú (GNU GPLv3) projekt, amely nem áll kapcsolatban az e-KRÉTA Zrt.-vel. Az alkalmazás jelen állapotában („as-is”), bármiféle garancia nélkül érhető el.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _PrivacyLegalSection(
                          icon: Icons.lock_person_rounded,
                          title: uwu('Adatkezelés & Biztonság'),
                          body: uwu(
                            'Bejelentkezési adataid, tokenjeid, jegyeid és személyes iskolai adataid kizárólag helyileg, a készülékeden tárolódnak, és közvetlenül a hivatalos KRÉTA API-val kommunikálnak - harmadik fél vagy fejlesztői szerverre soha nem kerülnek.',
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
                            'Az opcionális hibajelentések csak akkor küldenek adatot, ha kifejezetten beküldöd őket: kizárólag anonimizált technikai metaadatokat (app- és Android-verzió, aktív téma) és az általad írt leírást.',
                          ),
                          scheme: scheme,
                          dividerColor: theme.dividerColor,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    uwu('Rendben'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final ColorScheme scheme;
  final Color dividerColor;
  final bool isDark;

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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
