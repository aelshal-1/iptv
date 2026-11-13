# IPTV Player (Android & iOS)

Flutter app for Xtream Codes accounts: Live TV, Movies, Series, favorites, continue watching,
whole-library download with progress, per-category refresh, category reorder/hide, search,
subtitle & audio track selection. English / Arabic.

Builds run on GitHub Actions (`.github/workflows/build.yml`). Every push to `main` publishes a
release with the APK and an unsigned IPA. Platform folders are generated in CI by
`flutter create` and patched by `tool/patch_platforms.py`.

## iOS via TestFlight

Uses the same Apple signing setup as Daftar. Add these repository secrets
(Settings → Secrets and variables → Actions), same values as in Daftar:
`APPLE_TEAM_ID`, `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`.

Bundle ID: `com.aelshal.iptvPlayer`. CI registers it and creates the App Store
profile with the API key. If that is refused, make the profile by hand and add it as
`IOS_PROFILE_APP_BASE64`. Create the app once in App Store Connect
(Apps → + → New App, that bundle ID). Builds then appear in TestFlight.
