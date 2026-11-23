<div align="center">
  <img src="assets/images/tinta_icon.png" alt="Tinta Napló" width="112" height="112" />
  <h1>Tinta Napló</h1>
  <p>Alternatív, független e-KRÉTA kliens Androidra és Wear OS-re.</p>

  <p>
    <a href="https://tintanaplo.hu">
      <img src="https://img.shields.io/badge/Weboldal-tintanaplo.hu-000000?style=for-the-badge" alt="Weboldal" />
    </a>
    <a href="https://github.com/mlnlbrt10/tinta-naplo/releases/latest">
      <img src="https://img.shields.io/github/v/release/mlnlbrt10/tinta-naplo?style=for-the-badge&color=ffffff&labelColor=000000&label=Let%C3%B6lt%C3%A9s" alt="Latest Release" />
    </a>
    <a href="https://creativecommons.org/licenses/by-nc-sa/4.0/">
      <img src="https://img.shields.io/badge/Licenc-CC_BY--NC--SA_4.0-000000?style=for-the-badge" alt="CC BY-NC-SA 4.0" />
    </a>
  </p>
</div>

> [!IMPORTANT]
> **A Tinta Napló nem azonos a Tintával.**
> A Tinta egy másik, független alternatív KRÉTA-kliens, amely 2026 októbere óta elérhető, más fejlesztőtől. A két app nem kapcsolódik egymáshoz, és nem ugyanaz a kódjuk.
> * A Tinta oldala: [tinta.pacuka.hu](https://tinta.pacuka.hu/)
> * A Tinta hibáit és kérdéseit ott jelentsd be, ne itt.

---

## Fő funkciók

### Főoldal, Órarend & Live Activity
* **Élő óra- és szünetkövetés:** Vizuális visszaszámláló gyűrű az óraszám körül órán, szünetben és suli előtt is, az utolsó percben másodpercalapú visszaszámlálással.
* **Android 16 Live Activity & Samsung Now Bar:** Az aktuális óra és a hátralévő idő folyamatos megjelenítése a zárolási képernyőn és az állapotsoron, az app megnyitása nélkül is.
* **Kezdőképernyős widgetek:** 2×1-es (aktuális óra + visszaszámláló gyűrű) és 2×2-es (aktuális + következő óra) widgetek.
* **Órarendbe integrált dolgozatok és házik:** A számonkérések és a házi feladatok közvetlenül az adott napi órarendben is megjelennek (külön ki/bekapcsolható nézetekkel), egyedi naptárválasztóval és testreszabható óraszám-színekkel.
* **Google Naptár szinkronizálás:** Közelgő dolgozatok, felelések és házi feladatok automatikus szinkronizálása natív naptárba, eseménytípusonként választható színekkel.

### Jegyek, Ösztöndíj & Hiányzások
* **Átlaghatás és Aura Glow:** Minden jegynél azonnal látszik, mennyit húz az adott tantárgy átlagán, a frissen beírt értékelések pedig Aura Glow kiemelést kapnak.
* **Szellemjegyek & célátlag-kalkulátor:** Tantárgyakon belül hozzáadható szellemjegyek azonnali átlag-számítással, plusz reális céljegy-javaslatok (nem csak 5-ösökkel számolva).
* **Szakképzési ösztöndíj-kalkulátor:** Tanulmányi átlag alapú ösztöndíj-becslés és lépésenkénti célkövetés.
* **Átlátható hiányzások:** Tantárgyankénti százalékos bontás és órarend-stílusú napi nézet, ahol pirossal látszanak a mulasztott órák.

### Wear OS társalkalmazás
* Külön **Wear OS** alkalmazás a csuklódra, telefonos szinkronizálással.
* Elérhető róla az aktuális és a következő óra, a mai és a holnapi órarend, valamint a legutóbbi jegyek és számonkérések.

### MenetrendGO & Tanév rendje
* **MenetrendGO integráció:** Reggeli és délutáni ingázáshoz igazított menetrend-kártya a Főoldalon, állítható gyaloglási tempóval (3–8 km/h) és közlekedési módokkal (vonat, busz stb.).
* **Tanév rendje:** Az iskola adatai alapján lekérdezett tanítási szünetek és munkanap-áthelyezések a profilmenüben.

### Értesítések & Testreszabás
* **Azonnali, átírható értesítések:** Értesítés új jegyről, számonkérésről, elmaradt óráról, helyettesítésről, késésről, hiányzásról és új üzenetről — kategóriánként kapcsolhatóan, teljesen szerkeszthető szövegsablonokkal.
* **Megjelenés & témák:** Valódi AMOLED fekete (`#000000`), letisztult Világos mód, **Liquid Glass** (0–100% áttetszőség + blur + élő hátterek), kompakt **Minimalista mód**, valamint saját **custom CSS** támogatás.
* **Extrák:** Beépített **GitHub OTA frissítő**, offline gyorsítótár, 100+ napszakhoz igazodó üdvözlő üzenet, és kikapcsolható UwU mód.
* **Közvetlen kommunikáció:** Nincs köztes szerver vagy adatgyűjtés; az alkalmazás közvetlenül a hivatalos e-KRÉTA végpontokkal kommunikál.

---

## Telepítés

1. Töltsd le a legfrissebb telefonos (`tinta-naplo-android-*.apk`) vagy órás (`tinta-naplo-wearos-*.apk`) telepítőt a [GitHub Releases](https://github.com/mlnlbrt10/tinta-naplo/releases/latest) oldalról, vagy a [tintanaplo.hu](https://tintanaplo.hu) címről.
2. Engedélyezd az ismeretlen forrásból származó alkalmazások telepítését.
3. Telepítsd az APK-t, majd jelentkezz be a KRÉTA-fiókoddal (a későbbi verziókat az app már magától jelzi és telepíti).

---

## Fordítás forráskódból

Szükséges hozzá a Flutter SDK és az Android SDK / JDK.

```bash
git clone [https://github.com/mlnlbrt10/tinta-naplo.git](https://github.com/mlnlbrt10/tinta-naplo.git)
cd tinta-naplo
flutter pub get

# Telefonos APK
flutter build apk --release

# Wear OS APK
cd android && ./gradlew :wear:assembleRelease
```

---

## Jogi nyilatkozat & Licenc

* **Független fejlesztés:** A **Tinta Napló** egy teljes mértékben független, nem hivatalos kliensalkalmazás. Nem áll semmilyen kapcsolatban az e-KRÉTA rendszerrel, az eKRÉTA Informatikai Zrt.-vel, sem annak hivatalos fejlesztőivel vagy üzemeltetőivel, és nem minősül hivatalos terméknek. Az alkalmazás „jelen állapotában” (*as-is*), bármiféle garancia nélkül érhető el.
* **Licenc:** A projekt a [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/) licenc alatt áll (csak nem kereskedelmi célra használható fel és módosítható, a forrás megjelölésével és azonos licenc alatt történő továbbadással).
* **Köszönetnyilvánítás:** Az ikonok kialakítását a [Firka (QwIT)](https://firka.app/) inspirálta.
