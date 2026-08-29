#!/bin/bash

echo "🐚 SETUP XONSH"

_XONSH_TARGET="0.23.7"

function _check_xonsh_update {
    # make sure we are also updating to the target version of xonsh
    _XONSH_CURRENT=$(pipx list --short 2>/dev/null | grep "^xonsh " | awk '{print $2}')

    if [ "$_XONSH_CURRENT" = "$_XONSH_TARGET" ]; then
        echo "xonsh $_XONSH_TARGET already installed, skipping"
    else
        pipx install --force xonsh==$_XONSH_TARGET
    fi
}

function _check_xonsh_global {
    # we need to check if we need to run the setup as root
    # at the first time we should need to symlink the xonsh to the /usr/bin
    # read the /usr/bin/xonsh and check if it is linked to
    # the $HOME/.local/pipx/venvs/xonsh/bin/xonsh, if not we need to run with sudo
    local local_xonsh="$HOME/.local/pipx/venvs/xonsh/bin/xonsh"
    local global_xonsh="/usr/bin/xonsh"

    # get the local xonsh by the real path from $HOME/.local/bin/xonsh
    local_xonsh="$(readlink -f "$HOME/.local/bin/xonsh")"

    if [ ! -f "$local_xonsh" ]; then
        echo "Expected local xonsh at $local_xonsh but it was not found."
        return 1
    fi

    if [ -e "$global_xonsh" ] && [ "$(readlink -f "$global_xonsh")" = "$local_xonsh" ]; then
        return 0
    fi

    if [ -e "$global_xonsh" ]; then
        echo "The xonsh in $global_xonsh is not linked to $local_xonsh, trying to relink ..."
    else
        echo "$global_xonsh does not exist, creating global xonsh link ..."
    fi

    if [ -z "${PSSWD}" ]; then
        echo "Insufficient permissions to create $global_xonsh and PSSWD is not set."
        return 1
    fi

    if ! printf '%s\n' "$PSSWD" | sudo -S ln -sf "$local_xonsh" "$global_xonsh"; then
        echo "Failed to create $global_xonsh using sudo. Check password and sudo permissions."
        return 1
    fi

    return 0
}

function _do_injections {
    pipx inject xonsh distro
    pipx inject xonsh shtab
    pipx inject xonsh pyyaml
    pipx inject xonsh psutil
    pipx inject xonsh ruamel.yaml
    pipx inject xonsh torizon-templates-utils
    pipx inject xonsh GitPython
    pipx inject xonsh python-lsp-server
    pipx inject xonsh pylsp-rope
}

function _setup_torizon_dev_symlink {
    local zygote_path="$(realpath "$(dirname "$(readlink -f "$0")")/../zygote.xsh")"
    local target_symlink="/usr/bin/torizon-dev"

    if [ ! -f "$zygote_path" ]; then
        echo "Error: $zygote_path not found."
        return 1
    fi

    if [ -e "$target_symlink" ] && [ "$(readlink -f "$target_symlink")" = "$zygote_path" ]; then
        return 0
    fi

    if [ -e "$target_symlink" ]; then
        echo "The symlink $target_symlink is not pointing to $zygote_path, trying to relink ..."
    else
        echo "$target_symlink does not exist, creating global symlink ..."
    fi

    if [ -z "${PSSWD}" ]; then
        echo "Insufficient permissions to create $target_symlink and PSSWD is not set."
        return 1
    fi

    if ! printf '%s\n' "$PSSWD" | sudo -S ln -sf "$zygote_path" "$target_symlink"; then
        echo "Failed to create $target_symlink using sudo. Check password and sudo permissions."
        return 1
    fi
}

