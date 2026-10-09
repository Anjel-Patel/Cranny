#!/bin/bash
# Installs or updates Cranny from its latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Anjel-Patel/Cranny/main/install.sh | bash
#
# What it does: checks your macOS version, downloads Cranny.zip and its published SHA-256
# checksum, verifies them, quits any running copy, installs Cranny.app into /Applications
# (or ~/Applications if /Applications isn't writable) and opens it.
set -euo pipefail

REPO="Anjel-Patel/Cranny"
DOWNLOADS="https://github.com/$REPO/releases/latest/download"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Everything runs inside main, so a partially downloaded script never runs.
main() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "Cranny is a macOS app."
  local macos
  macos="$(sw_vers -productVersion)"
  (( ${macos%%.*} >= 14 )) || fail "Cranny needs macOS 14 Sonoma or later (this Mac has $macos)."

  # Update an existing copy in place; otherwise prefer /Applications.
  local dest
  if [[ -d "/Applications/Cranny.app" ]]; then
    dest="/Applications"
  elif [[ -d "$HOME/Applications/Cranny.app" ]]; then
    dest="$HOME/Applications"
  elif [[ -w "/Applications" ]]; then
    dest="/Applications"
  else
    dest="$HOME/Applications"
    mkdir -p "$dest"
  fi
  [[ -w "$dest" ]] || fail "This account can't change $dest. Run the command from an administrator account."

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  say "Downloading the latest Cranny release"
  curl -fsSL "$DOWNLOADS/Cranny.zip" -o "$tmp/Cranny.zip" || fail "Couldn't download Cranny.zip."
  curl -fsSL "$DOWNLOADS/Cranny.zip.sha256" -o "$tmp/Cranny.zip.sha256" || fail "Couldn't download the checksum."

  say "Verifying the download"
  local expected actual
  expected="$(awk '{print $1}' "$tmp/Cranny.zip.sha256")"
  actual="$(shasum -a 256 "$tmp/Cranny.zip" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || fail "The download didn't match its checksum, so nothing was installed."

  ditto -x -k "$tmp/Cranny.zip" "$tmp/unpacked"
  [[ -d "$tmp/unpacked/Cranny.app" ]] || fail "The download didn't contain Cranny.app."

  if pgrep -xq Cranny; then
    say "Quitting the running copy"
    pkill -x Cranny || true
    for _ in {1..25}; do
      pgrep -xq Cranny || break
      sleep 0.2
    done
  fi

  say "Installing into $dest"
  rm -rf "$dest/Cranny.app"
  ditto "$tmp/unpacked/Cranny.app" "$dest/Cranny.app"

  local version
  version="$(defaults read "$dest/Cranny.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
  open "$dest/Cranny.app"
  say "Cranny $version is installed. Hover over your notch to try it."
}

main "$@"
