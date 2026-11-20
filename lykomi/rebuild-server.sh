#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
set -euo pipefail

output=${1:?Expected an absolute output directory}
: "${EXPECTED_ARCH:?Expected the target architecture}"
: "${EXPECTED_STRING_ABI:?Expected the vendor libstdc++ string ABI}"
case "$EXPECTED_STRING_ABI" in
    0) kit_symbol='_Z10lokit_mainRKSs' ;;
    1) kit_symbol='_Z10lokit_mainRKNSt7__cxx11' ;;
    *) echo "Unsupported string ABI: $EXPECTED_STRING_ABI" >&2; exit 1 ;;
esac
if [[ $output != /* ]]; then
    echo "The output directory must be absolute" >&2
    exit 1
fi

case "$EXPECTED_ARCH" in
    amd64) machine='Advanced Micro Devices X86-64' ;;
    arm64) machine='AArch64' ;;
    *) echo "Unsupported architecture: $EXPECTED_ARCH" >&2; exit 1 ;;
esac

./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-tests \
    --with-lo-builddir="$PWD/engine" --with-lokit-path="$PWD/engine/include" \
    --with-lo-path=/opt/collaboraoffice
make -j "$(nproc)" coolwsd coolforkit-caps coolforkit-ns

mkdir -p "$output"
for program in coolwsd coolforkit-caps coolforkit-ns; do
    install -m 755 "./$program" "$output/$program"
    strip --strip-unneeded "$output/$program"
    readelf --file-header "$output/$program" > "$output/$program.elf"
    readelf --dynamic --version-info "$output/$program" >> "$output/$program.elf"
    if [[ $program == coolforkit-* ]]; then
        objdump --dynamic-syms "$output/$program" > "$output/$program.symbols"
        grep -F "$kit_symbol" "$output/$program.symbols" >> "$output/$program.elf"
        rm "$output/$program.symbols"
    fi
    strings "$output/$program" > "$output/$program.strings"
    grep -F "$machine" "$output/$program.elf"
    grep -F 'OpenSSL 3.5.10-dev' "$output/$program.strings" | sort -u
    if grep -qE 'OpenSSL 3\.5\.8|NEEDED.*\[(libssl|libcrypto)\.so' \
        "$output/$program.strings" "$output/$program.elf"; then
        echo "Unexpected OpenSSL linkage in $program" >&2
        exit 1
    fi
    rm "$output/$program.strings"
done

git rev-parse HEAD > "$output/source-commit"
{
    printf 'Workflow run: %s / attempt %s\n' "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-local}"
    printf 'Runner image: %s %s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"
    printf '\nOnline configure arguments:\n'
    ./config.status --config
    printf '\nEngine configure arguments:\n'
    (cd engine && ./config.status --config)
    printf '\nConfigured toolchain and external linkage:\n'
    grep -E '^export (CC|CXX|LINK|COM|CPPFLAGS|CXXFLAGS|SYSTEM_(EXPAT|LIBPNG|OPENSSL|ZLIB|ZSTD))=' engine/config_host.mk
    printf 'Preprocessor flags: %s\n' "${CPPFLAGS:-}"
    printf 'Vendor libstdc++ string ABI: %s\n' "$EXPECTED_STRING_ABI"
    printf '\nBuild tool package versions:\n'
    "${CC:-gcc}" --version | sed -n '1p'
    "${CXX:-g++}" --version | sed -n '1p'
    dpkg-query -W "${CC:-gcc}" "${CXX:-g++}" binutils make libc6-dev
    printf '\nPinned OpenSSL material:\n'
    grep -E '^OPENSSL_(TARBALL|TARBALL_URL|SHA256SUM)[[:space:]]*[:?]?=' engine/download.lst
    sha256sum engine/workdir/UnpackedTarball/openssl/libssl.a engine/workdir/UnpackedTarball/openssl/libcrypto.a
} > "$output/build-environment.txt"
(
    cd "$output"
    files=(coolwsd coolforkit-caps coolforkit-ns coolwsd.elf coolforkit-caps.elf
        coolforkit-ns.elf source-commit build-environment.txt)
    sha256sum "${files[@]}" > SHA256SUMS
    tar -cf "$output.tar" "${files[@]}" SHA256SUMS
)
