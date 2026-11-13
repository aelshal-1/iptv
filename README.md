# IPTV Player (Android & iOS)

Flutter app for Xtream Codes accounts: Live TV, Movies, Series, favorites, continue watching,
whole-library download with progress, per-category refresh, category reorder/hide, search,
subtitle & audio track selection. English / Arabic.

Builds run on GitHub Actions (`.github/workflows/build.yml`). Every push to `main` publishes a
release with the APK and an unsigned IPA. Platform folders are generated in CI by
`flutter create` and patched by `tool/patch_platforms.py`.
