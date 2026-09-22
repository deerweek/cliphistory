# Sign with one local certificate kept in its own keychain.
# The same certificate is reused on every build, so the Accessibility
# grant survives updates. Ad-hoc signatures do not.
CERT_NAME="ClipHistory Local Codesign"
SUPPORT="${HOME}/Library/Application Support/剪贴板记录"
KEYCHAIN="${SUPPORT}/signing.keychain-db"
PASSFILE="${SUPPORT}/signing.pass"

sign_app() {
  local app="$1"
  if ! sign_with_cert "$app"; then
    codesign --force --sign - --identifier local.cliphistory "$app"
  fi
}

sign_with_cert() {
  local app="$1"
  ensure_signing_keychain
  local pass sha
  pass="$(cat "$PASSFILE")"
  security unlock-keychain -p "$pass" "$KEYCHAIN"
  sha="$(security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" | awk '/SHA-1 hash:/ { print $3; exit }')"
  [[ -n "$sha" ]] || return 1
  codesign --force --timestamp=none --sign "$sha" --keychain "$KEYCHAIN" --identifier local.cliphistory "$app"
}

ensure_signing_keychain() {
  mkdir -p "$SUPPORT"
  if [[ ! -f "$PASSFILE" ]]; then
    openssl rand -base64 24 > "$PASSFILE"
    chmod 600 "$PASSFILE"
  fi
  local pass
  pass="$(cat "$PASSFILE")"
  if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$pass" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
  fi
  security unlock-keychain -p "$pass" "$KEYCHAIN"
  if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    return
  fi

  local dir
  dir="$(mktemp -d)"
  cat > "$dir/cert.cfg" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no
[ req_dn ]
CN = ClipHistory Local Codesign
O = Local
[ codesign_ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
    -config "$dir/cert.cfg" \
    -keyout "$dir/key.pem" \
    -out "$dir/cert.pem" >/dev/null 2>&1
  openssl pkcs12 -export \
    -inkey "$dir/key.pem" \
    -in "$dir/cert.pem" \
    -out "$dir/cert.p12" \
    -passout pass:cliphistory >/dev/null 2>&1
  security import "$dir/cert.p12" \
    -k "$KEYCHAIN" \
    -P cliphistory \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -A
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$pass" \
    "$KEYCHAIN" >/dev/null
  rm -rf "$dir"
}
