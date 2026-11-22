# CI integration

`app_updater` can serve builds that never reached a store or a GitHub release.
Two paths exist, and they can be combined:

| Path | Needs a server | Good for |
|---|---|---|
| **CI feed** (`CiFeedSource`) | yes, `app_updater_ci` | Instant delivery, private builds, several platforms |
| **GitHub Actions artifacts** (`GitHubArtifactsSource`) | no | Public or private repos already building on GitHub |

Both end in the same place: an `UpdateCandidate` with a version, notes and one
or more downloadable artifacts.

---

## 1. The CI feed

### Start the server

```bash
# Docker (image published by .github/workflows/release.yml)
docker run -d --name app-updater-ci \
  -p 8080:8080 \
  -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest

# Or from source
cd ci/app_updater_ci
dart pub get
dart run bin/server.dart --port 8080 --token change-me --data ./data
```

Options: `--host`, `--port`, `--data`, `--token`, `--private` (token required
for reads too), `--keep` (builds kept per app and channel, default 10, `0`
disables pruning).

The write token is mandatory. An empty token makes the server refuse to start,
because an open ingest endpoint lets anyone publish a build to your users.

### API

| Method | Route | Auth | Purpose |
|---|---|---|---|
| `POST` | `/v1/apps/{app}/builds` | write | Announce a build. Returns `{buildId, uploadUrl, awaitingUpload}`. |
| `PUT` | `/v1/apps/{app}/builds/{id}/artifact` | write | Upload the file (`x-file-name`, `x-sha256`). |
| `GET` | `/v1/apps/{app}/latest?platform=&channel=&abi=` | read | Manifest consumed by `CiFeedSource`. |
| `GET` | `/v1/apps/{app}/builds` | read | All builds, oldest first. |
| `GET` | `/v1/apps/{app}/builds/{id}/artifact` | read | The file (`x-checksum-sha256`). |
| `DELETE` | `/v1/apps/{app}/builds/{id}` | write | Remove a build and its file. |
| `GET` | `/healthz` | none | Liveness probe. |

`POST /builds` accepts:

```json
{
  "version": "1.4.2",
  "buildNumber": 168,
  "platform": "android",
  "channel": "stable",
  "abi": "arm64-v8a",
  "releaseNotes": "Fixed the player crash",
  "releaseUrl": "https://github.com/me/app/releases/tag/v1.4.2",
  "minimumVersion": "1.2.0",
  "urgency": "medium",
  "mandatory": false,
  "fileName": "app-arm64-v8a-release.apk",
  "url": "https://cdn.example.com/app.apk"
}
```

Send `url` to publish a link (S3, R2, a CDN) instead of uploading bytes. Send
`fileName` when you are about to `PUT` the file.

A build only appears in `/latest` once it has a file (or a `url`), so a failed
upload never reaches users.

### Publish from CI

The shell script needs `bash`, `curl`, `sha256sum` and `python3`:

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint "$APP_UPDATER_CI_ENDPOINT" \
  --token "$APP_UPDATER_CI_TOKEN" \
  --app my-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 \
  --build-number "$GITHUB_RUN_NUMBER" \
  --platform android \
  --abi arm64-v8a \
  --notes-file CHANGELOG.md \
  --write-manifest
```

Flags: `--channel`, `--notes`, `--notes-file`, `--build-number`,
`--minimum-version`, `--release-url`, `--urgency`, `--mandatory`, `--url`
(external artifact), `--write-manifest`, `--token`, `--endpoint`.

The Dart alternative is useful when Dart is already installed:

```bash
cd ci/app_updater_ci
dart run bin/publish.dart \
  --endpoint https://updates.example.com --app my-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 --platform android --abi arm64-v8a \
  --notes-file CHANGELOG.md --write-manifest
