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
export __TCD_APOLLOX_REPO="gaiaBuildSystem/vscode-phobos-templates"
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
export __TCD_APOLLOX_REPO="gaiaBuildSystem/vscode-phobos-templates"
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

# --- Update mode: refresh compose file and pull the latest image ---
if [[ "${1:-}" == "--update" || "${1:-}" == "-u" ]]; then
    echo "=== Updating Torizon dev container image ==="

    mkdir -p "$HOME/.tcd"

    # The compose template interpolates this, so it must be set even though
    # we are not creating a container here
    export __TCD_SHA_DIR=$(echo -n "$PWD" | openssl dgst -sha256 | sed 's/^.* //')

    # Refresh docker-compose.yml, it may point to a new image tag
    __TCD_COMPOSE_TMP="$(mktemp)"
    if wget -q "https://raw.githubusercontent.com/$__TCD_APOLLOX_REPO/$__TCD_APOLLOX_BRANCH/scripts/container/docker-compose.yml" -O "$__TCD_COMPOSE_TMP" 2>/dev/null; then
        mv "$__TCD_COMPOSE_TMP" "$__TCD_COMPOSE_FILE"
        echo "Refreshed $__TCD_COMPOSE_FILE"
    else
        rm -f "$__TCD_COMPOSE_TMP"
        if [ ! -f "$__TCD_COMPOSE_FILE" ]; then
            echo "Error: Could not download docker-compose.yml"
            exit 1
        fi
        echo "Warning: Could not refresh docker-compose.yml, using the existing one"
    fi

    echo "Pulling torizon-dev image ..."
    docker compose -f "$__TCD_COMPOSE_FILE" pull torizon-dev || { echo "Error: Failed to pull the torizon-dev image"; exit 1; }

    # Existing containers keep running the image they were created from,
    # so point out the ones that are now outdated
    __TCD_IMAGE=$(docker compose -f "$__TCD_COMPOSE_FILE" config --images torizon-dev 2>/dev/null | head -n1)
    __TCD_IMAGE_ID=$(docker image inspect --format='{{.Id}}' "$__TCD_IMAGE" 2>/dev/null || true)
    OUTDATED=""
    while IFS= read -r cid; do
        [ -z "$cid" ] && continue
        CONT_IMAGE_ID=$(docker inspect --format='{{.Image}}' "$cid" 2>/dev/null || true)
        if [ -n "$__TCD_IMAGE_ID" ] && [ "$CONT_IMAGE_ID" != "$__TCD_IMAGE_ID" ]; then
            OUTDATED="$OUTDATED $(docker inspect --format='{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')"
        fi
    done < <(docker ps -aq -f name="torizon-dev-[a-f0-9]+" 2>/dev/null)

    echo ""
    echo "✅ torizon-dev image is up to date."
    if [ -n "$OUTDATED" ]; then
        echo ""
        echo "⚠️  The following containers still use the previous image:"
        for name in $OUTDATED; do
            echo "  - $name"
        done
        echo ""
        echo "To recreate them with the new image, run:"
        echo "  torizon-dev --clean      # then run torizon-dev again in each workspace"
    fi

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

# --- WSL support ---
# On WSL the container must see the Windows drives and the WSL interop
# socket so Windows binaries (powershell.exe, cmd.exe, ...) can be run from
# inside it, and the Windows directories must be in its PATH.
__TCD_COMPOSE_ARGS=(-f "$__TCD_COMPOSE_FILE")
__TCD_IS_WSL=false
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    __TCD_IS_WSL=true
fi

