#!/usr/bin/env bash
# ==============================================================================
# gpg-setup.sh — GPG key management for package signing
# ==============================================================================
# Usage: ./scripts/utils/gpg-setup.sh [command]
# Commands:
#   generate    — Generate new GPG key for signing
#   export      — Export public key for distribution
#   import      — Import existing private key from env/file
#   test        — Test signing with current key
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="GPG"
readonly GPG_HOME="${GPG_HOME:-$HOME/.gnupg}"
readonly KEY_NAME="Helium Browser Repository"
readonly KEY_EMAIL="${GPG_EMAIL:-noreply@github.com}"
readonly KEY_COMMENT="Package Signing Key"

cmd_generate() {
  log "Generating new GPG key for package signing..."
  
  mkdir -p "$GPG_HOME"
  chmod 700 "$GPG_HOME"
  
  # Batch key generation
  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $KEY_NAME
Name-Comment: $KEY_COMMENT
Name-Email: $KEY_EMAIL
Expire-Date: 2y
%commit
EOF

  log "GPG key generated successfully!"
  gpg --list-secret-keys --keyid-format LONG "$KEY_EMAIL"
}

cmd_export() {
  log "Exporting public key..."
  
  local key_id
  key_id=$(gpg --list-secret-keys --keyid-format LONG "$KEY_EMAIL" 2>/dev/null | \
    grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)
  
  if [[ -z "$key_id" ]]; then
    err "No GPG key found for $KEY_EMAIL. Run: $0 generate"
  fi
  
  local output_file="${1:-site/public/HELIUM-GPG-KEY}"
  mkdir -p "$(dirname "$output_file")"
  
  gpg --armor --export "$key_id" > "$output_file"
  log "Public key exported to: $output_file"
  log "Key ID: $key_id"
  log "Fingerprint: $(gpg --fingerprint "$key_id" | grep -oP '[A-F0-9]{4}(\s+[A-F0-9]{4}){9}' | head -1)"
}

cmd_import() {
  local key_data="${1:-${GPG_PRIVATE_KEY:-}}"
  
  if [[ -z "$key_data" ]]; then
    err "No key data provided. Set GPG_PRIVATE_KEY env var or provide file path."
  fi
  
  log "Importing GPG private key..."
  
  if [[ -f "$key_data" ]]; then
    gpg --batch --import "$key_data"
  else
    echo "$key_data" | gpg --batch --import
   fi
  
  # Trust the key ultimately
  local key_id
  key_id=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | \
    grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)
  
  if [[ -n "$key_id" ]]; then
    echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$key_id" trust quit 2>/dev/null || true
    log "Key imported and trusted: $key_id"
  fi
}

cmd_test() {
  log "Testing GPG signing..."
  
  local test_file
  test_file=$(mktemp)
  echo "test" > "$test_file"
  
  if gpg --detach-sign --armor "$test_file" 2>/dev/null; then
    log "✓ GPG signing works!"
    rm -f "$test_file" "$test_file.asc"
  else
    err "GPG signing failed. Check your key configuration."
  fi
}

cmd_show() {
  log "Current GPG keys:"
  gpg --list-secret-keys --keyid-format LONG
}

# Main
case "${1:-show}" in
  generate) cmd_generate ;;
  export) cmd_export "${2:-}" ;;
  import) cmd_import "${2:-}" ;;
  test) cmd_test ;;
  show) cmd_show ;;
  *) echo "Usage: $0 {generate|export|import|test|show}"; exit 1 ;;
esac
