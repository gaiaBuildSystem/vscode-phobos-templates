#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# tcd-env-setup.sh — Install torizon-dev environment system-wide
# Run as your normal user:  ./tcd-env-setup.sh
# Per-user assets go to ~/.tcd; the system-wide bits (/usr/local/bin
# and /usr/share/bash-completion/completions/) are installed through
# sudo automatically. Running it with plain `sudo` also works: the
# invoking user's home is resolved from $SUDO_USER.
# ============================================================

echo "=== Installing Torizon dev environment ==="

# --- Resolve the real (non-root) user and its home directory ---
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        __TCD_REAL_USER="$SUDO_USER"
    else
        __TCD_REAL_USER="root"
    fi
else
    if ! command -v sudo > /dev/null 2>&1; then
        echo "ERROR: sudo is required to install torizon-dev system-wide."
        exit 1
    fi
    SUDO="sudo"
    __TCD_REAL_USER="$(id -un)"
fi

HOME="$(getent passwd "$__TCD_REAL_USER" | cut -d: -f6)"
if [ -z "$HOME" ] || [ ! -d "$HOME" ]; then
    echo "ERROR: Could not resolve home directory for user '$__TCD_REAL_USER'."
    exit 1
fi
export HOME

__TCD_COMPOSE_FILE="$HOME/.tcd/docker-compose.yml"
__TCD_BASH_COMPLETION_FILE="$HOME/.tcd/torizon-dev-completion.bash"
export __TCD_APOLLOX_REPO="torizon/vscode-torizon-templates"
export __TCD_APOLLOX_BRANCH="dev"
export __TCD_BRANCH="dev"
export __TCD_UUID=$(id -u "$__TCD_REAL_USER")
export __TCD_DGID=$(getent group docker | cut -d: -f3 2>/dev/null || echo 100)

# --- Create .tcd directory and download required files ---
if [ ! -d "$HOME/.tcd" ]; then
    echo "Creating $HOME/.tcd ..."
    mkdir -p "$HOME/.tcd"
else
    echo "Found $HOME/.tcd ... Cleaning up old assets ..."
    rm -rf "$HOME/.tcd/docker-compose.yml"
    rm -rf "$HOME/.tcd/torizon-dev-completion.bash"
fi

# Download docker-compose.yml if missing
if [ ! -f "$__TCD_COMPOSE_FILE" ]; then
    echo "Downloading docker-compose.yml from GitHub ..."
    wget -q "https://raw.githubusercontent.com/$__TCD_APOLLOX_REPO/$__TCD_APOLLOX_BRANCH/scripts/container/docker-compose.yml" -O "$__TCD_COMPOSE_FILE" || { echo "Warning: Could not download docker-compose.yml"; exit 1; }
fi

# Download bash completion if missing
if [ ! -f "$__TCD_BASH_COMPLETION_FILE" ]; then
    echo "Downloading bash completion from GitHub ..."
    wget -q "https://raw.githubusercontent.com/$__TCD_APOLLOX_REPO/$__TCD_APOLLOX_BRANCH/scripts/bash/tcd-completion.bash" -O "$__TCD_BASH_COMPLETION_FILE" || true
fi

# If we were invoked through sudo, give ~/.tcd back to the real user so the
# torizon-dev wrapper (which runs unprivileged) can update these files later.
if [ "$(id -u)" -eq 0 ] && [ "$__TCD_REAL_USER" != "root" ]; then
    chown -R "$__TCD_REAL_USER": "$HOME/.tcd"
fi

# --- Compute workspace hash for container naming (needed by compose template) ---
myhash=$(echo -n "$PWD" | openssl dgst -sha256 | sed 's/^.* //')
export __TCD_SHA_DIR=$myhash

# --- Pull the Docker image ---
echo "Pulling torizon-dev image ..."
docker compose -f "$__TCD_COMPOSE_FILE" pull torizon-dev

# --- Resolve target paths (system-wide, written through sudo) ---
TARGET_BIN="/usr/local/bin/torizon-dev"
TARGET_COMPLETION_FILE="/usr/share/bash-completion/completions/torizon-dev"

if [ -n "$SUDO" ]; then
    echo "Installing system-wide files (you may be asked for your sudo password) ..."
fi

$SUDO mkdir -p "$(dirname "$TARGET_BIN")"
$SUDO mkdir -p "$(dirname "$TARGET_COMPLETION_FILE")"

__TCD_TMP_BIN="$(mktemp)"
trap 'rm -f "$__TCD_TMP_BIN"' EXIT