if [ "$__TCD_IS_WSL" = true ]; then
    # Windows drive mount points (drvfs), e.g. /mnt/c, /mnt/d ...
    __TCD_WSL_MOUNTS=$(awk '$3 == "drvfs" || ($3 == "9p" && $4 ~ /aname=drvfs/) { print $2 }' /proc/mounts 2>/dev/null | sort -u)

    # The interop socket is per WSL session; if the variable is not set
    # (e.g. shell not started by WSL) use the most recent socket
    if [ -z "${WSL_INTEROP:-}" ]; then
        WSL_INTEROP=$(ls -t /run/WSL/*_interop 2>/dev/null | head -n1)
    fi
    export WSL_INTEROP

    # Compose override with the WSL specific mounts. /mnt is already
    # mounted by the base compose file, so only add drives outside of it
    __TCD_WSL_COMPOSE_FILE="$HOME/.tcd/docker-compose.wsl.yml"
    {
        echo "services:"
        echo "  torizon-dev:"
        echo "    environment:"
        echo "      - WSL_INTEROP=\${WSL_INTEROP}"
        echo "    volumes:"
        echo "      - /run/WSL:/run/WSL"
        [ -d /usr/lib/wsl ] && echo "      - /usr/lib/wsl:/usr/lib/wsl:ro"
        for mp in $__TCD_WSL_MOUNTS; do
            case "$mp" in
                /mnt|/mnt/*) ;;
                *) echo "      - \"$mp:$mp\"" ;;
            esac
        done
    } > "$__TCD_WSL_COMPOSE_FILE"
    __TCD_COMPOSE_ARGS+=(-f "$__TCD_WSL_COMPOSE_FILE")

    # Windows PATH entries: the ones from the host PATH that live on a
    # Windows drive, plus the Windows system directories as a fallback
    __TCD_WSL_PATH=""
    __tcd_add_wsl_path() {
        case ":$__TCD_WSL_PATH:" in
            *":$1:"*) ;;
            *) __TCD_WSL_PATH="${__TCD_WSL_PATH:+$__TCD_WSL_PATH:}$1" ;;
        esac
    }
    IFS=':' read -r -a __tcd_host_path <<< "$PATH"
    for d in "${__tcd_host_path[@]}"; do
        for mp in $__TCD_WSL_MOUNTS; do
            case "$d" in
                "$mp"|"$mp"/*) __tcd_add_wsl_path "$d"; break ;;
            esac
        done
    done
    for mp in $__TCD_WSL_MOUNTS; do
        if [ -d "$mp/Windows/System32" ]; then
            __tcd_add_wsl_path "$mp/Windows/System32"
            __tcd_add_wsl_path "$mp/Windows"
            __tcd_add_wsl_path "$mp/Windows/System32/WindowsPowerShell/v1.0"
        fi
    done
fi

# --- Container management (mirrors original torizon-dev function) ---
if [ "$(docker ps -aq -f name="torizon-dev-$myhash")" ]; then
    # Container exists — check if it's running
    CONT_STATUS=$(docker inspect --format='{{.State.Status}}' "torizon-dev-$myhash" 2>/dev/null || echo "unknown")
    if [ "$CONT_STATUS" != "running" ]; then
        docker start "torizon-dev-$myhash" > /dev/null 2>&1
        echo "Container 'torizon-dev-$myhash' was stopped, starting it..."
    fi

    # Containers created before WSL support was added lack the interop mount
    if [ "$__TCD_IS_WSL" = true ] && \
        ! docker inspect --format='{{range .Mounts}}{{.Destination}} {{end}}' "torizon-dev-$myhash" 2>/dev/null | grep -qw "/run/WSL"; then
        echo "⚠️  This container was created without the WSL mounts, Windows binaries will not work."
        echo "   Recreate it with:  torizon-dev --clean && torizon-dev"
    fi
else
    # Create a new container for this workspace
    _workspace=$(basename "$PWD")
    echo "Configuring environment for the [$_workspace] workspace ..."
    echo "Please wait ..."

    docker compose "${__TCD_COMPOSE_ARGS[@]}" run \
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
if [ "$__TCD_IS_WSL" = true ]; then
    # WSL_INTEROP changes between WSL sessions, so pass it on every exec, and
    # append the Windows PATH entries to the container PATH.
    # Windows binaries translate the current directory to a Windows path and
    # fail with "Invalid argument" if it does not exist on the WSL host (e.g.
    # /workspace), so start in the workspace host path, which is also mounted
    docker exec -it --user torizon -w "$PWD" \
        -e "WSL_INTEROP=$WSL_INTEROP" \
        -e "__TCD_WSL_PATH=$__TCD_WSL_PATH" \
        "torizon-dev-$myhash" \
        bash -c 'if [ -n "$__TCD_WSL_PATH" ]; then export PATH="$PATH:$__TCD_WSL_PATH"; fi; unset __TCD_WSL_PATH; exec zygote "$@"' zygote "$@"
else
    docker exec -it --user torizon "torizon-dev-$myhash" zygote "$@"
fi
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
echo ""
echo "To update the torizon-dev container image:"
echo "    torizon-dev --update"
