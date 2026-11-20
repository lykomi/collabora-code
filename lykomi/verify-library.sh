#!/bin/sh
set -eu

vendor=$1
candidate=$2
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

readelf -d "$candidate" > "$scratch/dependencies"
grep -F 'Library soname: [libcurl.so.4]' "$scratch/dependencies"
if grep -Eq 'Shared library: \[lib(ssl|crypto)\.so' "$scratch/dependencies"; then
    echo 'Expected the patched OpenSSL to be statically linked into libcurl' >&2
    exit 1
fi

grep -F 'Library runpath: [$ORIGIN]' "$scratch/dependencies"

curl_exports() {
    readelf --dyn-syms --wide "$1" | awk '$5 == "GLOBAL" && $7 != "UND" && $8 ~ /^curl_/ { print $8 }' | sort -u
}
curl_exports "$vendor" > "$scratch/vendor"
curl_exports "$candidate" > "$scratch/candidate"
test -s "$scratch/vendor"
comm -23 "$scratch/vendor" "$scratch/candidate" > "$scratch/missing"
if [ -s "$scratch/missing" ]; then
    echo 'Candidate is missing exported curl symbols:' >&2
    cat "$scratch/missing" >&2
    exit 1
fi

strings "$candidate" > "$scratch/strings"
grep -F 'libcurl/8.23.0' "$scratch/strings"
grep -F 'OpenSSL 3.5.10' "$scratch/strings"
