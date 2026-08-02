#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <image-root>" >&2
    exit 2
fi

root=$1
toolchain=${IMAGE_TOOLCHAIN:-clang}
host_gcc=${HOST_GCC:-gcc}
stage_deps=${STAGE_ELF_DEPS:-tools/stage_elf_deps.sh}

find_real()
{
    tool=$1
    path=$(command -v "$tool" 2>/dev/null || true)
    if [ -z "$path" ]; then
        return 1
    fi
    readlink -f "$path"
}

require_real()
{
    tool=$1
    if ! find_real "$tool"; then
        echo "missing required host tool: $tool" >&2
        exit 1
    fi
}

copy_to()
{
    copy_src=$1
    copy_dst=$2
    [ -e "$copy_src" ] || return 0
    mkdir -p "$(dirname "$copy_dst")"
    cp -aL "$copy_src" "$copy_dst"
}

copy_same_path()
{
    same_src=$1
    [ -e "$same_src" ] || return 0
    copy_to "$same_src" "$root$same_src"
}

copy_to_dir()
{
    dir_src=$1
    dir_dst=$2
    [ -e "$dir_src" ] || return 0
    mkdir -p "$dir_dst"
    cp -aL "$dir_src" "$dir_dst/$(basename "$dir_src")"
}

copy_ldd_named_deps_to_dir()
{
    dir=$1
    shift
    mkdir -p "$dir"
    for elf in "$@"; do
        [ -e "$elf" ] || continue
        ldd "$elf" 2>/dev/null | while IFS= read -r line; do
            set -- $line
            case "$line" in
                *"=>"*)
                    [ -n "${3:-}" ] || continue
                    case "$1" in
                        libLLVM.so.*|libclang-cpp.so.*)
                            copy_to "$3" "$dir/$1"
                            ;;
                    esac
                    ;;
            esac
        done
    done
}

copy_glob_to_dir()
{
    dir=$1
    shift
    mkdir -p "$dir"
    for pattern in "$@"; do
        for f in $pattern; do
            [ -e "$f" ] || continue
            cp -aL "$f" "$dir/"
        done
    done
}

stage_ldd_deps()
{
    if [ -x "$stage_deps" ]; then
        "$stage_deps" "$root" "$@"
    elif [ -f "$stage_deps" ]; then
        sh "$stage_deps" "$root" "$@"
    fi
}

