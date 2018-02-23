#!/usr/bin/env bash

THIS_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
TMP_GIT_CONFIG_FILE="$THIS_DIR/.tmp_git_config"

GIT_NAME="$(git config --global --list | grep 'user.name' | cut -d'=' -f2-)"
GIT_EMAIL="$(git config --global --list | grep 'user.email' | cut -d'=' -f2-)"

echo "[user]" > "$TMP_GIT_CONFIG_FILE"
echo "    name = $GIT_NAME" >> "$TMP_GIT_CONFIG_FILE"
echo "    email = $GIT_EMAIL" >> "$TMP_GIT_CONFIG_FILE"

cleanup() {
    rm "$TMP_GIT_CONFIG_FILE" || true
}

trap cleanup SIGINT

docker run \
    -it \
    --rm \
    --name hacktributor \
    -v "$(pwd)":/hacktributor \
    -v "$TMP_GIT_CONFIG_FILE":/root/.gitconfig \
    milesrichardson/hacktributor "$@"

cleanup
