#!/usr/bin/env bash
# Install a prebuilt rivus from a GitHub Release, verify it, and add it to PATH.
# Expects: VERSION (tag such as v0.0.14, or "latest"), WITH_DART ("true" to build rivus-dart),
#          GH_TOKEN (for gh attestation verify), RUNNER_TEMP and GITHUB_PATH (set by the runner).
set -euo pipefail

: "${RUNNER_TEMP:?}"
: "${GITHUB_PATH:?}"
VERSION="${VERSION:-latest}"
WITH_DART="${WITH_DART:-false}"

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

if [[ "$WITH_DART" == "true" ]]; then
  # The Dart extractor is not part of the release. Build it from the source of the tag.
  # rivus-dart reads the dart:* sources of the Dart SDK at run time and finds the SDK from `dart` on PATH.
  src="${root}/src"
  mkdir -p "$src"
  echo "::group::Build rivus-dart"
  curl -fsSL --retry 3 "https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz" |
    tar -xz -C "$src" --strip-components=1
  (
    cd "${src}/extractor/dart"
    dart pub get --enforce-lockfile
    dart compile exe bin/rivus_dart.dart -o "${bin}/rivus-dart"
  )
  echo "::endgroup::"
fi

echo "$bin" >> "$GITHUB_PATH"
PATH="${bin}:${PATH}" rivus version
