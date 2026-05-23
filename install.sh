#!/usr/bin/env sh
# sprite-ntfy installer
# Run this inside a sprite console:
#   curl -fsSL https://raw.githubusercontent.com/lubien/sprite-ntfy/main/install.sh | sh
set -eu

# ── Versions & paths ──────────────────────────────────────────────────────────
NTFY_VERSION="2.23.0"
NTFY_BIN="/usr/local/bin/ntfy"
NTFY_CONFIG="/etc/ntfy/server.yml"
NTFY_DATA="/var/lib/ntfy"
NTFY_CACHE="/var/cache/ntfy"
NTFY_PORT="8080"
REPO_URL="https://github.com/lubien/sprite-ntfy"

# ── Colour helpers (degrade gracefully when no tty) ───────────────────────────
if [ -t 2 ]; then
  GRN='\033[0;32m' YLW='\033[1;33m' RED='\033[0;31m' BLD='\033[1m' RST='\033[0m'
else
  GRN='' YLW='' RED='' BLD='' RST=''
fi

info() { printf "${GRN}==> ${BLD}%s${RST}\n" "$*"; }
step() { printf "    %s\n" "$*"; }
warn() { printf "${YLW} !  %s${RST}\n" "$*"; }
die()  { printf "${RED}✗ error:${RST} %s\n" "$*" >&2; exit 1; }

# ── 1. Pre-flight: confirm we're inside a sprite ──────────────────────────────
info "Checking sprite environment..."
SPRITE_INFO=$(sprite-env info 2>/dev/null) \
  || die "sprite-env not found. Please run this inside a sprite (via 'sprite console')."

SPRITE_URL=$(printf '%s' "$SPRITE_INFO" | python3 -c \
  "import sys, json; print(json.load(sys.stdin)['sprite_url'])" 2>/dev/null) \
  || die "Could not parse sprite URL from: $SPRITE_INFO"

step "Sprite URL: ${BLD}${SPRITE_URL}${RST}"

# ── 2. Install ntfy binary ────────────────────────────────────────────────────
if command -v ntfy >/dev/null 2>&1; then
  INSTALLED_VER=$(ntfy 2>&1 | grep -oE 'ntfy [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | head -1 || echo "unknown")
  info "ntfy already installed (v${INSTALLED_VER}), skipping download."
else
  info "Downloading ntfy v${NTFY_VERSION}..."

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)        NTFY_ARCH="amd64" ;;
    aarch64|arm64) NTFY_ARCH="arm64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac

  ARCHIVE="ntfy_${NTFY_VERSION}_linux_${NTFY_ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/binwiederhier/ntfy/releases/download/v${NTFY_VERSION}/${ARCHIVE}"

  TMP=$(mktemp -d)
  # shellcheck disable=SC2064
  trap 'rm -rf "$TMP"' EXIT INT TERM

  step "Fetching ${DOWNLOAD_URL}..."
  curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP/ntfy.tar.gz"
  tar -xzf "$TMP/ntfy.tar.gz" -C "$TMP"

  sudo cp "$TMP/ntfy_${NTFY_VERSION}_linux_${NTFY_ARCH}/ntfy" "$NTFY_BIN"
  sudo chmod +x "$NTFY_BIN"
  step "Installed ntfy at ${NTFY_BIN}"
fi

# ── 3. Prepare data directories ───────────────────────────────────────────────
info "Preparing directories..."
sudo mkdir -p /etc/ntfy "$NTFY_DATA" "$NTFY_CACHE"
# Data dirs must be writable by the current (sprite) user so ntfy can manage its DBs
sudo chown -R "$(id -un):$(id -gn)" "$NTFY_DATA" "$NTFY_CACHE"
step "/etc/ntfy  /var/lib/ntfy  /var/cache/ntfy ready"

# ── 4. Write server config ────────────────────────────────────────────────────
info "Writing server config to ${NTFY_CONFIG}..."

sudo tee "$NTFY_CONFIG" >/dev/null <<EOF
# ntfy server config — managed by sprite-ntfy
# https://github.com/lubien/sprite-ntfy

base-url: $SPRITE_URL
listen-http: ":$NTFY_PORT"

# Auth — deny unauthenticated access by default.
# Users are added with: ntfy user add <username>
auth-file: $NTFY_DATA/user.db
auth-default-access: deny-all
enable-login: true
enable-signup: false

# Message cache (survives ntfy restarts)
cache-file: $NTFY_CACHE/cache.db
cache-duration: 12h

# The sprites proxy terminates TLS — ntfy only speaks plain HTTP internally.
behind-proxy: true
EOF

step "Config written."