function _install_bash_completion {
    local completion_file="$(realpath "$(dirname "$(readlink -f "$0")")/tcd-completion.bash")"
    local target_completion="/usr/share/bash-completion/completions/tcd"

    if [ ! -f "$completion_file" ]; then
        echo "Error: $completion_file not found."
        return 1
    fi

    if [ -e "$target_completion" ] && [ "$(readlink -f "$target_completion")" = "$completion_file" ]; then
        return 0
    fi

    if [ -e "$target_completion" ]; then
        echo "The symlink $target_completion is not pointing to $completion_file, trying to relink ..."
    else
        echo "$target_completion does not exist, creating global bash completion symlink ..."
    fi

    if [ -z "${PSSWD}" ]; then
        echo "Insufficient permissions to create $target_completion and PSSWD is not set."
        return 1
    fi

    if ! printf '%s\n' "$PSSWD" | sudo -S ln -sf "$completion_file" "$target_completion"; then
        echo "Failed to create $target_completion using sudo. Check password and sudo permissions."
        return 1
    fi
}

function _install_node_dependencies {
    local node_dir="$(realpath "$(dirname "$(readlink -f "$0")")/../node")"

    if [ ! -d "$node_dir" ]; then
        echo "Error: Node directory $node_dir not found."
        return 1
    fi

    if [ -d "$node_dir/node_modules" ]; then
        echo "Node dependencies already exist in $node_dir, skipping npm install..."
        return 0
    fi

    echo "Installing Node dependencies in $node_dir..."
    (cd "$node_dir" && npm install)

    if [ $? -ne 0 ]; then
        echo "Failed to install Node dependencies."
        return 1
    fi

    echo "Node dependencies installed successfully ✅"
}

# check if xonsh is on $HOME/.local/bin
if [ -f "$HOME/.local/bin/xonsh" ]; then
    _check_xonsh_update
    echo "updating torizon-templates-utils ..."

    VARS_FILE="./.conf/repo-vars.json"

    if [ -f "$VARS_FILE" ]; then
        echo "Found repo-vars.json, attempting to use custom source..."

        repo=$(jq -r '.repo // empty' "$VARS_FILE")
        branch=$(jq -r '.branch // empty' "$VARS_FILE")
        tag_or_hash=$(jq -r '.tag // empty' "$VARS_FILE")

        if [ -z "$repo" ] || { [ -z "$branch" ] && [ -z "$tag_or_hash" ]; }; then
            echo "Invalid or incomplete config, falling back to package..."
        else
            if [ -e "$repo" ]; then
                repo="file://$(realpath "$repo")"
            fi

            if [ -n "$tag_or_hash" ]; then
                ref="$tag_or_hash"
            else
                ref="$branch"
            fi

            pipx runpip xonsh install --force-reinstall \
                "git+${repo}@${ref}#subdirectory=scripts/utils/pip"

            echo "Installed from custom repo ✅"
        fi
    else
        # Fallback to package if no repo or branch/tag set
        echo "Using published package..."
        pipx runpip xonsh install --upgrade torizon-templates-utils
    fi

    _do_injections
    _setup_torizon_dev_symlink
    _install_bash_completion
    _install_node_dependencies

    # re-check if we need to link xonsh globally
    if ! _check_xonsh_global; then
        exit 1
    fi

    echo "all ok ✅"
    exit 0
fi

# fail as soon as a command fails, and return the exit status
set -e

pipx install xonsh==$_XONSH_TARGET
pipx ensurepath

_do_injections
_setup_torizon_dev_symlink
_install_bash_completion
_install_node_dependencies

# add xonsh to the path if not already present
if ! grep -q "export PATH=\$PATH:\$HOME/.local/bin" ~/.bashrc; then
    echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bashrc
fi

# also for .xonshrc itself
if [ ! -f ~/.xonshrc ]; then
    touch ~/.xonshrc
fi
if ! grep -q "\$HOME/.local/bin" ~/.xonshrc; then
    echo "\$PATH.insert(0, '$HOME/.local/bin')" >> ~/.xonshrc
fi

# also make sure the xonsh is linked to the /usr/bin
if ! _check_xonsh_global; then
    exit 1
fi
