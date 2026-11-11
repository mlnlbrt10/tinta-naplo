# reKRETA

**Egy modern, villámgyors és kompromisszummentes e-Kréta mobilkliens Flutter alapokon.**

*Nincs felesleges bloatware, nincsenek idegesítő bugok — csak a lényeg, letisztult OLED dizájnnal és fejlett tanulói funkciókkal.*

## Mi az a reKRETA?

A **reKRETA** egy független, nyílt forráskódú alternatív kliens az e-Kréta rendszeréhez. Az alkalmazás célja, hogy a hivatalos app nehézkes, lassú felületét felváltsa egy modern, reszponzív, azonnal betöltő felülettel, miközben olyan funkciókat biztosít a diákoknak, amiket a gyári kliens évek óta nem hajlandó implementálni.

## Főbb Funkciók

### OLED & Material You Dizájn

* **True OLED Black téma (`#000000`):** Maximális akkumulátorkímélés AMOLED/OLED kijelzőkön mélyfekete felületekkel és finom kontraszttal.

* **24-28px lekerekítések:** Modern, szerves Material 3 kártyák és felületek.

* **Teljes személyre szabhatóság:** Rendszerszintű dinamikus Material You színek, egyedi témaszínek és tetszőleges hex színkódok minden érdemjegyhez (1–5).

### Jegyek & Fejlett Szellemjegy Számoló

* **Valós tanulmányi átlagok:** Súlyozott tantárgyi és összesített átlagok valós idejű kalkulációja.

* **Egyedi kerekítési küszöbök:** Személyre szabható skálák (pl. beállítható, hogy az 5-ös 4.60-tól vagy 4.75-től induljon a kerekítés során).

* **Interaktív Szellemjegy Szimulátor:**

  * *Összesített kalkulátor:* Tetszőleges súlyú (50%, 100%, 200%) virtuális jegyek hozzáadásával modellezhető a bizonyítvány végső átlaga.

  * *Tantárgyi szimulátor:* Megmutatja, pontosan hány és milyen jegyre van szükséged az adott tantárgy javításához.

### Intelligens Órarend & Napi Nézet

* **Következő óra Hero kártya:** Élő visszaszámláló az éppen futó vagy következő tanóráig, teremszámmal és napi hátralévő órák számával (`Ma még X / Y óra van hátra`).

* **Helyettesítés-kezelés:** Helyettesített tanár áthúzása és a helyettesítő oktató kiemelése.

* **Automatikus fekvő mód:** A „Heti nézet” gomb megnyomásakor az alkalmazás automatikusan átvált fekvő tájolásra, így a teljes munkahét görgetés nélkül áttekinthető.

* **Hétvége elrejtése/megjelenítése:** Egyetlen kapcsolóval testreszabható a naptári nézet.

### Egyesített Tevékenységi Hírfolyam (Feed)

* **Görgethető események:** Értékelések, házi feladatok és bejelentett számonkérések egy közös idővonalon.

* **Gyors szűrősáv:** Külön lapozható fülek: *Összes*, *Jegyek*, *Házik*, *Számonkérések*.

* **Frosted Glass (Soft Blur) részletek:** Kártyára koppintva elmosott hátterű modális felület jeleníti meg a jegy súlyát, pontos leírását, rögzítés idejét és a tanár nevét.

### Kiterjeszthető Profil & Galéria Kép

* **Összecsukható profilkártya:** Azonnali hozzáférés a tanulói adatokhoz anélkül, hogy el kellene hagyni a főoldalt.

* **Egyedi becenév támogatás:** Napszakos dinamikus köszöntés a mentett beceneveddel (*„Szép reggelt / napot / estét / Jó éjszakát, Milu!”*).

* **Saját profilkép:** Kép kiválasztása közvetlenül a telefon galériájából, helyi offline titkosított tárolással.

## Biztonság & Hitelesítés

A reKRETA kiemelt hangsúlyt fektet a biztonságra:

1. **OAuth2 PKCE Flow:** Az iparági szabványú hitelesítési eljárást használja (`code_challenge` + `code_verifier`).

2. **In-App WebView reCAPTCHA kezelés:** A bejelentkezés közvetlenül a hivatalos Kréta IDP felületén (`idp.e-kreta.hu`) történik, így a Google reCAPTCHA ellenőrzések zökkenőmentesen lefutnak.

3. **Titkosított helyi tárolás:** A tokenek és a felhasználói beállítások kizárólag a készülék titkosított kulcstárában (`flutter_secure_storage` / Android Keystore) tárolódnak.

4. **Zéró telemetria:** Semmilyen személyes adat, jelszó vagy statisztika nem kerül harmadik félhez vagy külső szerverre; minden hálózati kérés kizárólag az iskola hivatalos e-Kréta API végpontjaival kommunikál.

## Telepítés & Buildelés

### Előfeltételek

* **Flutter SDK:** `>= 3.19.0`

* **Dart SDK:** `>= 3.3.0`

* **Java Development Kit (JDK):** JDK 21 (OpenJDK)

* **Android SDK:** API 34+ platform tools

### Projekt klónozása és függőségek letöltése

```
git clone https://github.com/mlnlbrt10/reKRETA.git
cd reKRETA
flutter pub get

```

### Futtatás fejlesztői módban (csatlakoztatott eszközön)

```
flutter run

```

### Release APK fordítása

```
flutter build apk --release

```

A lefordított telepítőfájl helye:
`build/app/outputs/flutter-apk/reKRETA-v1.2.0.apk`

## Technikai Stack

| Komponens | Alkalmazott Technológia | 
| ----- | ----- | 
| **Keretrendszer** | [Flutter](https://flutter.dev) (Dart) | 
| **Dizájn Nyelv** | Material Design 3 (OLED Dark UI) | 
| **API Kliens** | `kreta_api` v3 wrapper OAuth2 PKCE-vel | 
| **Adattárolás** | `flutter_secure_storage` (AES titkosítás) | 
| **Képek kezelése** | `image_picker` | 
| **Effektek** | `dart:ui` `BackdropFilter` & `ImageFilter` | 

## Hozzájárulás (Contributing)

Hibát találtál, vagy van egy jó ötleted egy új funkcióhoz? Nyiss bátran egy [Issue-t](https://github.com/mlnlbrt10/reKRETA/issues) vagy küldj egy Pull Requestet!

1. Forkold a repót (`Fork`)

2. Hozz létre egy feature ágat (`git checkout -b feature/UjFeature`)

3. Commitold a változtatásokat (`git commit -m 'feat: új szuper funkció'`)

4. Pushold az ágadra (`git push origin feature/UjFeature`)

5. Nyiss egy Pull Requestet

## Jogi nyilatkozat (Disclaimer)

A **reKRETA** egy független, rajongói projekt, amely nem áll semmilyen kapcsolatban az e-Kréta Informatikai Zrt.-vel, sem az Oktatási Hivatallal vagy a Belügyminisztériummal. Az „e-Kréta” védjegy a jogos tulajdonosát illeti meg. Az alkalmazás kizárólag a hivatalos API végpontokat használja a felhasználó saját azonosítóival.