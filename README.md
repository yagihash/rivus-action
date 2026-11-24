# rivus-action

A GitHub Action that installs [rivus](https://github.com/yagihash/rivus) from a GitHub Release and adds it to `PATH`.

The action downloads the prebuilt archive for the runner (Linux x86-64 / arm64, macOS arm64), verifies it, and puts `rivus` on `PATH`. Nothing is built or cached, so it does not use up the repository's cache quota.

## Usage

```yaml
permissions:
  contents: read
  attestations: read # to verify the attestations of the release

jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false

      - uses: yagihash/rivus-action@v0.0.1
        with:
          version: v0.0.15 # omit to install the latest release

      - run: rivus analyze ./...
```

To analyze Dart, set up the Dart SDK first and enable `dart`:

```yaml
      - uses: dart-lang/setup-dart@v1

      - uses: yagihash/rivus-action@v0.0.1
        with:
          version: v0.0.15
          dart: true

      - run: rivus analyze -C path/to/dart/project
```

Pin the actions to a commit SHA in your own workflows.

## Inputs

| Name      | Required | Default               | Description                                                                          |
|-----------|----------|-----------------------|--------------------------------------------------------------------------------------|
| `version` | No       | `latest`              | rivus release tag to install (e.g. `v0.0.15`). `latest` installs the newest release  |
| `dart`    | No       | `false`               | Also build the Dart extractor (`rivus-dart`). Requires the Dart SDK on `PATH`        |
| `token`   | No       | `${{ github.token }}` | Token for `gh attestation verify`                                                    |

## Requirements

- Linux (x86-64, arm64) or macOS (arm64) runner. Windows and Intel macOS are not supported.
- `gh` on `PATH` (preinstalled on GitHub-hosted runners), to verify the attestations.
- A release that ships binaries. Releases before the one that first shipped them have no assets, and the action fails on them.
- Go on `PATH` to analyze Go code: rivus runs `go list` at run time. Run `actions/setup-go` first (macOS runners do not ship Go). Installing rivus itself needs no Go.
- Dart SDK on `PATH` when `dart: true`. The extractor is built from the source of the tag, and the compiled extractor reads the SDK's `dart:*` sources at run time.
- Run `dart pub get` in the target project before analyzing Dart.

## Not supported

- **Rust.** The pinned nightly toolchain is about 1.1 GB, and the sandbox that isolates untrusted code is available on macOS only.

## Security

The action verifies the archive before it is used. Any failure stops the step.

1. **Checksum**: the SHA-256 of the archive matches `rivus_<version>_checksums.txt` of the release.
2. **Build provenance**: `gh attestation verify` checks that the archive was built by `yagihash/rivus/.github/workflows/tagpr.yml` on a GitHub-hosted runner.
3. **Release attestation**: `gh release verify-asset` checks that the archive is an asset of the published (immutable) release of that tag.

Other points:

- `version` is validated against a release-tag pattern before it is used in a URL or a file name.
- `latest` is resolved at run time, so the same workflow can install different versions over time. Pin `version` when you need reproducible runs.
- With `dart: true`, the Dart extractor is built from the source of the tag, which is not verified against a checksum.
