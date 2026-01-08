#!/bin/sh
printf '\033c\033]0;%s\a' Networking
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Networking.x86_64" "$@"
