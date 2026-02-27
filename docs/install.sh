#!/usr/bin/env bash
# shiv quick-install — https://shiv.knacklabs.co
# Usage: curl -fsSL shiv.knacklabs.co/install.sh | bash
set -eo pipefail

# Configuration via environment variables
SHIV_NONINTERACTIVE="${SHIV_NONINTERACTIVE:-0}"
SHIV_INSTALL_PATH="${SHIV_INSTALL_PATH:-$HOME/.local/share/shiv/self}"
SHIV_BIN_DIR="${SHIV_BIN_DIR:-$HOME/.local/bin}"
SHIV_CONFIG_DIR="${SHIV_CONFIG_DIR:-$HOME/.config/shiv}"
SHIV_REGISTRIES="${SHIV_REGISTRIES:-}"

CHICLE_URL="https://github.com/KnickKnackLabs/chicle/releases/latest/download/chicle.sh"
TOTAL_STEPS=6

# --- stdin redirect for curl | bash ---
# When piped, stdin is the pipe. Redirect from /dev/tty for interactive prompts.
if [ ! -t 0 ]; then
  if [ "$SHIV_NONINTERACTIVE" != "1" ] && (: < /dev/tty) 2>/dev/null; then
    exec < /dev/tty
  else
    SHIV_NONINTERACTIVE=1
  fi
fi

# --- Load chicle with graceful fallback ---
eval "$(curl -fsSL "$CHICLE_URL" 2>/dev/null)" 2>/dev/null || true

if ! type chicle_log >/dev/null 2>&1; then
  chicle_style() {
    local text=""
    while [ $# -gt 0 ]; do
      case $1 in --bold|--dim|--cyan|--green|--yellow|--red) shift ;; *) text="$1"; shift ;; esac
    done
    printf "%s" "$text"
  }
  chicle_rule() { printf '%s\n' "────────────────────────────────────────"; }
  chicle_log() {
    local level="" message=""
    while [ $# -gt 0 ]; do
      case $1 in --info|--success|--warn|--error|--debug|--step) level="${1#--}"; shift ;; *) message="$1"; shift ;; esac
    done
    case $level in
      info)    echo "ℹ $message" ;; success) echo "✓ $message" ;; warn) echo "⚠ $message" ;;
      error)   echo "✗ $message" ;; step)    echo "→ $message" ;; *)    echo "$message" ;;
    esac
  }
  chicle_steps() {
    local current=0 total=0 title=""
    while [ $# -gt 0 ]; do
      case $1 in --current) current="$2"; shift 2 ;; --total) total="$2"; shift 2 ;; --title) title="$2"; shift 2 ;; *) shift ;; esac
    done
    echo "[$current/$total] $title"
  }
  chicle_spin() {
    local title=""
    while [ $# -gt 0 ]; do
      case $1 in --title) title="$2"; shift 2 ;; --) shift; break ;; *) shift ;; esac
    done
    echo "... $title"
    "$@"
  }
  chicle_confirm() {
    local default="no" prompt=""
    while [ $# -gt 0 ]; do
      case $1 in --default) default="$2"; shift 2 ;; *) prompt="$1"; shift ;; esac
    done
    local hint="[y/N]"
    [ "$default" = "yes" ] && hint="[Y/n]"
    printf "%s %s " "$prompt" "$hint"
    read -r reply
    if [ -z "$reply" ]; then
      [ "$default" = "yes" ]
    else
      echo "$reply" | grep -qi '^y'
    fi
  }
  chicle_choose() {
    local header="" options=()
    while [ $# -gt 0 ]; do
      case $1 in --header) header="$2"; shift 2 ;; --multi) shift ;; *) options+=("$1"); shift ;; esac
    done
    [ -n "$header" ] && echo "$header"
    local i=1
    for opt in "${options[@]}"; do
      echo "  $i) $opt"
      i=$((i + 1))
    done
    printf "> "
    read -r choice
    # Support comma-separated for multi-select fallback
    local IFS=','
    for c in $choice; do
      c=$(echo "$c" | tr -d ' ')
      [ -n "$c" ] && echo "${options[$((c - 1))]}"
    done
  }
fi

is_interactive() {
  [ "$SHIV_NONINTERACTIVE" != "1" ] && [ -t 0 ]
}