cat > "$__TCD_TMP_BIN" <<'ENDOFSCRIPT'
#!/usr/bin/env bash

# ============================================================
# torizon-dev — standalone wrapper for Torizon dev environment
# System-wide installation (installed by tcd-env-setup.sh, requires root)
# Replaces the inline function in tcd-env-setup.sh so you can run
# `torizon-dev` directly from anywhere without sourcing anything.
# ============================================================

# --- Environment variables (must be set before docker commands) ---
__TCD_COMPOSE_FILE="$HOME/.tcd/docker-compose.yml"
export __TCD_APOLLOX_REPO="torizon/vscode-torizon-templates"
export __TCD_BRANCH="dev"
export __TCD_APOLLOX_BRANCH="dev"
export __TCD_UUID=$(id -u 2>/dev/null || echo 0)
export __TCD_DGID=$(getent group docker | cut -d: -f3 2>/dev/null || echo 100)

# --- Clean mode: remove all torizon-dev containers if --clean is passed ---
CLEAN_MODE=false
CLEAN_ASSUME_YES=false
if [[ "${1:-}" == "--clean" || "${1:-}" == "-c" ]]; then
    CLEAN_MODE=true
    # --yes / -y: remove everything (running containers included) without asking
    if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
        CLEAN_ASSUME_YES=true
    fi
fi

if [ "$CLEAN_MODE" = true ]; then
    echo "=== Cleaning up Torizon dev containers ==="
    # Pattern to match torizon-dev containers (any hash suffix)
    CONT_PATTERN="torizon-dev-[a-f0-9]+"

    # List all matching containers
    MATCHING=$(docker ps -aq -f name="$CONT_PATTERN" 2>/dev/null || true)

    if [ -z "$MATCHING" ]; then
        echo "No torizon-dev containers found. Nothing to clean."
        echo ""
        echo "To re-enter a dev environment, run:"
        echo "  torizon-dev              # start fresh for current workspace"
        exit 0
    fi

    # Collect container names and details
    echo "Found the following torizon-dev containers:"
    CONT_LIST=""
    while IFS= read -r cid; do
        [ -z "$cid" ] && continue
        NAME=$(docker inspect --format='{{.Name}}' "$cid" 2>/dev/null || echo "unknown")
        STATE=$(docker inspect --format='{{.State.Status}}' "$cid" 2>/dev/null || echo "unknown")
        CREATED=$(docker inspect --format='{{.Created}}' "$cid" 2>/dev/null || echo "unknown")

        if [ "$STATE" = "running" ]; then
            echo "  ⚠️  $NAME — running (created: $CREATED)"
            if [ "$CLEAN_ASSUME_YES" = true ]; then
                CONFIRM="y"
            else
                # stdin is the container list here, so ask on the terminal
                read -r -p "Stop and remove? [y/N] " CONFIRM < /dev/tty || CONFIRM=""
            fi
            if [[ ! "${CONFIRM,,}" =~ ^y(es)?$ ]]; then
                echo "Aborted. Containers preserved."
                exit 0
            fi
        else
            echo "  ℹ️   $NAME — stopped/missing (created: $CREATED)"
        fi
        CONT_LIST="$CONT_LIST $cid"
    done < <(docker ps -aq -f name="$CONT_PATTERN" 2>/dev/null)

    # Stop all running containers first
    for cid in $CONT_LIST; do
        [ -z "$cid" ] && continue
        docker stop "$cid" > /dev/null 2>&1 || true
    done

    # Remove all matching containers
    echo ""
    echo "Removing containers..."
    REMOVED=0
    while IFS= read -r cid; do
        [ -z "$cid" ] && continue
        if docker rm "$cid" > /dev/null 2>&1; then
            echo "  ✅ Removed $cid"
            REMOVED=$((REMOVED + 1))
        else
            echo "  ❌ Failed to remove $cid"
        fi
    done < <(docker ps -aq -f name="$CONT_PATTERN" 2>/dev/null)

    echo ""
    if [ "$REMOVED" -gt 0 ]; then
        echo "✅ Removed $REMOVED torizon-dev container(s)."
    else
        echo "ℹ️   No containers were removed."
    fi

    # Clean up any leftover .tcd docker-compose references for these containers
    # (the compose file is workspace-specific, so no need to touch it here)

    exit 0
fi

# --- Compute container name hash (only needed for normal operation) ---
myhash=$(echo -n "$PWD" | openssl dgst -sha256 | sed 's/^.* //')
export __TCD_SHA_DIR=$myhash

