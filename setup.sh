#!/usr/bin/env bash
# Build rivus (and optionally the Dart extractor) from a release tag and add it to PATH.
# Expects: VERSION (tag such as v0.0.14, or "latest"), WITH_DART ("true" to build rivus-dart),
#          RUNNER_TEMP and GITHUB_PATH (set by the runner).
set -euo pipefail

: "${RUNNER_TEMP:?}"
: "${GITHUB_PATH:?}"
VERSION="${VERSION:-latest}"
WITH_DART="${WITH_DART:-false}"

die() {
  echo "::error::$*"
  exit 1
}

if [[ "$VERSION" == "latest" ]]; then
  # The redirect target of /releases/latest is the newest release tag. Unlike the API, it needs no token and has no rate limit.
  latest_url="$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/yagihash/rivus/releases/latest")"
  VERSION="${latest_url##*/}"
  echo "Resolved latest to ${VERSION}"
fi

# VERSION goes into a URL and a linker flag; accept only a plain release tag.
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
  die "Input 'version' must be 'latest' or a release tag such as v0.0.14 (got '${VERSION}')."

case "$(uname -s)" in
  Linux | Darwin) ;;
  *) die "Unsupported OS '$(uname -s)'. Only Linux and macOS runners are supported." ;;
esac

command -v go > /dev/null ||
  die "'go' was not found on PATH. Use a runner with Go or run actions/setup-go before this action."
case "$WITH_DART" in
  true)
    command -v dart > /dev/null ||
      die "'dart' was not found on PATH. Run dart-lang/setup-dart before this action, or set 'dart: false'."
    ;;
  false) ;;
  *) die "Input 'dart' must be 'true' or 'false' (got '${WITH_DART}')." ;;
esac

root="${RUNNER_TEMP}/rivus-action/${VERSION}"
src="${root}/src"
bin="${root}/bin"
rm -rf "$root"
mkdir -p "$src" "$bin"

echo "::group::Download rivus ${VERSION}"
curl -fsSL --retry 3 "https://github.com/yagihash/rivus/archive/refs/tags/${VERSION}.tar.gz" |
  tar -xz -C "$src" --strip-components=1
echo "::endgroup::"

# go.mod pins the Go version; with Go 1.21+ the go command fetches that toolchain on its own (GOTOOLCHAIN=auto).
echo "::group::Build rivus"
(cd "$src" && go build -trimpath -ldflags "-s -w -X main.versionStamp=${VERSION#v}" -o "${bin}/rivus" ./cmd/rivus)
echo "::endgroup::"

if [[ "$WITH_DART" == "true" ]]; then
  # rivus-dart reads the dart:* sources of the Dart SDK at run time and finds the SDK from `dart` on PATH.
  echo "::group::Build rivus-dart"
  (
    cd "${src}/extractor/dart"
    dart pub get --enforce-lockfile
    dart compile exe bin/rivus_dart.dart -o "${bin}/rivus-dart"
  )
  echo "::endgroup::"
fi

echo "$bin" >> "$GITHUB_PATH"
PATH="${bin}:${PATH}" rivus version
