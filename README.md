# Lenzorium IPTV Player — v1

Branded IPTV **player** for Windows, Android phones, Android TV and Amazon Fire TV Stick, built from one Flutter codebase. It plays the customer's own M3U playlist or Xtream Codes login and contains no channels or content.

```
app/      Flutter app (Windows + Android/TV/Fire TV)
server/   Licence server: trial, activation page, Stripe, reseller credits, "send playlist from phone"
```

## What's in v1

| Area | Done |
|---|---|
| Sources | M3U link, M3U file, Xtream Codes login; several playlists, switch from Home in one tap; QR code to type the playlist on a phone |
| Live TV | Categories / channels / preview with now & next; logos and numbers; favourites; recently watched |
| Zapping | ▲▼ or CH+/− in the player, ◀ last channel, number keys jump to a channel |
| TV guide | EPG grid from XMLTV (gzipped OK) or the Xtream guide; jump to now; refreshed daily and cached on the device |
| Movies / Series | Poster grids by category, details pages, resume where you stopped, seasons and episodes, auto-play next episode |
| Search | One search across channels, movies and series |
| Player | libmpv (media_kit): HLS, MPEG-TS, MP4, MKV, H.264/HEVC, AAC/AC-3; audio track, subtitles, aspect ratio, speed for films and series; reconnects by itself after Wi-Fi drops |
| PiP | Mini-player on Windows; picture-in-picture on Android phones |
| Parental | 4-digit PIN locks chosen categories (hidden from lists and search) |
| Settings | Playlists, PIN, language, theme (Dark / Black), buffer size, TS / HLS, aspect, auto-play, licence, about |
| Control | Keyboard and mouse, touch, and TV remote D-pad (arrows, OK, Back, Menu) on every screen |
| Licence | Device ID + key, 7-day trial, activation by website, 7-day offline grace, reseller credits |

The premium features in the spec (catch-up, multi-view, recording, cloud sync, reseller dashboard UI, casting, extra layouts) are **not** in v1. The reseller **API** is in place.

## Build the app

Requires Flutter 3.22+ (Dart 3.4+). Android builds need Android Studio / SDK; Windows builds need Visual Studio 2022 with "Desktop development with C++".

```bash
cd app
./setup.sh            # or .\setup.ps1 on Windows — generates Gradle/Windows runner files
flutter test          # parser + database tests
flutter run -d windows
flutter run           # with an Android phone, Android TV box or Fire TV Stick connected (adb)
```

Release builds (point the app at your licence server):

```bash
flutter build apk --release --split-per-abi --dart-define=LICENCE_API=https://activate.lenzorium.com
flutter build windows --release --dart-define=LICENCE_API=https://activate.lenzorium.com
dart run msix:create   # Windows installer; set certificate_path in pubspec.yaml to sign it
```

Fire TV: `app-armeabi-v7a-release.apk` runs on all Fire TV Sticks; the arm64 build suits 4K Max. Customers install it with the Downloader app.

### Provider build (XCIPTV style) — optional

Build-time settings can pre-fill an Xtream server so customers only type a username and password:

```bash
flutter build apk --dart-define=DEFAULT_XTREAM_SERVER=http://server.example:8080 --dart-define=LOCK_XTREAM_SERVER=true
```

Both settings are empty by default, so the standard build stays a generic player. A build that ships with one provider's server is tied to that provider's content. Per the Legal section of the product spec, only do this for a provider that is licensed to distribute what it serves, and have the solicitor review it.

### Things to replace before release
- `assets/logo.png`, `android/app/src/main/res/drawable/banner.png` and `lib/widgets/brand.dart` (`LzLogo`) use a placeholder lens mark. Replace them with the real logo.
- `LzColors.accent` in `lib/core/theme.dart` is the brand colour.
- The `[PRICE]` placeholders are in `lib/screens/activate_screen.dart` and `server/src/pages.js`.
- Launcher icons: run `flutter_launcher_icons` or replace the `mipmap-*` folders after `setup.sh`.

## Run the licence server

Node 22.5+ (it uses the built-in `node:sqlite`, so no database server is needed).

```bash
cd server
npm install
npm test                       # 10 API tests
cp .env.example .env           # fill in, then:
node --env-file=.env src/server.js
```

Put it behind HTTPS at `activate.lenzorium.com`, with a reverse proxy that sets `TRUST_PROXY=1`.

| Endpoint | Used by |
|---|---|
| `POST /api/device/check` | App at start-up and every few seconds on Activate / Add playlist. Registers the device, starts its trial, returns its status and any playlists sent from the website |
| `POST /api/device/playlists/ack` | App, after importing a playlist sent from the website. The server then deletes it |
| `GET /` · `POST /api/checkout` | Activation page (QR target): device ID + key + plan → Stripe Checkout |
| `POST /api/stripe/webhook` | Stripe `checkout.session.completed` → activates. Idempotent per payment |
| `GET /setup` · `POST /api/device/playlist` | "Send a playlist to your TV" page (the QR on Add playlist). Undelivered playlists are purged after 24 h |
| `POST /api/reseller/activate` · `GET /api/reseller/me` | Resellers (Bearer API key): spend credits to activate a device |
| `POST /api/admin/resellers` · `POST /api/admin/resellers/:id/credits` · `GET /api/admin/devices/:id` | You (Bearer `ADMIN_TOKEN`) |

Stripe setup: create two one-time Prices (yearly, lifetime), then add a webhook to `https://activate.lenzorium.com/api/stripe/webhook` for `checkout.session.completed`. Yearly purchases stack on top of any time left.

**Google Play:** store rules require Google Play Billing to unlock features inside a Play-distributed app. This build sells licences only through the website (Stripe), which fits the direct-download APK and the Windows .exe. A Play build would need a Play Billing purchase flow added.

## How it fits together

```
lib/
  main.dart, app.dart            start-up, theme, D-pad shortcuts, mini-player overlay
  core/                          config (--dart-define), theme colours, navigation + formatting
  models/                        playlists, channels, movies, series, episodes, programmes
  services/
    m3u_parser.dart              M3U/M3U8: tvg-id, tvg-name, tvg-logo, group-title, tvg-chno, url-tvg
    xtream_api.dart              player_api.php calls + stream link patterns
    xmltv_parser.dart            streaming, gzip-aware XMLTV reader (keeps −12 h … +3 days)
    catalog_db.dart              SQLite store: catalogue, guide, favourites, history/resume
    playlist_sync.dart           downloads a source into the store
    licence_service.dart         device ID/key, check, offline grace
    settings_store.dart          preferences
  state/app_state.dart           licence, playlists, sync, favourites, history
  state/playback.dart            one libmpv player shared by full screen, preview and mini-player
  widgets/focusable.dart         the D-pad building block (focus ring, OK/Menu keys, auto-scroll)
  screens/                       Splash, Activate, Add playlist, Home, Live TV, Guide, Movies/Series,
                                 details, Player, Search, Favourites, Settings
```

The remote keys are OK = select, Back = back, Menu (or F on a keyboard, or long-press) = add to favourites. In the player, OK shows the controls.

## Testing checklist before launch (from the spec)
- Windows 10/11, two Android phones, an Android TV box, Fire TV Stick HD and 4K
- A playlist with 50,000+ items: load, search and scroll
- HLS and TS, HD/4K, HEVC, several audio and subtitle tracks
- Pull the Wi-Fi mid-stream: it should reconnect by itself, or show a clear message
- Every screen with arrows, OK and Back only
- Licence: trial countdown, activation, expiry, 7 days offline

---
Lenzorium Player does not provide any content. Use it only with content you are legally allowed to access.
