2026-04-18T10:40:07.8332289Z ##[group]Run set -euo pipefail
2026-04-18T10:40:07.8332639Z [36;1mset -euo pipefail[0m
2026-04-18T10:40:07.8332909Z [36;1mgit fetch origin main[0m
2026-04-18T10:40:07.8333169Z [36;1mgit checkout main[0m
2026-04-18T10:40:07.8333511Z [36;1mdart run tool/release/release_prepare.dart --apply --check[0m
2026-04-18T10:40:07.8333899Z [36;1mif ! git diff --quiet; then[0m
2026-04-18T10:40:07.8334229Z [36;1m  git config user.name "github-actions[bot]"[0m
2026-04-18T10:40:07.8334676Z [36;1m  git config user.email "github-actions[bot]@users.noreply.github.com"[0m
2026-04-18T10:40:07.8335216Z [36;1m  git add README.md android/app/build.gradle.kts || true[0m
2026-04-18T10:40:07.8335693Z [36;1m  git commit -m "docs: update release summary for $GITHUB_REF_NAME" || true[0m
2026-04-18T10:40:07.8336123Z [36;1m  git push origin HEAD:main[0m
2026-04-18T10:40:07.8337032Z [36;1mfi[0m
2026-04-18T10:40:07.8337450Z [36;1mgit checkout "$GITHUB_REF_NAME"[0m
2026-04-18T10:40:07.8358980Z shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}
2026-04-18T10:40:07.8359366Z env:
2026-04-18T10:40:07.8359590Z   FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
2026-04-18T10:40:07.8360001Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.18-8/x64
2026-04-18T10:40:07.8360547Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.18-8/x64
2026-04-18T10:40:07.8361054Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.41.7-x64/flutter
2026-04-18T10:40:07.8361445Z   PUB_CACHE: /home/runner/.pub-cache
2026-04-18T10:40:07.8361716Z ##[endgroup]
2026-04-18T10:40:08.2916941Z From https://github.com/whmdg20090421/vault_app
2026-04-18T10:40:08.2922323Z  * branch            main       -> FETCH_HEAD
2026-04-18T10:40:08.5146754Z Previous HEAD position was de86d8d chore(release): bump version to 1.4.2+20 and update changelog
2026-04-18T10:40:08.5160334Z Switched to a new branch 'main'
2026-04-18T10:40:08.5163165Z M	pubspec.lock
2026-04-18T10:40:08.5163648Z branch 'main' set up to track 'origin/main'.
2026-04-18T10:40:08.9746281Z Running build hooks...Running build hooks...On branch main
2026-04-18T10:40:08.9752595Z Your branch is up to date with 'origin/main'.
2026-04-18T10:40:08.9767016Z 
2026-04-18T10:40:08.9777657Z Changes not staged for commit:
2026-04-18T10:40:08.9797119Z   (use "git add <file>..." to update what will be committed)
2026-04-18T10:40:08.9807390Z   (use "git restore <file>..." to discard changes in working directory)
2026-04-18T10:40:08.9857233Z 	modified:   pubspec.lock
2026-04-18T10:40:08.9857748Z 
2026-04-18T10:40:08.9858149Z Untracked files:
2026-04-18T10:40:08.9858881Z   (use "git add <file>..." to include in what will be committed)
2026-04-18T10:40:08.9859689Z 	release_notes.md
2026-04-18T10:40:08.9860094Z 
2026-04-18T10:40:08.9860590Z no changes added to commit (use "git add" and/or "git commit -a")
2026-04-18T10:40:09.3094761Z Everything up-to-date
2026-04-18T10:40:09.3522341Z Note: switching to 'v1.4.2'.
2026-04-18T10:40:09.3529969Z 
2026-04-18T10:40:09.3530196Z M	pubspec.lock
2026-04-18T10:40:09.3531201Z You are in 'detached HEAD' state. You can look around, make experimental
2026-04-18T10:40:09.3532379Z changes and commit them, and you can discard any commits you make in this
2026-04-18T10:40:09.3533499Z state without impacting any branches by switching back to a branch.
2026-04-18T10:40:09.3534234Z 
2026-04-18T10:40:09.3534794Z If you want to create a new branch to retain commits you create, you may
2026-04-18T10:40:09.3535828Z do so (now or later) by using -c with the switch command. Example:
2026-04-18T10:40:09.3536757Z 
2026-04-18T10:40:09.3537160Z   git switch -c <new-branch-name>
2026-04-18T10:40:09.3537702Z 
2026-04-18T10:40:09.3538239Z Or undo this operation with:
2026-04-18T10:40:09.3538764Z 
2026-04-18T10:40:09.3539095Z   git switch -
2026-04-18T10:40:09.3539625Z 
2026-04-18T10:40:09.3540226Z Turn off this advice by setting config variable advice.detachedHead to false
2026-04-18T10:40:09.3541003Z 
2026-04-18T10:40:09.3541881Z HEAD is now at de86d8d chore(release): bump version to 1.4.2+20 and update changelog
