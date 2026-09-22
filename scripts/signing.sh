sign_app() {
  local app="$1"
  local identity="${CLIPHISTORY_CODESIGN_IDENTITY:--}"
  # A plain ad-hoc signature gets a designated requirement containing the
  # executable's cdhash.  That hash changes on every rebuild, so macOS treats
  # every build as a different Accessibility client and silently invalidates
  # the user's checkbox.  Embed a stable identifier requirement for local
  # builds instead.  The bundle path is still part of the client identity,
  # which means the user only has to authorize the copy in Applications.
  if [[ "$identity" == "-" ]]; then
    local req
    req="$(mktemp -t cliphistory-codesign-req)"
    printf 'designated => identifier "local.cliphistory"\n' > "$req"
    codesign --force --timestamp=none --sign "$identity" \
      --requirements "$req" --identifier local.cliphistory "$app"
    rm -f "$req"
  else
    codesign --force --timestamp=none --sign "$identity" \
      --identifier local.cliphistory "$app"
  fi
}
