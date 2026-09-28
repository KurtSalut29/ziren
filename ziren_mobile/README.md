# ziren_mobile

The Ziren phone app (Flutter 3.29, Dart 3.7) for two roles:

- **Residents** file reports (a category, the incident location, an optional
  photo or voice note) and SOS alerts, then follow what the agency does with
  them.
- **Responders** receive dispatches, update status on the way to the scene,
  and are told about incidents near them.

English and Filipino (`lib/l10n/`).

## Run

```powershell
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

`dart_defines.json` is not committed. Create it with three keys:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<anon key>",
  "API_BASE_URL": "http://localhost:8000"
}
```

These are compile-time constants, so editing the file does nothing to a
running app: stop it and run again. `AppConfig.validate()` throws at startup if
one is missing. For a phone on USB, `adb reverse tcp:8000 tcp:8000` makes
`localhost:8000` reach the laptop (see the root README).

## Layout

```
lib/
  core/       config, networking, routing, errors, geodesic distance
  features/   one folder per feature (auth, registration, incident_report,
              sos, responder, notifications, ...), split into data /
              domain / presentation where a feature has those layers
  shared/     theme tokens, reusable widgets and dialogs, map
  l10n/       ARB strings and generated localizations
test/         unit, widget, golden and layout-overflow tests
```

## Checks

```powershell
flutter analyze      # No issues found
flutter test         # 751 tests, all passing
```

The suite includes golden-image tests (`test/goldens/`) and overflow tests
that render key screens at 320, 360 and 412 dp, at 1.0x and 2.0x text scale,
in both English and Filipino. A golden test fails when a screen's pixels
change. Regenerate them only for an intended visual change, with
`flutter test --update-goldens`.
