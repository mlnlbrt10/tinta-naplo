<!DOCTYPE html>
<html lang="hu">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Tinta Napló — Modern alternatív e-KRÉTA kliens</title>
  <meta name="description" content="Tinta Napló: gyors, OLED fekete, liquid glass felületű, nyílt forráskódú e-KRÉTA kliens Androidra." />
  <link rel="icon" type="image/png" href="assets/images/tinta_icon.png" />
  <style>
    :root {
      --bg: #000000;
      --surface: rgba(255, 255, 255, 0.05);
      --surface-hover: rgba(255, 255, 255, 0.09);
      --border: rgba(255, 255, 255, 0.14);
      --text: #f5f5f7;
      --muted: #8e8e93;
      --accent: #f2f2f0;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", "Segoe UI", sans-serif;
    }

    body {
      background-color: var(--bg);
      color: var(--text);
      min-height: 100vh;
      overflow-x: hidden;
      line-height: 1.5;
    }

    .ambient-glow {
      position: fixed;
      top: -180px;
      left: 50%;
      transform: translateX(-50%);
      width: 680px;
      height: 420px;
      background: radial-gradient(circle, rgba(255, 255, 255, 0.08) 0%, rgba(130, 100, 220, 0.04) 45%, rgba(0, 0, 0, 0) 75%);
      pointer-events: none;
      z-index: 0;
    }

    .container {
      position: relative;
      z-index: 1;
      max-width: 980px;
      margin: 0 auto;
      padding: 28px 20px 80px;
    }

    nav {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 18px;
      background: rgba(255, 255, 255, 0.04);
      backdrop-filter: blur(24px);
      -webkit-backdrop-filter: blur(24px);
      border: 1px solid var(--border);
      border-radius: 20px;
      margin-bottom: 72px;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
      font-weight: 700;
      font-size: 1.05rem;
      letter-spacing: -0.02em;
    }

    .brand img {
      width: 34px;
      height: 34px;
      border-radius: 10px;
      border: 1px solid rgba(255,255,255,0.15);
    }

    .nav-link {
      color: var(--muted);
      text-decoration: none;
      font-size: 0.92rem;
      font-weight: 500;
      transition: color 0.2s;
    }

    .nav-link:hover {
      color: var(--text);
    }

    .hero {
      text-align: center;
      max-width: 680px;
      margin: 0 auto 76px;
    }

    .hero-icon {
      width: 112px;
      height: 112px;
      border-radius: 28px;
      margin-bottom: 28px;
      border: 1px solid rgba(255, 255, 255, 0.18);
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.9), 0 0 40px rgba(255, 255, 255, 0.06);
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 999px;
      background: var(--surface);
      border: 1px solid var(--border);
      font-size: 0.82rem;
      color: var(--muted);
      margin-bottom: 20px;
      backdrop-filter: blur(16px);
    }

    .badge span.dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: #ffffff;
      box-shadow: 0 0 8px #ffffff;
    }

    h1 {
      font-size: clamp(2.4rem, 6vw, 3.8rem);
      font-weight: 800;
      letter-spacing: -0.04em;
      line-height: 1.08;
      margin-bottom: 18px;
    }

    .subtitle {
      font-size: 1.12rem;
      color: var(--muted);
      margin-bottom: 34px;
      letter-spacing: -0.01em;
    }

    .cta-group {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 14px;
    }

    .btn-primary {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      background: var(--accent);
      color: #000000;
      font-weight: 700;
      font-size: 0.98rem;
      padding: 14px 26px;
      border-radius: 16px;
      text-decoration: none;
      transition: transform 0.2s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.2s;
    }

    .btn-primary:hover {
      transform: translateY(-2px);
      box-shadow: 0 12px 30px rgba(255, 255, 255, 0.16);
    }

    .btn-secondary {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      background: var(--surface);
      color: var(--text);
      font-weight: 600;
      font-size: 0.98rem;
      padding: 14px 24px;
      border-radius: 16px;
      border: 1px solid var(--border);
      text-decoration: none;
      backdrop-filter: blur(20px);
      transition: background 0.2s, transform 0.2s;
    }

    .btn-secondary:hover {
      background: var(--surface-hover);
      transform: translateY(-2px);
    }

    .meta-info {
      margin-top: 14px;
      font-size: 0.82rem;
      color: var(--muted);
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(270px, 1fr));
      gap: 18px;
    }

    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 26px;
      backdrop-filter: blur(24px);
      -webkit-backdrop-filter: blur(24px);
      transition: transform 0.25s cubic-bezier(0.22, 1, 0.36, 1), border-color 0.25s;
    }

    .card:hover {
      transform: translateY(-3px);
      border-color: rgba(255, 255, 255, 0.28);
    }

    .card h3 {
      font-size: 1.12rem;
      font-weight: 700;
      margin-bottom: 8px;
      letter-spacing: -0.02em;
    }

    .card p {
      color: var(--muted);
      font-size: 0.94rem;
    }

    footer {
      margin-top: 80px;
      text-align: center;
      color: var(--muted);
      font-size: 0.85rem;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
      padding-top: 28px;
    }

    footer a {
      color: var(--text);
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="ambient-glow"></div>

  <div class="container">
    <nav>
      <div class="brand">
        <img src="assets/images/tinta_icon.png" alt="Tinta Napló" />
        <span>Tinta Napló</span>
      </div>
      <a class="nav-link" href="https://github.com/mlnlbrt10/tinta-naplo" target="_blank" rel="noopener">GitHub</a>
    </nav>

    <section class="hero">
      <img class="hero-icon" src="assets/images/tinta_icon.png" alt="Tinta Napló ikon" />
      <div class="badge">
        <span class="dot"></span>
        <span id="version-badge">v1.0.0 • Android</span>
      </div>
      <h1>Az e-KRÉTA,<br />ahogy kinéznie kellene.</h1>
      <p class="subtitle">
        120fps-es animációk, valódi OLED fekete és liquid glass felület, azonnali offline cache és beépített OTA frissítések — reklámok és felesleges sallangok nélkül.
      </p>

      <div class="cta-group">
        <a id="download-btn" class="btn-primary" href="https://github.com/mlnlbrt10/tinta-naplo/releases/latest">
          Letöltés (APK)
        </a>
        <a class="btn-secondary" href="https://github.com/mlnlbrt10/tinta-naplo" target="_blank" rel="noopener">
          Forráskód
        </a>
      </div>
      <div id="release-meta" class="meta-info">Android 8.0+ • arm64-v8a</div>
    </section>

    <section class="grid">
      <div class="card">
        <h3>Liquid Glass & OLED</h3>
        <p>Tiszta fekete háttér, testreszabható frosted glass kártyák és fizikával rendelkező bouncy navigáció 120Hz-en.</p>
      </div>
      <div class="card">
        <h3>Azonnali betöltés</h3>
        <p>A helyi gyorsítótárnak köszönhetően a jegyeid, az órarended és a házik internetkapcsolat nélkül is azonnal megnyílnak.</p>
      </div>
      <div class="card">
        <h3>Teljes e-Ügyintézés</h3>
        <p>Rendszer- és tanári üzenetek kezelése, mellékletek letöltése és szinkronizált olvasottsági állapot.</p>
      </div>
      <div class="card">
        <h3>Határidő-fókusz</h3>
        <p>A közelgő számonkérések és házi feladatok automatikusan határidő szerint rendezve jelennek meg a Főoldalon.</p>
      </div>
      <div class="card">
        <h3>OTA frissítések</h3>
        <p>Nem kell manuálisan APK-kat vadásznod: az alkalmazás jelzi az új verziót és egy kattintással telepíti.</p>
      </div>
      <div class="card">
        <h3>100% Privát</h3>
        <p>Nyílt forráskódú kliens, ami közvetlenül a KRÉTA szervereivel kommunikál. Nincs telemetria, nincs külső szerver.</p>
      </div>
    </section>

    <footer>
      Készítette: <a href="https://github.com/mlnlbrt10" target="_blank" rel="noopener">mlnlbrt</a> • Nem hivatalos e-KRÉTA kliens
    </footer>
  </div>

  <script>
    fetch("https://api.github.com/repos/mlnlbrt10/tinta-naplo/releases/latest")
      .then(res => res.ok ? res.json() : null)
      .then(data => {
        if (!data) return;
        const tag = data.tag_name || "v1.0.0";
        document.getElementById("version-badge").textContent = `${tag} • Android`;
        const apk = (data.assets || []).find(a => a.name.endsWith(".apk"));
        if (apk) {
          const btn = document.getElementById("download-btn");
          btn.href = apk.browser_download_url;
          btn.textContent = `Letöltés (${tag} APK)`;
          const mb = (apk.size / (1024 * 1024)).toFixed(1);
          document.getElementById("release-meta").textContent = `Android 8.0+ • ${mb} MB • ${apk.name}`;
        }
      })
      .catch(() => {});
  </script>
</body>
</html>