# ── 5. Initialize ntfy DBs and create admin user ─────────────────────────────
info "Initialising ntfy (creates DB files on first run)..."
# ntfy user management requires the server to have been started at least once so
# that it creates the SQLite database files.  We start it briefly in the
# background, wait for it to be ready, then kill it before registering the
# permanent sprite service.
# On a re-run the DB already exists — skip the temp start to avoid a port conflict
# with the already-running sprite service.
_NTFY_TMP_PID=""
if [ ! -f "$NTFY_DATA/user.db" ]; then
  ntfy serve --config "$NTFY_CONFIG" >/dev/null 2>&1 &
  _NTFY_TMP_PID=$!
  trap 'kill "$_NTFY_TMP_PID" 2>/dev/null; wait "$_NTFY_TMP_PID" 2>/dev/null || true' EXIT INT TERM

  # Wait until ntfy's health endpoint responds (up to 10 s)
  _tries=0
  while [ "$_tries" -lt 20 ]; do
    _health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NTFY_PORT}/v1/health" 2>/dev/null || echo "000")
    [ "$_health" = "200" ] && break
    sleep 0.5
    _tries=$((_tries + 1))
  done
  [ "$_health" = "200" ] || warn "ntfy did not respond in time — proceeding anyway."
  step "ntfy initialised (DB files created)."
else
  step "DB files already exist, skipping temporary ntfy start."
fi

info "Setting up admin user..."

# Support non-interactive mode via environment variables
if [ -n "${NTFY_ADMIN_USER:-}" ] && [ -n "${NTFY_ADMIN_PASSWORD:-}" ]; then
  ADMIN_USER="$NTFY_ADMIN_USER"
  ADMIN_PASS="$NTFY_ADMIN_PASSWORD"
  step "Using credentials from NTFY_ADMIN_USER / NTFY_ADMIN_PASSWORD env vars."
else
  # /dev/tty lets us prompt even when stdin is piped from curl
  printf "  Admin username [admin]: " >/dev/tty
  read -r ADMIN_USER </dev/tty
  ADMIN_USER="${ADMIN_USER:-admin}"

  ADMIN_PASS=""
  while [ -z "$ADMIN_PASS" ]; do
    stty_save=$(stty -g </dev/tty)
    printf "  Admin password: " >/dev/tty
    stty -echo </dev/tty
    read -r ADMIN_PASS </dev/tty
    stty "$stty_save" </dev/tty
    printf "\n" >/dev/tty

    printf "  Confirm password: " >/dev/tty
    stty -echo </dev/tty
    read -r _confirm </dev/tty
    stty "$stty_save" </dev/tty
    printf "\n" >/dev/tty

    if [ -z "$ADMIN_PASS" ]; then
      warn "Password cannot be empty. Try again."
    elif [ "$ADMIN_PASS" != "$_confirm" ]; then
      warn "Passwords do not match. Try again."
      ADMIN_PASS=""
    fi
  done
fi

# ntfy user add exits non-zero if the user already exists.
# In that case fall back to updating the password and promoting to admin.
if NTFY_PASSWORD="$ADMIN_PASS" ntfy user add --role=admin "$ADMIN_USER" 2>/dev/null; then
  step "Admin user '${ADMIN_USER}' created."
else
  step "User '${ADMIN_USER}' already exists — updating password and role..."
  NTFY_PASSWORD="$ADMIN_PASS" ntfy user change-pass "$ADMIN_USER"
  ntfy user change-role "$ADMIN_USER" admin
  step "Admin user '${ADMIN_USER}' updated."
fi

# Shut down the temporary ntfy process (if one was started) before handing off
if [ -n "$_NTFY_TMP_PID" ]; then
  kill "$_NTFY_TMP_PID" 2>/dev/null
  wait "$_NTFY_TMP_PID" 2>/dev/null || true
  trap - EXIT INT TERM
  step "Temporary ntfy process stopped."
fi

# ── 6. Register sprite service ────────────────────────────────────────────────
info "Registering ntfy as a sprite service..."

# Remove stale service definition if it exists
sprite-env services delete ntfy 2>/dev/null && step "Removed existing service." || true

sprite-env services create ntfy \
  --cmd "$NTFY_BIN" \
  --args "serve,--config,$NTFY_CONFIG" \
  --http-port "$NTFY_PORT"

# ── 7. Clone repo for future updates ─────────────────────────────────────────
INSTALL_DIR="$HOME/sprite-ntfy"
if [ -d "$INSTALL_DIR" ]; then
  step "Repo already at ${INSTALL_DIR}, skipping clone."
else
  info "Cloning repo to ${INSTALL_DIR}..."
  git clone "$REPO_URL" "$INSTALL_DIR" \
    && step "Cloned to ${INSTALL_DIR}." \
    || warn "Could not clone repo — network issue? You can clone manually later."
fi

# ── 8. Quick health check ─────────────────────────────────────────────────────
info "Waiting for ntfy to start..."
sleep 3
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NTFY_PORT}/v1/health" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
  step "ntfy is up and healthy (HTTP ${HTTP_STATUS})."
else
  warn "Health check returned HTTP ${HTTP_STATUS} — ntfy may still be starting."
  warn "Check logs with: sprite-env services get ntfy"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n"
info "Installation complete!"
printf "    ntfy URL:   ${BLD}%s${RST}\n" "$SPRITE_URL"
printf "    Admin user: ${BLD}%s${RST}\n" "$ADMIN_USER"
printf "\n"
printf "${YLW}Next step:${RST} make the URL publicly accessible by running this on your LOCAL machine:\n"
printf "\n"
printf "    sprite url update --auth public\n"
printf "\n"
printf "Without this, only requests with a valid sprite token can reach ntfy.\n"