```

`--dry-run` validates the file and arguments without touching the network.

### Per-CI recipes

| CI | Copy |
|---|---|
| GitHub Actions | [`ci/examples/github-actions.yml`](../ci/examples/github-actions.yml) |
| GitLab CI | [`ci/examples/gitlab-ci.yml`](../ci/examples/gitlab-ci.yml) |
| CircleCI | [`ci/examples/circleci.yml`](../ci/examples/circleci.yml) |
| Jenkins | [`ci/examples/Jenkinsfile`](../ci/examples/Jenkinsfile) |

GitHub users can call the reusable workflow instead of writing steps:

```yaml
jobs:
  publish:
    uses: ferelking242/app_updater/.github/workflows/publish-app-updater.yml@main
    with:
      app_id: my-app
      build_command: flutter build apk --release --split-per-abi
      artifact_glob: build/app/outputs/flutter-apk/*.apk
    secrets:
      APP_UPDATER_CI_ENDPOINT: ${{ secrets.APP_UPDATER_CI_ENDPOINT }}
      APP_UPDATER_CI_TOKEN: ${{ secrets.APP_UPDATER_CI_TOKEN }}
```

### Consume the feed

```dart
final controller = AppUpdateController(
  source: CiFeedSource(
    endpoint: Uri.parse('https://updates.example.com'),
    appId: 'my-app',
    channel: 'stable',
  ),
  notifier: myNotifier,
  installer: myInstaller,
  options: const AutoUpdateOptions(enabledByDefault: true, abi: 'arm64-v8a'),
);
```

`CiFeedSource` also accepts `token` (private servers) and `headers`.

---

## 2. GitHub Actions artifacts

No server, no release. The workflow builds the app, writes `app-update.json`,
and uploads both as an artifact.

```yaml
- name: Build
  run: flutter build apk --release --split-per-abi

- name: Write manifest
  run: |
    VERSION="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml | head -n1)"
    for FILE in build/app/outputs/flutter-apk/*.apk; do
      ./publish-build.sh --app my-app --file "$FILE" --version "$VERSION" --write-manifest
    done

- uses: actions/upload-artifact@v4
  with:
    name: my-app-android
    path: |
      build/app/outputs/flutter-apk/*.apk
      build/app/outputs/flutter-apk/app-update.json
```

```dart
GitHubArtifactsSource(
  owner: 'my-org',
  repo: 'my-app',
  workflow: 'publish.yml',   // file name, workflow name or numeric id
  branch: 'main',
  token: Platform.environment['GH_TOKEN'], // private repositories
)
```

Version resolution order: `app-update.json` inside the archive (read after
download), then the artifact name (`my-app-android-arm64-1.4.2`), then the run
title, then the branch. A run without any version is skipped; pass
`versionResolver` if your naming cannot carry one.

Artifacts expire (90 days by default). Expired artifacts are ignored.

---

## 3. Releases

Releases are the stable channel and the long-term archive:

```bash
git tag v1.4.2
git push origin v1.4.2
```

On the `app_updater` repository, `.github/workflows/release.yml` then:

1. runs `flutter analyze`, `flutter test` and `dart pub publish --dry-run`,
2. packages `app_updater-<version>.tar.gz`,
3. creates the GitHub release with generated notes,
4. builds and pushes `ghcr.io/<owner>/app-updater-ci:<tag>`.

For an application repository, attach the build to the release and let
`GitHubReleasesSource` (or `--release-url` on the CI feed) point users to it.

---

## 4. Combining sources

```dart
CompositeUpdateSource([
  CiFeedSource(endpoint: ..., appId: 'my-app'),          // newest builds
  GitHubArtifactsSource(owner: 'me', repo: 'my-app'),    // fallback, no server
  GitHubReleasesSource(owner: 'me', repo: 'my-app'),     // stable channel
]);
```

The newest version wins. A source that throws is ignored, so one outage does
not hide the others.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `401 unauthorized` on publish | Missing or wrong `APP_UPDATER_CI_TOKEN` | Check the token used by CI and by the server. |
| `/latest` returns 404 | No build with a file for this platform/channel | Check `--platform`, `--channel`, and that the `PUT` succeeded. |
| `SHA-256 mismatch` | File changed between hashing and upload | Re-run the publish step. |
| App never sees the build | Client channel or ABI filter | `channel: 'stable'` is the default; ABI-less builds match every device. |
| GitHub source returns nothing | Workflow name mismatch or expired artifacts | Use the workflow file name, check the run status. |
| `413` on upload | Reverse proxy body limit | Raise `client_max_body_size` (nginx) or equivalent. |
