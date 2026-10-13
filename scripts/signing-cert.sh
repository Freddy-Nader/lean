#!/bin/sh
# One-time: creates the self-signed "lean" code-signing certificate and imports it into the login
# keychain. build.sh and the updater sign with it, so macOS keeps privacy grants (Full Disk Access)
# across rebuilds and updates: an ad-hoc signature changes identity with every build.
# Leaves lean.p12 + password in ~/.config/lean/signing/ for the CI secrets (see README).
set -e
DIR="$HOME/.config/lean/signing"
if security find-certificate -c lean >/dev/null 2>&1; then echo "cert 'lean' already in keychain"; exit 0; fi
mkdir -p "$DIR" && chmod 700 "$DIR" && cd "$DIR"
umask 077
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -subj "/CN=lean" \
  -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" -keyout lean.key -out lean.crt 2>/dev/null
openssl rand -hex 16 > p12-password
# -legacy: the keychain cannot read OpenSSL 3's default p12 encryption.
openssl pkcs12 -export -legacy -inkey lean.key -in lean.crt -name lean -passout file:p12-password -out lean.p12
rm lean.key
security import lean.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P "$(cat p12-password)" -T /usr/bin/codesign
echo "imported 'lean'. CI secrets: $DIR/lean.p12 (base64) and $DIR/p12-password"