stage_non_llvm_ldd_deps()
{
    for elf in "$@"; do
        [ -e "$elf" ] || continue
        ldd "$elf" 2>/dev/null | while IFS= read -r line; do
            set -- $line
            case "$line" in
                *"=>"*)
                    case "${1:-}" in
                        libLLVM.so.*|libclang-cpp.so.*)
                            continue
                            ;;
                    esac
                    [ -n "${3:-}" ] || continue
                    copy_same_path "$3"
                    ;;
                /*)
                    copy_same_path "$1"
                    ;;
            esac
        done
    done
}

gcc_triple()
{
    "$host_gcc" -dumpmachine 2>/dev/null
}

gcc_version()
{
    "$host_gcc" -dumpversion 2>/dev/null
}

gcc_libdir()
{
    libgcc=$("$host_gcc" -print-file-name=libgcc.a 2>/dev/null)
    dirname "$libgcc"
}

gcc_libexecdir()
{
    cc1=$("$host_gcc" -print-prog-name=cc1 2>/dev/null)
    dirname "$cc1"
}

stage_glibc_devel()
{
    triple=$1

    rm -rf "$root/usr/include"
    mkdir -p "$root/usr/include" "$root/usr/lib/$triple" "$root/lib/$triple"
    cp -a /usr/include/. "$root/usr/include/"

    copy_glob_to_dir "$root/usr/lib/$triple" \
        "/usr/lib/$triple/crt*.o" \
        "/usr/lib/$triple/Scrt*.o" \
        "/usr/lib/$triple/Mcrt*.o" \
        "/usr/lib/$triple/libc.so" \
        "/usr/lib/$triple/libc_nonshared.a" \
        "/usr/lib/$triple/libm.so" \
        "/usr/lib/$triple/libmvec_nonshared.a" \
        "/usr/lib/$triple/libpthread_nonshared.a" \
        "/usr/lib/$triple/libstdc++.so*"

    copy_glob_to_dir "$root/lib/$triple" \
        "/lib/$triple/crt*.o" \
        "/lib/$triple/Scrt*.o" \
        "/lib/$triple/Mcrt*.o" \
        "/lib/$triple/libbfd-*.so" \
        "/lib/$triple/libctf.so*" \
        "/lib/$triple/libjansson.so*" \
        "/lib/$triple/libsframe.so*" \
        "/lib/$triple/libz.so*" \
        "/lib/$triple/libzstd.so*" \
        "/lib/$triple/libc.so*" \
        "/lib/$triple/libm.so*" \
        "/lib/$triple/libgcc_s.so*" \
        "/lib/$triple/libstdc++.so*"
}

stage_minimal_gcc_runtime()
{
    triple=$1
    version=$2
    libdir=$(gcc_libdir)
    dst="$root/usr/lib/gcc/$triple/$version"

    mkdir -p "$dst"
    copy_glob_to_dir "$dst" \
        "$libdir/crtbegin*.o" \
        "$libdir/crtend*.o" \
        "$libdir/libgcc.a" \
        "$libdir/libgcc_eh.a" \
        "$libdir/libgcc_s.so*" \
        "$libdir/libstdc++.so*" \
        "$libdir/libsupc++.a"
}

stage_binutils()
{
    triple=$1
    as_path=$(command -v "$triple-as" 2>/dev/null || command -v as 2>/dev/null || true)
    ld_path=$(command -v "$triple-ld.bfd" 2>/dev/null || command -v "$triple-ld" 2>/dev/null || command -v ld.bfd 2>/dev/null || command -v ld 2>/dev/null || true)

    [ -n "$as_path" ] || { echo "missing required host assembler" >&2; exit 1; }
    [ -n "$ld_path" ] || { echo "missing required host linker" >&2; exit 1; }

    as_real=$(readlink -f "$as_path")
    ld_real=$(readlink -f "$ld_path")
    mkdir -p "$root/usr/bin"
    copy_to "$as_real" "$root/usr/bin/$(basename "$as_real")"
    copy_to "$as_real" "$root/usr/bin/as"
    copy_to "$ld_real" "$root/usr/bin/$(basename "$ld_real")"
    copy_to "$ld_real" "$root/usr/bin/$triple-ld"
    copy_to "$ld_real" "$root/usr/bin/ld"
    stage_ldd_deps "$as_real" "$ld_real"
}

stage_gcc_toolchain()
{
    triple=$(gcc_triple)
    version=$(gcc_version)
    gcc_real=$(require_real "$host_gcc")
    gcc_name=$(basename "$gcc_real")
    libdir=$(gcc_libdir)
    libexecdir=$(gcc_libexecdir)

    [ -n "$triple" ] && [ -n "$version" ] || { echo "cannot detect host gcc target/version" >&2; exit 1; }
    [ -d "$libdir" ] || { echo "cannot detect host gcc libdir" >&2; exit 1; }
    [ -d "$libexecdir" ] || { echo "cannot detect host gcc libexecdir" >&2; exit 1; }

    mkdir -p "$root/usr/bin" "$root/usr/lib/gcc/$triple" "$root/usr/libexec/gcc/$triple"
    copy_to "$gcc_real" "$root/usr/bin/$gcc_name"
    copy_to "$gcc_real" "$root/usr/bin/gcc-$version"
    copy_to "$gcc_real" "$root/usr/bin/gcc"
    copy_to "$gcc_real" "$root/usr/bin/cc"
    cp -aL "$libdir" "$root/usr/lib/gcc/$triple/"
    cp -aL "$libexecdir" "$root/usr/libexec/gcc/$triple/"

    stage_binutils "$triple"
    stage_glibc_devel "$triple"
    stage_ldd_deps "$gcc_real" "$libexecdir/cc1" "$libexecdir/collect2"
}

stage_clang_resource()
{
    clang=$1
    resource_dir=$("$clang" --print-resource-dir 2>/dev/null)
    resource_ver=$(basename "$resource_dir")
    dst="$root/usr/lib/clang/$resource_ver"

    [ -d "$resource_dir" ] || { echo "cannot detect clang resource dir" >&2; exit 1; }

    mkdir -p "$dst"
    if [ "${CLANG_STAGE_FULL_RESOURCE:-0}" = 1 ]; then
        cp -aL "$resource_dir/." "$dst/"
        return
    fi

    cp -aL "$resource_dir/include" "$dst/include"
    mkdir -p "$dst/lib/linux"
    copy_to "$resource_dir/lib/linux/libclang_rt.builtins-x86_64.a" "$dst/lib/linux/libclang_rt.builtins-x86_64.a"
    copy_to "$resource_dir/lib/linux/clang_rt.crtbegin-x86_64.o" "$dst/lib/linux/clang_rt.crtbegin-x86_64.o"
    copy_to "$resource_dir/lib/linux/clang_rt.crtend-x86_64.o" "$dst/lib/linux/clang_rt.crtend-x86_64.o"
}

stage_clang_toolchain()
{
    host_clang=${HOST_CLANG:-clang}
    host_clangxx=${HOST_CLANGXX:-clang++}
    host_llvm_ar=${HOST_LLVM_AR:-llvm-ar}
    host_llvm_ranlib=${HOST_LLVM_RANLIB:-llvm-ranlib}
    triple=$(gcc_triple)
    version=$(gcc_version)
    clang_real=$(require_real "$host_clang")
    clangxx_real=$(require_real "$host_clangxx")
    llvm_ar_real=$(find_real "$host_llvm_ar" || true)
    llvm_ranlib_real=$(find_real "$host_llvm_ranlib" || true)
    llvm_libdir=$(dirname "$clang_real")/../lib

    [ -n "$triple" ] && [ -n "$version" ] || { echo "cannot detect host gcc target/version" >&2; exit 1; }

    mkdir -p "$root/usr/bin" "$root/usr/lib"
    copy_to "$clang_real" "$root/usr/bin/clang"
    copy_to "$clangxx_real" "$root/usr/bin/clang++"
    copy_to "$clang_real" "$root/usr/bin/cc"
    copy_to "$clangxx_real" "$root/usr/bin/c++"

    if [ -n "$llvm_ar_real" ]; then
        copy_to "$llvm_ar_real" "$root/usr/bin/llvm-ar"
        copy_to "$llvm_ar_real" "$root/usr/bin/ar"
    fi
    if [ -n "$llvm_ranlib_real" ]; then
        copy_to "$llvm_ranlib_real" "$root/usr/bin/llvm-ranlib"
        copy_to "$llvm_ranlib_real" "$root/usr/bin/ranlib"
    fi

    copy_ldd_named_deps_to_dir "$root/usr/lib" "$clang_real" "$llvm_ar_real"

    stage_binutils "$triple"
    stage_glibc_devel "$triple"
    stage_minimal_gcc_runtime "$triple" "$version"
    stage_clang_resource "$clang_real"
    stage_non_llvm_ldd_deps "$clang_real" "$clangxx_real"
    if [ -n "$llvm_ar_real" ]; then
        stage_non_llvm_ldd_deps "$llvm_ar_real"
    fi
    if [ -n "$llvm_ranlib_real" ]; then
        stage_non_llvm_ldd_deps "$llvm_ranlib_real"
    fi
}

case "$toolchain" in
    clang)
        stage_clang_toolchain
        ;;
    gcc)
        stage_gcc_toolchain
        ;;
    none)
        ;;
    *)
        echo "unsupported IMAGE_TOOLCHAIN=$toolchain (expected clang, gcc, or none)" >&2
        exit 1
        ;;
esac