# --- Step 1: Detect environment ---
echo ""
chicle_rule
chicle_style --bold "shiv installer"
echo ""
chicle_rule
echo ""

chicle_steps --current 1 --total $TOTAL_STEPS --title "Detecting environment" --style dots

OS="$(uname -s)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *)      chicle_log --error "Unsupported OS: $OS"; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH_NAME="x64" ;;
  arm64|aarch64) ARCH_NAME="arm64" ;;
  *) ARCH_NAME="$ARCH" ;;
esac

USER_SHELL="$(basename "${SHELL:-/bin/bash}")"

chicle_log --success "Detected $OS_NAME ($ARCH_NAME), shell: $USER_SHELL"

for cmd in curl git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    chicle_log --error "Required tool not found: $cmd"
    chicle_log --info "Install $cmd and re-run the installer."
    exit 1
  fi
done

chicle_log --success "Prerequisites satisfied (curl, git)"
echo ""

# --- Step 2: Set up mise ---
chicle_steps --current 2 --total $TOTAL_STEPS --title "Setting up mise" --style dots

if command -v mise >/dev/null 2>&1; then
  MISE_VERSION="$(mise --version 2>/dev/null | head -1)"
  chicle_log --success "mise already installed ($MISE_VERSION)"
else
  chicle_log --info "mise not found — installing..."
  chicle_spin --title "Installing mise" -- \
    bash -c 'curl -fsSL https://mise.jdx.dev/install.sh | MISE_QUIET=1 sh'

  export PATH="$HOME/.local/bin:$PATH"

  if command -v mise >/dev/null 2>&1; then
    chicle_log --success "mise installed successfully"
  else
    chicle_log --error "mise installation failed"
    exit 1
  fi
fi
echo ""

# --- Step 3: Install shiv ---
chicle_steps --current 3 --total $TOTAL_STEPS --title "Installing shiv" --style dots

if [ -d "$SHIV_INSTALL_PATH/.git" ]; then
  chicle_log --info "shiv already installed — updating..."
  chicle_spin --title "Pulling latest" -- \
    git -C "$SHIV_INSTALL_PATH" pull --ff-only --quiet
  chicle_log --success "shiv updated"
else
  mkdir -p "$(dirname "$SHIV_INSTALL_PATH")"
  chicle_spin --title "Cloning shiv" -- \
    git clone --quiet https://github.com/KnickKnackLabs/shiv.git "$SHIV_INSTALL_PATH"
  chicle_log --success "shiv cloned to $SHIV_INSTALL_PATH"
fi

chicle_spin --title "Installing shiv dependencies" -- \
  bash -c "cd '$SHIV_INSTALL_PATH' && mise trust -q 2>/dev/null; mise install -q 2>/dev/null"

chicle_log --success "shiv dependencies ready"
echo ""

# --- Step 4: Configure registries ---
# Each registry is a separate .json file in ~/.config/shiv/sources/.
# SHIV_SOURCES is auto-discovered as a comma-delimited list of these files.
chicle_steps --current 4 --total $TOTAL_STEPS --title "Configuring package sources" --style dots

SOURCES_DIR="$SHIV_CONFIG_DIR/sources"
mkdir -p "$SOURCES_DIR"

# KnickKnackLabs sources (always installed)
cp "$SHIV_INSTALL_PATH/sources.json" "$SOURCES_DIR/knacklabs.json"
chicle_log --success "Added KnickKnackLabs packages"

add_ricon_registry() {
  cat > "$SOURCES_DIR/ricon-family.json" <<'RICON'
{
  "fold": "ricon-family/fold",
  "food": "ricon-family/food-life"
}
RICON
  chicle_log --success "Added ricon-family packages"
}

if [ -n "$SHIV_REGISTRIES" ]; then
  # Non-interactive: parse env var
  if echo "$SHIV_REGISTRIES" | grep -q "ricon-family"; then
    add_ricon_registry
  fi
elif is_interactive; then
  echo ""
  SELECTED=$(chicle_choose --header "Additional package registries" --multi \
    "ricon-family (fold, food)")

  if echo "$SELECTED" | grep -q "ricon-family"; then
    add_ricon_registry
  fi
fi