# --- Continue with normal operation only if not in clean mode ---

# --- Ensure .tcd directory exists ---
if [ ! -d "$HOME/.tcd" ]; then
    mkdir -p "$HOME/.tcd"
fi

__TCD_BASH_COMPLETION_FILE="$HOME/.tcd/torizon-dev-completion.bash"

# Download docker-compose.yml if missing (vars are now set above)
if [ ! -f "$__TCD_COMPOSE_FILE" ]; then
    set +e
    wget -q "https://raw.githubusercontent.com/$__TCD_APOLLOX_REPO/$__TCD_APOLLOX_BRANCH/scripts/container/docker-compose.yml" -O "$__TCD_COMPOSE_FILE" 2>/dev/null || { echo "Warning: Could not download docker-compose.yml"; exit 1; }
    set -e
fi

# Download bash completion if missing (local copy)
if [ ! -f "$__TCD_BASH_COMPLETION_FILE" ]; then
    wget -q "https://raw.githubusercontent.com/$__TCD_APOLLOX_REPO/$__TCD_APOLLOX_BRANCH/scripts/bash/tcd-completion.bash" -O "$__TCD_BASH_COMPLETION_FILE" 2>/dev/null || true
fi

# --- Container management (mirrors original torizon-dev function) ---
if [ "$(docker ps -aq -f name="torizon-dev-$myhash")" ]; then
    # Container exists — check if it's running
    CONT_STATUS=$(docker inspect --format='{{.State.Status}}' "torizon-dev-$myhash" 2>/dev/null || echo "unknown")
    if [ "$CONT_STATUS" != "running" ]; then
        docker start "torizon-dev-$myhash" > /dev/null 2>&1
        echo "Container 'torizon-dev-$myhash' was stopped, starting it..."
    fi
else
    # Create a new container for this workspace
    _workspace=$(basename "$PWD")
    echo "Configuring environment for the [$_workspace] workspace ..."
    echo "Please wait ..."

    docker compose -f "$__TCD_COMPOSE_FILE" run \
        --entrypoint /bin/bash \
        --name "torizon-dev-$myhash" \
        --user root \
        -d torizon-dev > /dev/null 2>&1 || { echo "Error: Failed to create container"; exit 1; }

    # Set up user/group ownership inside the container
    docker exec -it --user root "torizon-dev-$myhash" usermod -u $__TCD_UUID torizon
    docker exec -it --user root "torizon-dev-$myhash" groupadd -g $__TCD_DGID docker 2>/dev/null || true
    docker exec -it --user root "torizon-dev-$myhash" usermod -aG $__TCD_DGID torizon 2>/dev/null || true
    docker exec -it --user root "torizon-dev-$myhash" chown -R torizon:torizon /home/torizon
fi

# --- Execute zygote with any passed arguments ---
docker exec -it --user torizon "torizon-dev-$myhash" zygote "$@"
ENDOFSCRIPT

$SUDO install -m 0755 "$__TCD_TMP_BIN" "$TARGET_BIN"
echo "Installed torizon-dev script: $TARGET_BIN (system-wide)"

# Older versions installed a per-user copy in ~/.local/bin, which comes first
# in PATH and would shadow the system-wide one. Remove it if it is ours.
__TCD_OLD_BIN="$HOME/.local/bin/torizon-dev"
if [ -f "$__TCD_OLD_BIN" ] && grep -q "standalone wrapper for Torizon dev environment" "$__TCD_OLD_BIN"; then
    rm -f "$__TCD_OLD_BIN"
    echo "Removed old per-user torizon-dev: $__TCD_OLD_BIN"
fi
hash -r 2>/dev/null || true

# Install (or refresh) completion in the system-wide location
if [ -f "$__TCD_BASH_COMPLETION_FILE" ]; then
    $SUDO install -m 0644 "$__TCD_BASH_COMPLETION_FILE" "$TARGET_COMPLETION_FILE" || true
fi

echo ""
echo "✅ Torizon dev environment installed!"
echo "   Command:  torizon-dev"
echo "   Completions: added to /usr/share/bash-completion/completions/"
echo ""
echo "Next time you open a Phobos project, just run:"
echo "    torizon-dev          # enters the dev container with zygote"
echo ""
echo "To remove all torizon-dev containers:"
echo "    torizon-dev --clean        # asks before removing running containers"
echo "    torizon-dev --clean --yes  # removes all without asking"
