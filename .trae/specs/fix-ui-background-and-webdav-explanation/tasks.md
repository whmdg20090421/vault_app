# Tasks
- [ ] Task 1: Fix UI Background Rendering
  - [ ] Move `_BackgroundShell` from wrapping `MaterialApp` to being inside `MaterialApp.builder` in `lib/main.dart`.
  - [ ] Update `buildTheme` in `lib/theme/app_theme.dart` to set `scaffoldBackgroundColor` to `Colors.transparent` ONLY when `bgEnabled` is true. When false, fallback to `scheme.surfaceContainer` (or `scheme.surface` for pureBlack).
