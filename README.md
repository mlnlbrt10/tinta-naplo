<div align="center">
  <img src="assets/images/tinta_icon.png" alt="Tinta Napló ikon" width="116" height="116" />
  <h1>Tinta Napló</h1>
  <p><strong>Letisztult, minimalista, reklámmentes alternatív e-KRÉTA kliens Androidra</strong></p>

  <p>
    <a href="https://github.com/mlnlbrt10/tinta-naplo/releases/latest">
      <img src="https://img.shields.io/github/v/release/mlnlbrt10/tinta-naplo?style=for-the-badge&color=ffffff&labelColor=000000&label=Let%C3%B6lt%C3%A9s" alt="Latest Release" />
    </a>
    <img src="https://img.shields.io/badge/Platform-Android_arm64-000000?style=for-the-badge&logo=android&logoColor=white" alt="Android arm64" />
    <img src="https://img.shields.io/badge/Flutter-Dart-000000?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter & Dart" />
  </p>
</div>

---

## Fő funkciók

- **Letisztult, minimalista OLED (`#000000`) dizájn** — valódi mélyfekete felület testreszabható háttéreffektekkel, opcionális soft blur megjelenéssel és 120 fps-es animációkkal.
- **MenetrendGo integráció** — közvetlen helyi és helyközi menetrend-elérés közvetlenül az alkalmazásból.
- **Ösztöndíj kalkulátor** — automatikus tanulmányi átlag- és várható ösztöndíjbecslés a jegyek alapján.
- **Villámgyors offline gyorsítótár** — jegyek, órarend, hiányzások, házi feladatok és üzenetek azonnali megjelenítése internetkapcsolat nélkül is.
- **Határidő szerint rendezett dolgozatok és házik** — a közelgő számonkérések és házi feladatok mindig a határidő szerint rendezve jelennek meg.
- **Beépített OTA frissítő** — új kiadás megjelenésekor egyetlen érintéssel frissíthető közvetlenül a GitHub Releasesből.
- **Zéró adatgyűjtés** — nincs köztes szerver vagy telemetria; minden adat kizárólag közvetlenül a hivatalos KRÉTA szerverekkel kommunikál.

---

## Letöltés és telepítés

A legfrissebb kiadás (`Tinta-Naplo-v1.0.0.apk`) elérhető a [GitHub Releases](https://github.com/mlnlbrt10/tinta-naplo/releases/latest) oldalon:

1. Töltsd le a legfrissebb `Tinta-Naplo-v*.apk` fájlt a [Releases](https://github.com/mlnlbrt10/tinta-naplo/releases/latest) oldalról.
2. Engedélyezd az ismeretlen forrásból származó alkalmazások telepítését.
3. Telepítsd az APK-t, majd jelentkezz be a KRÉTA-fiókoddal.

Az újabb kiadások ezt követően már közvetlenül az alkalmazáson belül, a **Beállítások / Névjegy** menüpontból is letölthetők és telepíthetők.

---

## Fordítás forráskódból

Előfeltételek: Flutter SDK, Android SDK / JDK.

```bash
git clone https://github.com/mlnlbrt10/tinta-naplo.git
cd tinta-naplo
flutter pub get
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols
```

A lefordított APK helye: `build/app/outputs/flutter-apk/Tinta-Naplo-v1.0.0.apk`.

---

## Jogi nyilatkozat

A **Tinta Napló** egy független, nyílt forráskódú kliensalkalmazás, és nem áll kapcsolatban az eKRÉTA Informatikai Zrt.-vel.
