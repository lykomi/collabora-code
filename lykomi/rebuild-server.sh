#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
set -euo pipefail

output=${1:?Expected an absolute output directory}
: "${EXPECTED_ARCH:?Expected the target architecture}"
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
    install -m 755 "engine/workdir/LinkTarget/Executable/$program" "$output/$program"
    strip --strip-unneeded "$output/$program"
    readelf --file-header "$output/$program" > "$output/$program.elf"
    readelf --dynamic "$output/$program" >> "$output/$program.elf"
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
(
    cd "$output"
    sha256sum coolwsd coolforkit-caps coolforkit-ns *.elf source-commit > SHA256SUMS
    tar -cf "$output.tar" coolwsd coolforkit-caps coolforkit-ns *.elf source-commit SHA256SUMS
)
