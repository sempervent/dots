#!/usr/bin/env bash

symlink_files() {
    src_dir="$1"
    target_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        echo "Source directory not found: $src_dir"
        return 1
    fi

    if [[ ! -d "$target_dir" ]]; then
        echo "Target directory not found: $target_dir, creating"
        mkdir -p "$target_dir"
    fi

    find "$src_dir" -type f -exec bash -c 'ln -s "{}" "$0/$(basename "{}")"' "$target_dir" \;
    echo "Symlinks created in $target_dir"
}


symlink_files "${HOME}/dots/ranger/" "${HOME}/.config/ranger"
