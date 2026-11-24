# rivus-action

A GitHub Action that builds [rivus](https://github.com/yagihash/rivus) from a release tag and adds it to `PATH`.

rivus does not publish prebuilt binaries yet, so this action downloads the source of the given tag and builds it on the runner. Nothing is cached, so it does not use up the repository's cache quota.

## Usage

```yaml
jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false

      - uses: yagihash/rivus-action@v0.0.1
        with:
          version: v0.0.14 # omit to build the latest release

      - run: rivus analyze ./...
```

To analyze Dart, set up the Dart SDK first and enable `dart`:

```yaml
      - uses: dart-lang/setup-dart@v1

      - uses: yagihash/rivus-action@v0.0.1
        with:
          version: v0.0.14
          dart: true

      - run: rivus analyze -C path/to/dart/project
```

Pin the actions to a commit SHA in your own workflows.

## Inputs

| Name      | Required | Default | Description                                                                  |
|-----------|----------|---------|------------------------------------------------------------------------------|
| `version` | No       | `latest` | rivus release tag to build (e.g. `v0.0.14`). `latest` builds the newest release |
| `dart`    | No       | `false` | Also build the Dart extractor (`rivus-dart`). Requires the Dart SDK on `PATH` |

## Requirements

- Linux or macOS runner. Windows is not supported.
- Go on `PATH` (preinstalled on GitHub-hosted runners). `go.mod` of rivus pins the Go version, and Go 1.21 or later fetches that toolchain by itself. Run `actions/setup-go` first if you need to control it.
- Dart SDK on `PATH` when `dart: true`. The compiled extractor reads the SDK's `dart:*` sources at run time.
- Run `dart pub get` in the target project before analyzing Dart.

## Not supported

- **Rust.** The pinned nightly toolchain is about 1.1 GB, and the sandbox that isolates untrusted code is available on macOS only.

## Security

- `version` is validated against a release-tag pattern before it is used in a URL or a linker flag.
- `latest` is resolved at run time, so the same workflow can build different versions over time. Pin `version` when you need reproducible runs.
- The source is fetched from a git tag, which is not an immutable reference. The tag is not verified against a checksum.
