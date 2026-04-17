import 'dart:io';

class _Args {
  final bool apply;
  final bool check;
  final bool requireChangelog;
  final String? writeReleaseNotesPath;

  _Args({
    required this.apply,
    required this.check,
    required this.requireChangelog,
    required this.writeReleaseNotesPath,
  });
}

_Args _parseArgs(List<String> args) {
  final apply = args.contains('--apply');
  final check = args.contains('--check') || !apply;
  final requireChangelog = args.contains('--require-changelog');

  String? writeReleaseNotesPath;
  final notesIndex = args.indexOf('--write-release-notes');
  if (notesIndex != -1 && notesIndex + 1 < args.length) {
    writeReleaseNotesPath = args[notesIndex + 1];
  }

  return _Args(
    apply: apply,
    check: check,
    requireChangelog: requireChangelog,
    writeReleaseNotesPath: writeReleaseNotesPath,
  );
}

String _readPubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exitCode = 2;
    return '';
  }

  final lines = pubspec.readAsLinesSync();
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('version:')) {
      final value = trimmed.substring('version:'.length).trim();
      if (value.isEmpty) {
        stderr.writeln('pubspec.yaml version is empty');
        exitCode = 2;
        return '';
      }
      return value;
    }
  }

  stderr.writeln('pubspec.yaml version not found');
  exitCode = 2;
  return '';
}

({String versionName, int buildNumber}) _parseFlutterVersion(String version) {
  final parts = version.split('+');
  final versionName = parts.first.trim();
  final buildNumber = parts.length >= 2 ? int.tryParse(parts[1].trim()) ?? 1 : 1;
  return (versionName: versionName, buildNumber: buildNumber);
}

String _repoReleaseUrl(String tagName) {
  final repo = Platform.environment['GITHUB_REPOSITORY'];
  if (repo == null || repo.isEmpty) return '';
  return 'https://github.com/$repo/releases/tag/$tagName';
}

String _extractReleaseSectionFromChangelog(String versionName) {
  final changelog = File('CHANGELOG.md');
  if (!changelog.existsSync()) return '';

  final lines = changelog.readAsLinesSync();
  final header = '# 版本 $versionName';
  final startIndex = lines.indexWhere((l) => l.trim() == header || l.trim().startsWith('$header '));
  if (startIndex == -1) return '';

  final buffer = <String>[];
  for (int i = startIndex; i < lines.length; i++) {
    if (i != startIndex && lines[i].startsWith('# 版本 ')) break;
    buffer.add(lines[i]);
  }
  return buffer.join('\n').trim();
}

List<String> _extractSummaryBullets(String releaseSection, {int maxItems = 5}) {
  if (releaseSection.isEmpty) return const [];
  final lines = releaseSection.split('\n');
  final items = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('- ')) {
      items.add(trimmed.substring(2).trim());
      if (items.length >= maxItems) break;
    }
  }
  return items;
}

String _buildReadmeSummaryBlock({
  required String versionName,
  required String releaseUrl,
  required List<String> bullets,
}) {
  final b = StringBuffer();
  b.writeln('## 最新版本概览');
  b.writeln();
  b.writeln('<!-- RELEASE_SUMMARY_START -->');
  b.writeln('- 当前版本：$versionName');
  if (bullets.isNotEmpty) {
    for (final item in bullets) {
      b.writeln('- $item');
    }
  } else {
    b.writeln('- 本次更新详见 Release 页面');
  }
  if (releaseUrl.isNotEmpty) {
    b.writeln('- 完整更新：$releaseUrl');
  }
  b.writeln('<!-- RELEASE_SUMMARY_END -->');
  b.writeln();
  return b.toString();
}

String _upsertReadmeSummary({
  required String readmeContent,
  required String block,
}) {
  const start = '<!-- RELEASE_SUMMARY_START -->';
  const end = '<!-- RELEASE_SUMMARY_END -->';

  final startIndex = readmeContent.indexOf(start);
  final endIndex = readmeContent.indexOf(end);

  if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
    final before = readmeContent.substring(0, startIndex);
    final after = readmeContent.substring(endIndex + end.length);
    final innerStart = block.indexOf(start);
    final innerEnd = block.indexOf(end);
    final replacement = innerStart != -1 && innerEnd != -1 ? block.substring(innerStart, innerEnd + end.length) : block;
    return before + replacement + after;
  }

  final lines = readmeContent.split('\n');
  final insertAt = lines.indexWhere((l) => l.trim().startsWith('## 更新历史'));
  if (insertAt == -1) {
    return readmeContent.trimRight() + '\n\n' + block;
  }

  final out = <String>[];
  out.addAll(lines.take(insertAt));
  out.add('');
  out.addAll(block.trimRight().split('\n'));
  out.addAll(lines.skip(insertAt));
  return out.join('\n');
}

