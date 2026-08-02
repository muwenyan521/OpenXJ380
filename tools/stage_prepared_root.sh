#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <prepared-root> <image-root>" >&2
    exit 2
fi

src_root=${1%/}
dst_root=${2%/}

if [ ! -d "$src_root" ]; then
    echo "prepared root not found: $src_root" >&2
    exit 1
fi

stage_entry()
{
    src=$1
    rel=${src#"$src_root"/}
    dst=$dst_root/$rel

    case $rel in
    Bf|Bf/*|var/cache/xbps|var/cache/xbps/*)
        return 0
        ;;
    esac

    if [ -L "$src" ]; then
        if [ -d "$dst" ] && [ ! -L "$dst" ]; then
            return 0
        fi
        rm -rf "$dst"
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
        return 0
    fi

    if [ -d "$src" ]; then
        if [ -L "$dst" ] || { [ -e "$dst" ] && [ ! -d "$dst" ]; }; then
            rm -rf "$dst"
        fi
        mkdir -p "$dst"
        return 0
    fi

    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

find "$src_root" -mindepth 1 | while IFS= read -r src; do
    stage_entry "$src"
done

sanitize_xbps_keys_for_fat()
{
    for key in "$dst_root"/var/db/xbps/keys/*:*; do
        [ -e "$key" ] || continue
        dir=$(dirname "$key")
        base=$(basename "$key")
        safe=$(printf '%s' "$base" | tr ':<>"\\|?*' '_')
        if [ "$base" != "$safe" ]; then
            mv -f "$key" "$dir/$safe"
        fi
    done
}

sanitize_xbps_keys_for_fat

mkdir -p "$dst_root/bin" "$dst_root/usr/bin"

link_bin_tool()
{
    tool=$1
    target=$2
    dst=$dst_root/bin/$tool

    if [ ! -x "$dst_root/$target" ]; then
        return 0
    fi
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        return 0
    fi

    rm -f "$dst"
    ln -s "../$target" "$dst"
}

if [ -x "$dst_root/usr/bin/dash" ]; then
    link_bin_tool sh usr/bin/dash
elif [ -x "$dst_root/usr/bin/bash" ]; then
    link_bin_tool sh usr/bin/bash
fi

for tool in \
    awk basename cat chmod chgrp chown cp cut date dd df dirname du echo env false find grep \
    gunzip gzip head install ln ls mkdir mv printf pwd readlink realpath rm rmdir sed sh sleep \
    sort stat sync tail tar test touch tr true uname uniq wc which xargs
do
    [ "$tool" = "sh" ] && continue
    link_bin_tool "$tool" "usr/bin/$tool"
done