# Count total packages across all source files
PACKAGE_COUNT=0
for sf in "$SOURCES_DIR"/*.json; do
  [ -f "$sf" ] || continue
  n=$(mise -C "$SHIV_INSTALL_PATH" exec -- jq 'length' "$sf")
  PACKAGE_COUNT=$((PACKAGE_COUNT + n))
done
chicle_log --success "$PACKAGE_COUNT packages available"
echo ""

# --- Step 5: Shell integration ---
chicle_steps --current 5 --total $TOTAL_STEPS --title "Setting up shell integration" --style dots

# Create shiv's own shim
mkdir -p "$SHIV_BIN_DIR"
cat > "$SHIV_BIN_DIR/shiv" <<SHIM
#!/usr/bin/env bash
# managed by shiv
REPO="$SHIV_INSTALL_PATH"
if [ ! -d "\$REPO" ]; then
  echo "shiv: repo not found at \$REPO" >&2
  echo "shiv: reinstall with: curl -fsSL shiv.knacklabs.co/install.sh | bash" >&2
  exit 1
fi
exec mise -C "\$REPO" run "\$@"
SHIM
chmod +x "$SHIV_BIN_DIR/shiv"

# Initialize registry
mkdir -p "$(dirname "$SHIV_CONFIG_DIR/registry.json")"
if [ ! -f "$SHIV_CONFIG_DIR/registry.json" ]; then
  echo '{}' > "$SHIV_CONFIG_DIR/registry.json"
fi

# Register shiv in its own registry
TMP=$(mise -C "$SHIV_INSTALL_PATH" exec -- jq --arg p "$SHIV_INSTALL_PATH" '. + {"shiv": $p}' "$SHIV_CONFIG_DIR/registry.json")
echo "$TMP" > "$SHIV_CONFIG_DIR/registry.json"

chicle_log --success "shiv shim created at $SHIV_BIN_DIR/shiv"

# Determine shell config file
SHELL_CONFIG=""
case "$USER_SHELL" in
  bash)
    if [ -f "$HOME/.bashrc" ]; then SHELL_CONFIG="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then SHELL_CONFIG="$HOME/.bash_profile"
    fi
    ;;
  zsh) SHELL_CONFIG="$HOME/.zshrc" ;;
  fish) SHELL_CONFIG="$HOME/.config/fish/config.fish" ;;
esac

EVAL_LINE="eval \"\$(mise -C '$SHIV_INSTALL_PATH' run -q shell)\""

ALREADY_CONFIGURED=0
if [ -n "$SHELL_CONFIG" ] && grep -qF "shiv" "$SHELL_CONFIG" 2>/dev/null; then
  ALREADY_CONFIGURED=1
  chicle_log --success "Shell already configured ($SHELL_CONFIG)"
fi

if [ "$ALREADY_CONFIGURED" = "0" ] && [ -n "$SHELL_CONFIG" ]; then
  add_shell_config() {
    echo "" >> "$SHELL_CONFIG"
    echo "# shiv — managed tool shims" >> "$SHELL_CONFIG"
    echo "$EVAL_LINE" >> "$SHELL_CONFIG"
    chicle_log --success "Added to $SHELL_CONFIG"
  }

  if is_interactive; then
    echo ""
    if chicle_confirm --default yes "Add shiv to $SHELL_CONFIG?"; then
      add_shell_config
    else
      chicle_log --warn "Skipped — add manually:"
      chicle_log --info "  $EVAL_LINE"
    fi
  else
    add_shell_config
  fi
fi
echo ""

# --- Step 6: Verify ---
chicle_steps --current 6 --total $TOTAL_STEPS --title "Verifying installation" --style dots

export PATH="$SHIV_BIN_DIR:$PATH"

if "$SHIV_BIN_DIR/shiv" list >/dev/null 2>&1; then
  chicle_log --success "shiv is working"
else
  chicle_log --warn "shiv installed but verification failed — check your PATH"
fi

echo ""
chicle_rule
chicle_style --bold --green "Installation complete!"
echo ""
chicle_rule
echo ""
chicle_log --info "Installed to: $SHIV_INSTALL_PATH"
chicle_log --info "Shim at: $SHIV_BIN_DIR/shiv"
chicle_log --info "Config at: $SHIV_CONFIG_DIR/"
echo ""
chicle_log --step "Next steps:"
echo "  1. Restart your shell (or run: source $SHELL_CONFIG)"
echo "  2. Try: shiv list"
echo "  3. Install a tool: shiv install shimmer"
echo ""
