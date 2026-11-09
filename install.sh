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
#
# A downloader killed by a signal, as by Ctrl-C, ends the script with its status.
# Some shells run the caller's `|| fail` before the INT trap, which would blame
# the version for the interruption.
download() {
	status=0
	if has curl; then
		curl -fsSL -o "$2" "$1" || status=$?
	else
		wget -q -O "$2" "$1" || status=$?
	fi
	[ "$status" -le 128 ] || exit "$status"
	return "$status"
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

# detect_arch OS
#
# uname -m reports the architecture of the current process, not the machine,
# so check the machine where the two can differ.
detect_arch() {
	machine=$(uname -m)

	# A shell running under Rosetta on Apple silicon reports x86_64.
	if [ "$1" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
		machine=arm64
	fi

	case "$machine" in
	x86_64 | amd64) arch=x86_64 ;;
	arm64 | aarch64) arch=arm64 ;;
	i386 | i686) arch=i386 ;;
	*) fail "unsupported architecture: ${machine}" ;;
	esac

	# A 64-bit kernel can run a 32-bit userland, for example Raspberry Pi OS.
	if [ "$1" = Linux ] && [ "$(getconf LONG_BIT 2>/dev/null)" = 32 ]; then
		case "$arch" in
		x86_64) arch=i386 ;;
		arm64) fail "32-bit ARM is not supported" ;;
		esac
	fi

	echo "$arch"
}

# Print where TARGET resolves if it is a Homebrew-managed link, which points into
# a Cellar. Print nothing otherwise.
homebrew_link() {
	[ -L "$1" ] || return 0
	link=$(readlink "$1")
	case "$link" in
	*/Cellar/*) printf '%s\n' "$link" ;;
	esac
}

# The whole install runs from main, called on the last line, so a download of
# this script cut off by a dropped connection runs nothing.
main() {
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
	shift $((OPTIND - 1))
	if [ "$#" -gt 0 ]; then
		log "Error: unexpected argument: $1 (use -v to pick a version)"
		usage >&2
		exit 2
	fi

	has curl || has wget || fail "curl or wget is required"

	os=$(detect_os)
	arch=$(detect_arch "$os")

	if [ "$os" = Darwin ] && [ "$arch" = i386 ]; then
		fail "32-bit macOS is not supported"
	fi

	if [ -z "$version" ] || [ "$version" = latest ]; then
		tag=$(latest_tag)
	else
		tag="v${version#v}"
	fi
	plain=${tag#v}

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
	# Drop a trailing slash so the PATH check below matches, but keep /.
	case "$install_dir" in
	?*/) install_dir=${install_dir%/} ;;
	esac
	target="${install_dir}/${BINARY}"

	# On Intel Macs /usr/local/bin is Homebrew's prefix. Replacing its link with a
	# standalone copy would break brew upgrade, so leave it to Homebrew.
	brew_link=$(homebrew_link "$target")
	if [ -n "$brew_link" ]; then
		fail "${target} is managed by Homebrew (${brew_link}). Run 'brew upgrade nscale' instead, or pass -b to install somewhere else"
	fi

	archive="nscale-cli_${os}_${arch}.tar.gz"
	base="https://github.com/${REPO}/releases/download/${tag}"

	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	trap 'rm -rf "$tmp"; exit 130' INT TERM

	log "Installing nscale ${tag} (${os} ${arch})"

	download "${base}/${archive}" "${tmp}/${archive}" ||
		fail "could not download ${base}/${archive} (see the error above). If the version is wrong, the available versions are at https://github.com/${REPO}/releases"
	download "${base}/nscale-cli-${plain}-checksums.txt" "${tmp}/checksums.txt" ||
		fail "could not download the checksums for ${tag} (see the error above)"

	expected=$(awk -v f="$archive" '$2 == f { print $1 }' "${tmp}/checksums.txt")
	[ -n "$expected" ] || fail "no checksum listed for ${archive}"
	actual=$(sha256 "${tmp}/${archive}")
	[ "$expected" = "$actual" ] || fail "checksum mismatch for ${archive}: expected ${expected}, got ${actual}"

	tar -xzf "${tmp}/${archive}" -C "$tmp" "$BINARY"

	mkdir -p "$install_dir" || fail "could not create ${install_dir} (see the error above)"
	install -m 0755 "${tmp}/${BINARY}" "$target" ||
		fail "could not install to ${target} (see the error above). If it's a permissions problem, pass a writable directory with -b, or run the installer with sudo"

	log "Installed ${target}"

	case ":${PATH}:" in
	*":${install_dir}:"*)
		found=$(command -v "$BINARY" 2>/dev/null || true)
		if [ -n "$found" ] && [ "$found" != "$target" ]; then
			log "Note: ${found} comes first on your PATH, so 'nscale' still runs that copy"
		fi
		;;
	*) log "Add ${install_dir} to your PATH to run nscale, for example: export PATH=\"${install_dir}:\$PATH\"" ;;
	esac
}

main "$@"
