#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <image-root>" >&2
    exit 2
fi

root=$1
busybox=${APP_BUSYBOX:-resources/apps/busybox}
image_busybox=${IMAGE_BUSYBOX:-1}
repo=${XBPS_REPOSITORY:-http://mirrors.tuna.tsinghua.edu.cn/voidlinux/current}
bf_dir=${BF_DIR:-Bf}
host_arch=${XBPS_STATIC_ARCH:-$(uname -m)}
static_tarball=${XBPS_STATIC_TARBALL:-$bf_dir/xbps-static-latest.$host_arch-musl.tar.xz}
static_uri=${XBPS_STATIC_URI:-http://repo-default.voidlinux.org/static/xbps-static-latest.$host_arch-musl.tar.xz}
triggers_dir=${XBPS_TRIGGERS_DIR:-$bf_dir/xbps-triggers}
triggers_pkg=${XBPS_TRIGGERS_PKG:-}

find_tool()
{
    tool=$1
    for path in \
        "$bf_dir/usr/bin/$tool" \
        "$bf_dir/bin/$tool" \
        "$bf_dir/$tool"
    do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

copy_to()
{
    src=$1
    dst=$2
    [ -e "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    cp -aL "$src" "$dst"
}

install_busybox_applet()
{
    dst=$1
    app=$2
    mkdir -p "$(dirname "$root$dst")"
    if [ -e "$root$dst" ]; then
        return
    fi
    if [ "$dst" = "/bin/sh" ]; then
        cp -aL "$busybox" "$root$dst"
        return
    fi

    {
        printf '%s\n' '#!/bin/sh'
        printf 'exec /apps/busybox %s "$@"\n' "$app"
    } > "$root$dst"
    chmod 755 "$root$dst"
}

stage_xbps_dirs()
{
    mkdir -p \
        "$root/etc/xbps.d" \
        "$root/usr/share/xbps.d" \
        "$root/usr/bin" \
        "$root/usr/libexec" \
        "$root/var/cache/xbps" \
        "$root/var/db/xbps/keys" \
        "$root/var/db/xbps/metadata"
}

stage_xbps_config()
{
    for dir in "$root/usr/share/xbps.d" "$root/etc/xbps.d"; do
        mkdir -p "$dir"
        conf="$dir/00-repository-main.conf"
        printf 'repository=%s\n' "$repo" > "$conf"
    done

    for conf in "$root"/usr/share/xbps.d/*-repository-*.conf \
                "$root"/usr/share/xbps.d/*repository*.conf \
                "$root"/etc/xbps.d/*-repository-*.conf \
                "$root"/etc/xbps.d/*repository*.conf; do
        [ -f "$conf" ] || continue
        sed -i \
            -e 's|https://repo-default.voidlinux.org|http://mirrors.tuna.tsinghua.edu.cn/voidlinux|g' \
            -e 's|https://alpha.de.repo.voidlinux.org|http://mirrors.tuna.tsinghua.edu.cn/voidlinux|g' \
            "$conf"
    done
}

stage_xbps_tools()
{
    required="xbps-install xbps-query xbps-remove xbps-uhelper"
    optional="xbps-rindex xbps-reconfigure xbps-alternatives xbps-pkgdb"

    for tool in $required; do
        if ! src=$(find_tool "$tool"); then
            echo "missing $tool in $bf_dir" >&2
            echo "preferred: download $static_uri to $static_tarball" >&2
            exit 1
        fi
        copy_to "$src" "$root/usr/bin/$tool"
    done

    for tool in $optional; do
        if src=$(find_tool "$tool"); then
            copy_to "$src" "$root/usr/bin/$tool"
        fi
    done
}

stage_xbps_static_tarball()
{
    if [ ! -f "$static_tarball" ]; then
        echo "missing xbps static tarball: $static_tarball" >&2
        echo "download it with:" >&2
        echo "  mkdir -p $bf_dir" >&2
        echo "  curl -fL '$static_uri' -o '$static_tarball'" >&2
        return 1
    fi

    tar -xJf "$static_tarball" -C "$root" ./usr/bin ./var/db/xbps/keys

    for tool in xbps-install xbps-query xbps-remove xbps-uhelper \
        xbps-rindex xbps-reconfigure xbps-alternatives xbps-pkgdb \
        xbps-fetch xbps-digest; do
        if [ -x "$root/usr/bin/$tool.static" ]; then
            rm -f "$root/usr/bin/$tool"
            cp -aL "$root/usr/bin/$tool.static" "$root/usr/bin/$tool"
        fi
    done
    return 0
}

sanitize_xbps_keys_for_fat()
{
    for key in "$root"/var/db/xbps/keys/*:*; do
        [ -e "$key" ] || continue
        dir=$(dirname "$key")
        base=$(basename "$key")
        safe=$(printf '%s' "$base" | tr ':<>"\\|?*' '_')
        if [ "$base" != "$safe" ]; then
            mv -f "$key" "$dir/$safe"
        fi
    done
}

stage_xbps_triggers()
{
    if [ -d "$triggers_dir" ]; then
        mkdir -p "$root/usr/libexec"
        cp -aL "$triggers_dir" "$root/usr/libexec/xbps-triggers"
        return
    fi

    if [ -z "$triggers_pkg" ]; then
        for pkg in "$bf_dir"/xbps-triggers-*.xbps; do
            [ -f "$pkg" ] || continue
            triggers_pkg=$pkg
            break
        done
    fi

    if [ -n "$triggers_pkg" ] && [ -f "$triggers_pkg" ]; then
        tar --zstd -xf "$triggers_pkg" -C "$root" ./usr/libexec/xbps-triggers
        return
    fi

    echo "missing xbps triggers" >&2
    echo "place triggers in $triggers_dir or put xbps-triggers-*.xbps under $bf_dir" >&2
    exit 1
}

stage_busybox_links()
{
    if [ "$image_busybox" != "1" ]; then
        echo "skip busybox applet staging (IMAGE_BUSYBOX=$image_busybox)"
        return
    fi

    if [ -e "$busybox" ]; then
        copy_to "$busybox" "$root/apps/busybox"
        for app in \
            sh ash cat chmod chown chgrp cp date echo env false grep install ln ls mkdir mv printf pwd \
            readlink rm rmdir sed sort stat sync test touch tr true uname uniq xargs awk
        do
            install_busybox_applet "/bin/$app" "$app"
            install_busybox_applet "/usr/bin/$app" "$app"
        done
    fi
}

stage_xbps_dirs
if ! stage_xbps_static_tarball; then
    stage_xbps_tools
fi
stage_xbps_config
sanitize_xbps_keys_for_fat
stage_xbps_triggers
stage_busybox_links
