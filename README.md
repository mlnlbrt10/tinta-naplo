<div align="center">
  <img src="assets/images/tinta_icon.png" alt="Tinta Napló" width="108" height="108" />
  <h1>Tinta Napló</h1>
  <p>Alternatív, nyílt forráskódú e-KRÉTA kliens Androidra és Wear OS-re.</p>

  <p>
    <a href="https://tintanaplo.hu">
      <img src="https://img.shields.io/badge/Web-tintanaplo.hu-000000?style=for-the-badge" alt="Weboldal" />
    </a>
    <a href="https://github.com/mlnlbrt10/tinta-naplo/releases/latest">
      <img src="https://img.shields.io/github/v/release/mlnlbrt10/tinta-naplo?style=for-the-badge&color=ffffff&labelColor=000000&label=Let%C3%B6lt%C3%A9s" alt="Latest Release" />
    </a>
  </p>
</div>

> [!IMPORTANT]
> **A Tinta Napló nem azonos a Tintával.**
> A Tinta egy másik, független alternatív KRÉTA-kliens, amely 2026 októbere óta elérhető, más fejlesztőtől. A két app nem kapcsolódik egymáshoz, és nem ugyanaz a kódjuk.
> * A Tinta oldala: [tinta.pacuka.hu](https://tinta.pacuka.hu/)
> * A Tinta hibáit és kérdéseit ott jelentsd be, ne itt.

---

### Mit tud?

* **Napi nézet & élő órakövetés** – aktuális és következő óra visszaszámlálóval, otthoni widgetekkel és Android 16 / Samsung Now Bar élő értesítéssel.
* **Wear OS társalkalmazás** – órarend, napi infók és jegyek közvetlenül az okosórádon, telefonos szinkronizálással.
* **Jegyek & szellemjegyek** – átlagszámítás, féléves bontás, szellemjegyek hozzáadása, valamint szakképzési ösztöndíj-kalkulátor.
* **Órarend, dolgozatok, házik** – napi és heti órarendbe integrált számonkérések és házi feladatok, plusz natív naptárszinkronizálás egyedi színekkel.
* **Testreszabható értesítések** – azonnali értesítés új jegyről, dolgozatról, elmaradt óráról, helyettesítésről, késésről, hiányzásról és üzenetről, teljesen átírható szövegekkel.
* **MenetrendGo & tanév rendje** – közvetlen utazástervező integráció és iskolai szünetek követése.
* **Megjelenés & alkalmazáson belüli frissítő** – AMOLED fekete és Liquid Glass témák, valódi kompakt minimalista mód, offline gyorsítótár és beépített GitHub OTA frissítő.
* **Közvetlen kommunikáció** – az app kizárólag a hivatalos KRÉTA szerverekkel kommunikál, nincs saját backend vagy adatgyűjtés.

---

### Telepítés

1. Töltsd le a legfrissebb telefonos (`tinta-naplo-android-*.apk`) vagy órás (`tinta-naplo-wear-*.apk`) telepítőt a [GitHub Releases](https://github.com/mlnlbrt10/tinta-naplo/releases/latest) oldalról, vagy a [tintanaplo.hu](https://tintanaplo.hu) címről.
2. Engedélyezd az ismeretlen forrásból származó alkalmazások telepítését.
3. Jelentkezz be a KRÉTA-fiókoddal (a későbbi frissítéseket az app már magától jelzi és telepíti).

---

### Fordítás forráskódból

Szükséges hozzá a Flutter SDK és az Android SDK / JDK.

```bash
git clone [https://github.com/mlnlbrt10/tinta-naplo.git](https://github.com/mlnlbrt10/tinta-naplo.git)
cd tinta-naplo
flutter pub get

# Telefonos APK
flutter build apk --release

# Wear OS APK
cd android && ./gradlew :wear:assembleRelease
