#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <image-root> <elf>..." >&2
    exit 2
fi

root=$1
shift

copy_one()
{
    src=$1

    case "$src" in
        /*) ;;
        *) return 0 ;;
    esac

    if [ ! -e "$src" ]; then
        return 0
    fi

    dst=$root$src
    mkdir -p "$(dirname "$dst")"
    cp -aL "$src" "$dst"
}

for elf in "$@"; do
    if ! command -v ldd >/dev/null 2>&1; then
        exit 0
    fi

    if ! ldd "$elf" >/dev/null 2>&1; then
        continue
    fi

    ldd "$elf" | while IFS= read -r line; do
        set -- $line
        case "$line" in
            *"=>"*)
                copy_one "$3"
                ;;
            /*)
                copy_one "$1"
                ;;
        esac
    done
done
