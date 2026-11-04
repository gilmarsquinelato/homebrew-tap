#!/bin/sh
# Install the Nscale CLI on macOS or Linux.
#
#   curl -fsSL https://docs.nscale.com/cli/install.sh | sh
#   curl -fsSL https://docs.nscale.com/cli/install.sh | sh -s -- -v 6.2.0 -b ~/.local/bin
#
# Options:
#   -v VERSION  Version to install, for example 7.0.0 or v7.0.0 (default: latest).
#   -b DIR      Directory to install nscale into (default: /usr/local/bin if
#               writable, otherwise ~/.local/bin).
#   -h          Show this help.
#
# NSCALE_VERSION and NSCALE_INSTALL_DIR are read when -v and -b are not given.

set -eu

REPO="nscaledev/homebrew-tap"
BINARY="nscale"

usage() {
	cat <<'EOF'
Install the Nscale CLI.

Usage: install.sh [-v VERSION] [-b DIR]

  -v VERSION  Version to install, for example 7.0.0 or v7.0.0 (default: latest)
  -b DIR      Directory to install nscale into (default: /usr/local/bin if
              writable, otherwise ~/.local/bin)
  -h          Show this help

NSCALE_VERSION and NSCALE_INSTALL_DIR are read when -v and -b are not given.
EOF
}

log() {
	printf '%s\n' "$*" >&2
}

fail() {
	log "Error: $*"
	exit 1
}

has() {
	command -v "$1" >/dev/null 2>&1
}

# download URL FILE
download() {
	if has curl; then
		curl -fsSL -o "$2" "$1"
	elif has wget; then
		wget -q -O "$2" "$1"
	else
		fail "curl or wget is required"
	fi
}

# Print the tag the "latest release" page redirects to, for example v7.0.0.
# Following the redirect avoids the GitHub API and its rate limit.
latest_tag() {
	url="https://github.com/${REPO}/releases/latest"
	if has curl; then
		effective=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$url")
	else
		effective=$(wget -q -S --spider "$url" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r')
	fi
	tag=${effective##*/}
	case "$tag" in
	v[0-9]*) printf '%s\n' "$tag" ;;
	*) fail "could not determine the latest version from ${url}" ;;
	esac
}

sha256() {
	if has sha256sum; then
		sha256sum "$1" | cut -d ' ' -f 1
	elif has shasum; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
	elif has openssl; then
		openssl dgst -sha256 "$1" | sed 's/^.*= *//'
	else
		fail "sha256sum, shasum or openssl is required to verify the download"
	fi
}

detect_os() {
	case "$(uname -s)" in
	Darwin) echo Darwin ;;
	Linux) echo Linux ;;
	MINGW* | MSYS* | CYGWIN*) fail "on Windows, use install.ps1: irm https://docs.nscale.com/cli/install.ps1 | iex" ;;
	*) fail "unsupported operating system: $(uname -s)" ;;
	esac
}

detect_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) echo x86_64 ;;
	arm64 | aarch64) echo arm64 ;;
	i386 | i686) echo i386 ;;
	*) fail "unsupported architecture: $(uname -m)" ;;
	esac
}

version=${NSCALE_VERSION:-}
install_dir=${NSCALE_INSTALL_DIR:-}

while getopts "v:b:h" opt; do
	case "$opt" in
	v) version=$OPTARG ;;
	b) install_dir=$OPTARG ;;
	h)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

has curl || has wget || fail "curl or wget is required"

os=$(detect_os)
arch=$(detect_arch)

if [ "$os" = Darwin ] && [ "$arch" = i386 ]; then
	fail "32-bit macOS is not supported"
fi

if [ -z "$version" ] || [ "$version" = latest ]; then
	tag=$(latest_tag)
else
	tag="v${version#v}"
fi
plain=${tag#v}

archive="nscale-cli_${os}_${arch}.tar.gz"
base="https://github.com/${REPO}/releases/download/${tag}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

log "Installing nscale ${tag} (${os} ${arch})"

download "${base}/${archive}" "${tmp}/${archive}" ||
	fail "could not download ${base}/${archive}. Check that version ${plain} exists: https://github.com/${REPO}/releases"
download "${base}/nscale-cli-${plain}-checksums.txt" "${tmp}/checksums.txt" ||
	fail "could not download the checksums for ${tag}"

expected=$(awk -v f="$archive" '$2 == f { print $1 }' "${tmp}/checksums.txt")
[ -n "$expected" ] || fail "no checksum listed for ${archive}"
actual=$(sha256 "${tmp}/${archive}")
[ "$expected" = "$actual" ] || fail "checksum mismatch for ${archive}: expected ${expected}, got ${actual}"

tar -xzf "${tmp}/${archive}" -C "$tmp" "$BINARY"

if [ -z "$install_dir" ]; then
	if [ -w /usr/local/bin ]; then
		install_dir=/usr/local/bin
	else
		install_dir="${HOME}/.local/bin"
	fi
fi
# Expand a leading ~ that the shell left alone, as in -b "~/bin".
# shellcheck disable=SC2088
case "$install_dir" in
"~") install_dir=$HOME ;;
"~/"*) install_dir="${HOME}/${install_dir#"~/"}" ;;
esac

mkdir -p "$install_dir" || fail "could not create ${install_dir}"
if ! install -m 0755 "${tmp}/${BINARY}" "${install_dir}/${BINARY}" 2>/dev/null; then
	fail "could not write to ${install_dir}. Pass a writable directory with -b, or rerun with sudo"
fi

log "Installed ${install_dir}/${BINARY}"

case ":${PATH}:" in
*":${install_dir}:"*) ;;
*) log "Add ${install_dir} to your PATH to run nscale, for example: export PATH=\"${install_dir}:\$PATH\"" ;;
esac
