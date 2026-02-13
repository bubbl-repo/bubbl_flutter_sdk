# Bubbl Flutter SDK Internal Release Guide (pub.dev)

This document defines how to release `bubbl_flutter_sdk` to pub.dev.

## Scope

- Package root: `/Users/jackwright/Projects/bubbl-current/sdk/bubbl_flutter_sdk`
- Public package name: `bubbl_flutter_sdk`
- Hosted registry: `https://pub.dev`

## One-time setup (per machine)

1. Install Flutter/Dart and verify:

```bash
flutter --version
dart --version
```

2. Log in to pub.dev:

```bash
dart pub login
```

The command opens an OAuth flow in the browser and stores credentials locally.

## Release checklist

1. Update release metadata:
- Bump `version` in `pubspec.yaml` (semantic versioning).
- Add release notes in `CHANGELOG.md` with the same version.

2. Run quality gates:

```bash
cd /Users/jackwright/Projects/bubbl-current/sdk/bubbl_flutter_sdk
flutter pub get
flutter analyze
flutter test
flutter pub publish --dry-run
```

3. Confirm publish payload:
- Ensure internal-only files are excluded.
- `.pubignore` currently excludes `internal.md`.

4. Publish:

```bash
cd /Users/jackwright/Projects/bubbl-current/sdk/bubbl_flutter_sdk
flutter pub publish --force
```

5. Verify release:
- Check package page: `https://pub.dev/packages/bubbl_flutter_sdk`.
- Confirm the new version appears under the Versions tab.

6. Tag source control for traceability:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

## Customer install snippet after publish

```yaml
dependencies:
  bubbl_flutter_sdk: ^X.Y.Z
```

## Hotfix release process

1. Branch from the release commit or `main`.
2. Apply fix and bump patch version (`X.Y.Z+1`).
3. Update `CHANGELOG.md`.
4. Re-run the checklist and publish again.

## Notes

- pub.dev packages are public.
- Unpublishing is restricted by pub.dev policy, so verify dry-run output carefully before publish.
