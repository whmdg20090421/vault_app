# UI Background and WebDAV Spec

## Why
1. The custom background feature renders a black screen when disabled. This happens because `_BackgroundShell` is placed outside `MaterialApp` where it lacks `Directionality` and `MediaQuery`, causing it to fail or render incorrectly against the Android window background. Furthermore, the `Scaffold` background remains fully transparent even when the custom background is disabled.
2. The WebDAV connection fails with a DNS lookup error (`Failed host lookup`) in Dart. The user requested an explanation of how `webdav-js` works compared to the current Dart `webdav_client` and why the latter fails in this context.

## What Changes
- Move `_BackgroundShell` inside the `builder` property of `MaterialApp` so it receives the proper Flutter app context.
- Update `app_theme.dart` to conditionally set `scaffoldBackgroundColor` to `Colors.transparent` only when `bgEnabled` is true. If false, it will use the theme's default surface color.
- Explain the differences between browser-based JS WebDAV and Dart's native networking stack.

## Impact
- Affected specs: UI rendering, Theme management
- Affected code: `lib/main.dart`, `lib/theme/app_theme.dart`

## ADDED Requirements
### Requirement: Stable Default Background
The system SHALL display the theme's default background color correctly without falling back to a black screen when the custom background is disabled.

#### Scenario: Success case
- **WHEN** the user turns off the custom background switch
- **THEN** the app background reverts to the standard theme background (e.g., white or dark gray) and the `Scaffold` is opaque.

## MODIFIED Requirements
### Requirement: App Theming
The `scaffoldBackgroundColor` is no longer always transparent, but conditionally transparent based on the `bgEnabled` flag.
