#!/usr/bin/env bash
# Install a prebuilt rivus from a GitHub Release, verify it, and add it to PATH.
# Expects: VERSION (tag such as v0.0.14, or "latest"), WITH_DART ("true" to build rivus-dart),
#          WITH_RUST ("true" to set up the Rust extractor), GH_TOKEN (for gh attestation verify), RUNNER_TEMP and GITHUB_PATH (set by the runner).
set -euo pipefail

: "${RUNNER_TEMP:?}"
: "${GITHUB_PATH:?}"
VERSION="${VERSION:-latest}"
WITH_DART="${WITH_DART:-false}"
WITH_RUST="${WITH_RUST:-false}"

REPO="yagihash/rivus"
# The workflow that builds and attests the release archives.
SIGNER_WORKFLOW="yagihash/rivus/.github/workflows/tagpr.yml"

die() {
  echo "::endgroup::" # close a group that is still open (a stray endgroup is ignored)
  echo "::error::$*"
  exit 1
}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

if [[ "$VERSION" == "latest" ]]; then
  # The redirect target of /releases/latest is the newest release tag. Unlike the API, it needs no token and has no rate limit.
  latest_url="$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  VERSION="${latest_url##*/}"
  echo "Resolved latest to ${VERSION}"
fi

# VERSION goes into a URL, a file name and a linker flag; accept only a plain release tag.
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
  die "Input 'version' must be 'latest' or a release tag such as v0.0.14 (got '${VERSION}')."
ver="${VERSION#v}"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target="linux_amd64" ;;
  Linux/aarch64 | Linux/arm64) target="linux_arm64" ;;
  Darwin/arm64) target="darwin_arm64" ;;
  *) die "Unsupported platform '$(uname -s)/$(uname -m)'. Supported: Linux (x86-64, arm64) and macOS (arm64)." ;;
esac

command -v gh > /dev/null ||
  die "'gh' was not found on PATH. It is needed to verify the attestations. GitHub-hosted runners have it."
case "$WITH_DART" in
  true)
    command -v dart > /dev/null ||
      die "'dart' was not found on PATH. Run dart-lang/setup-dart before this action, or set 'dart: false'."
    ;;
  false) ;;
  *) die "Input 'dart' must be 'true' or 'false' (got '${WITH_DART}')." ;;
esac
case "$WITH_RUST" in
  true)
    command -v rustup > /dev/null ||
      die "'rustup' was not found on PATH. GitHub-hosted runners have it; install it on other runners, or set 'rust: false'."
    ;;
  false) ;;
  *) die "Input 'rust' must be 'true' or 'false' (got '${WITH_RUST}')." ;;
esac

root="${RUNNER_TEMP}/rivus-action/${VERSION}"
dl="${root}/download"
pkg="${root}/pkg"
bin="${root}/bin"
rm -rf "$root"
mkdir -p "$dl" "$pkg" "$bin"

asset="rivus_${ver}_${target}.tar.gz"
checksums="rivus_${ver}_checksums.txt"
base="https://github.com/${REPO}/releases/download/${VERSION}"

echo "::group::Download ${asset}"
for f in "$asset" "$checksums"; do
  curl -fsSL --retry 3 -o "${dl}/${f}" "${base}/${f}" ||
    die "Could not download ${f} from the release ${VERSION}. Releases before the one that first shipped binaries have no assets."
done
echo "::endgroup::"

echo "::group::Verify ${asset}"
# 1. The archive is the one the release lists.
expected="$(awk -v a="$asset" '$2 == a || $2 == "./" a { print $1 }' "${dl}/${checksums}")"
[[ -n "$expected" ]] || die "${checksums} has no entry for ${asset}."
actual="$(sha256 "${dl}/${asset}")"
[[ "$actual" == "$expected" ]] || die "Checksum mismatch for ${asset}: expected ${expected}, got ${actual}."
echo "checksum ok: ${actual}"
# 2. The archive was built from ${REPO} by the release workflow (build provenance).
(cd "$dl" && gh attestation verify "$asset" --repo "$REPO" --signer-workflow "$SIGNER_WORKFLOW" --deny-self-hosted-runners) ||
  die "Build provenance verification failed for ${asset}."
# 3. The archive is an asset of the published (immutable) release ${VERSION}.
(cd "$dl" && gh release verify-asset "$VERSION" "$asset" --repo "$REPO") ||
  die "Release attestation verification failed for ${asset}."
echo "::endgroup::"

tar -xzf "${dl}/${asset}" -C "$pkg" --strip-components=1
install -m 0755 "${pkg}/rivus" "${bin}/rivus"

# The extractors are not part of the release. They are built from the source of the tag.
src="${root}/src"
if [[ "$WITH_DART" == "true" || "$WITH_RUST" == "true" ]]; then
  mkdir -p "$src"
  echo "::group::Download the source of rivus ${VERSION}"
  curl -fsSL --retry 3 "https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz" |
    tar -xz -C "$src" --strip-components=1
  echo "::endgroup::"
fi

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

if [[ "$WITH_RUST" == "true" ]]; then
  # The extractor is built with the nightly that the tag pins (extractor/rust/rust-toolchain.toml), about 1.1 GB.
  # Nothing is cached: that would use up the cache quota of the repository.
  echo "::group::Set up the Rust extractor"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # `rivus setup rust` installs the toolchain with rustup and builds the extractor into the data directory of rivus,
    # where rivus finds it. It handles the SDK of macOS.
    PATH="${bin}:${PATH}" rivus setup rust -source "${src}/extractor/rust" -y
  else
    # `rivus setup rust` is for macOS (the sandbox). On Linux there is no isolation: the toolchain and the extractor are
    # prepared here, and a trusted project is read with `rivus analyze -lang rust -unsafe-host-exec`.
    channel="$(sed -nE 's/^channel[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "${src}/extractor/rust/rust-toolchain.toml")"
    [[ "$channel" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
      die "extractor/rust/rust-toolchain.toml has no 'channel = \"nightly-YYYY-MM-DD\"' (got '${channel}')."
    rustup toolchain install "$channel" --profile minimal -c rustc-dev -c llvm-tools -c rust-src --no-self-update
    CARGO_TARGET_DIR="${root}/rust-target" cargo "+${channel}" install --path "${src}/extractor/rust" --locked --root "${root}/rust-ext"
    install -m 0755 "${root}/rust-ext/bin/rivus-rust" "${bin}/rivus-rust"
    # rivus looks for the toolchain in ~/.rustup; say where it is, in case RUSTUP_HOME is elsewhere.
    echo "RIVUS_RUST_TOOLCHAIN_DIR=$(rustup run "$channel" rustc --print sysroot)" >> "${GITHUB_ENV:?}"
  fi
  echo "::endgroup::"
fi

echo "$bin" >> "$GITHUB_PATH"
PATH="${bin}:${PATH}" rivus version
