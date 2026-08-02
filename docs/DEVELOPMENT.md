# OpenXJ380 development and reproducible build notes

## Canonical local build

Generate the build graph before running Ninja:

```bash
python3 tools/gen_ninja.py --out build.ninja
ninja -f build.ninja all -j"$(nproc)"
```

`ninja all` builds source-derived artifacts only: `out/BOOTX64.efi`,
`out/kernel.krl`, XAPI/user ELF objects, first-party `.sys` modules, and the
third-party compliance bundle.

## Rust target libraries

Rust no-std user programs need `libcore` and `libcompiler_builtins` for the
configured target. The generator normally asks `rustc` for the target library
path. For hermetic CI or a source package that must not depend on a developer's
personal rustup layout, set `RUST_TARGET_LIBDIR`:

```bash
export RUST_TARGET=x86_64-unknown-none
export RUST_TARGET_LIBDIR=/absolute/path/to/rustlib/x86_64-unknown-none/lib
python3 tools/gen_ninja.py --out build.ninja
```

The override directory must contain matching `libcore-*.rlib` and
`libcompiler_builtins-*.rlib` files. `RUSTC` may still point at the compiler used
by Rust build edges; the library lookup does not need to probe that compiler when
`RUST_TARGET_LIBDIR` is set.

## Image resource boundary

The public source tree can generate and build the Ninja graph without `Bf/`.
`Bf/` is a local cache/prepared-root area for complete Linux-compatibility image
contents and package-manager material.

Supported image modes:

1. Source-only boot image:

   ```bash
   python3 tools/gen_ninja.py --out build.ninja
   ninja -f build.ninja vdisk
   ```

   This stages the kernel, shell, modules, licenses, and bundled resources. It
   does not require a prepared XBPS root.

2. Complete image with Linux compatibility payload:

   ```bash
   python3 tools/gen_ninja.py --out build.ninja
   ninja -f build.ninja prepare
   ninja -f build.ninja complete
   ```

   `prepare` creates `Bf/xbps-root` using `tools/stage_xbps_bootstrap.sh`.
   Network mirrors and cache locations are controlled with:

   - `XBPS_REPOSITORY` or `XBPS_REPOSITORY_FALLBACKS`
   - `XBPS_STATIC_TARBALL` / `XBPS_STATIC_URI`
   - `XBPS_CACHEDIR`
   - `BF_DIR`
   - `XBPS_PREPARE_ROOT`

3. Explicitly disabling package-manager staging for experiments:

   ```bash
   IMAGE_PACKAGE_MANAGER=none python3 tools/gen_ninja.py --out build.ninja
   IMAGE_PACKAGE_MANAGER=none ninja -f build.ninja vdisk
   ```

## External material records

Third-party source and license material is tracked under `third_party/`,
`licenses/`, `LICENSES.md`, and `THIRD_PARTY_NOTICES.md`. The machine-readable
compliance bundle is produced by `tools/package_third_party.py` and copied into
`/system/licenses/third-party` during image staging.

Large prepared image caches under `Bf/` are not source-of-truth license records.
If a complete image consumes additional prebuilt package material, keep its
source, license, version, and checksum records with the compliance material, not
only in the local cache.