bool _ensureAndroidVersionConfig({
  required String versionName,
  required int buildNumber,
  required bool apply,
}) {
  final androidDir = Directory('android');
  if (!androidDir.existsSync()) return true;

  final targetExts = <String>{'.gradle', '.kts'};
  final files = androidDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => targetExts.any((ext) => f.path.endsWith(ext)))
      .toList();

  var ok = true;

  for (final file in files) {
    final original = file.readAsStringSync();
    var updated = original;

    updated = updated.replaceAllMapped(
      RegExp(r'versionName\s*=\s*"(\d+\.\d+\.\d+)"'),
      (_) => 'versionName = "$versionName"',
    );

    updated = updated.replaceAllMapped(
      RegExp(r'versionCode\s*=\s*(\d+)'),
      (_) => 'versionCode = $buildNumber',
    );

    if (apply && updated != original) {
      file.writeAsStringSync(updated);
    }

    final mismatchedVersionName = RegExp(r'versionName\s*=\s*"(\d+\.\d+\.\d+)"')
        .allMatches(updated)
        .any((m) => m.group(1) != versionName);
    final mismatchedVersionCode = RegExp(r'versionCode\s*=\s*(\d+)')
        .allMatches(updated)
        .any((m) => int.tryParse(m.group(1) ?? '') != buildNumber);

    if (mismatchedVersionName) {
      stderr.writeln('${file.path}: versionName mismatch, expect $versionName');
      ok = false;
    }

    if (mismatchedVersionCode) {
      stderr.writeln('${file.path}: versionCode mismatch, expect $buildNumber');
      ok = false;
    }
  }

  return ok;
}

void main(List<String> rawArgs) {
  final args = _parseArgs(rawArgs);

  final fullVersion = _readPubspecVersion();
  if (fullVersion.isEmpty) return;
  final parsed = _parseFlutterVersion(fullVersion);
  final versionName = parsed.versionName;
  final buildNumber = parsed.buildNumber;
  final tagName = 'v$versionName';

  final releaseUrl = _repoReleaseUrl(tagName);
  final releaseSection = _extractReleaseSectionFromChangelog(versionName);
  final bullets = _extractSummaryBullets(releaseSection);

  final androidOk = _ensureAndroidVersionConfig(
    versionName: versionName,
    buildNumber: buildNumber,
    apply: args.apply,
  );

  if (!androidOk) {
    exitCode = 1;
    return;
  }

  final readmeFile = File('README.md');
  if (!readmeFile.existsSync()) {
    stderr.writeln('README.md not found');
    exitCode = 2;
    return;
  }

  if (args.apply) {
    final block = _buildReadmeSummaryBlock(
      versionName: versionName,
      releaseUrl: releaseUrl,
      bullets: bullets,
    );
    final updated = _upsertReadmeSummary(
      readmeContent: readmeFile.readAsStringSync(),
      block: block,
    );
    if (updated != readmeFile.readAsStringSync()) {
      readmeFile.writeAsStringSync(updated);
    }
  }

  if (args.writeReleaseNotesPath != null) {
    final notes = releaseSection.isNotEmpty
        ? releaseSection + (releaseUrl.isNotEmpty ? '\n\n完整更新：$releaseUrl\n' : '\n')
        : (releaseUrl.isNotEmpty ? '本次更新详见：$releaseUrl\n' : '本次更新详见 Release 页面\n');
    File(args.writeReleaseNotesPath!).writeAsStringSync(notes);
  }

  if (args.check) {
    if (args.requireChangelog && releaseSection.isEmpty) {
      stderr.writeln('CHANGELOG.md missing section for version $versionName');
      exitCode = 1;
      return;
    }
  }
}
