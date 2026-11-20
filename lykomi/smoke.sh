#!/usr/bin/env bash
set -euo pipefail

image=$1
seccomp=$(realpath "$2")
workspace=$(mktemp -d)
container=''
cleanup() {
    if [[ -n "$container" ]]; then
        docker rm -f "$container" >/dev/null
    fi
    rm -rf "$workspace"
}
trap cleanup EXIT

# Check the real file reached by the distroless root's libz symlink.
arch=$(docker image inspect --format '{{.Architecture}}' "$image")
case "$arch" in
    amd64) multiarch=x86_64-linux-gnu; zlib_sha=6c13931760210e8b391b63a337dfe4071346c4ad6e3827694edb7b6989bb16dd ;;
    arm64) multiarch=aarch64-linux-gnu; zlib_sha=ac4b7f163145ca73ddba8e657cc35c5b5380ce01f75cbf3b65f8deeebd9c1e72 ;;
    *) exit 1 ;;
esac
container=$(docker create --platform "linux/$arch" "$image")
docker cp -L "$container:/usr/lib/$multiarch/libz.so.1.3.1" "$workspace/libz.so"
printf '%s  %s\n' "$zlib_sha" "$workspace/libz.so" | sha256sum --check
docker rm "$container" >/dev/null
container=''

# The image runs as uid 1001, so give it access to this disposable directory.
chmod 777 "$workspace"
printf '%s\n' 'LYKOMI CODE document smoke test' > "$workspace/fixture.txt"
if ! timeout 60s docker run --rm --network none --cap-drop=ALL \
    --mount "type=bind,source=$workspace,destination=/work" \
    -e HOME=/tmp -e SAL_USE_VCLPLUGIN=svp \
    --entrypoint /opt/collaboraoffice/program/soffice.bin "$image" \
    -env:UserInstallation=file:///tmp/lykomi-smoke --headless \
    --convert-to pdf --outdir /work /work/fixture.txt > "$workspace/convert.log" 2>&1; then
    tail -30 "$workspace/convert.log" >&2
    exit 1
fi
head -c 5 "$workspace/fixture.pdf" | grep -Fx '%PDF-'

container=$(docker run -d --cap-drop=ALL --security-opt "seccomp=$seccomp" \
    --publish 127.0.0.1::9980 -e DONT_GEN_SSL_CERT=true "$image" \
    --o:ssl.enable=false --o:ssl.termination=false --o:security.capabilities=true \
    --o:security.enable_macros_execution=false)
port=$(docker port "$container" 9980/tcp | awk -F: '{print $NF}')
for _ in $(seq 1 45); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$port/hosting/discovery" \
        -o "$workspace/discovery.xml" 2>/dev/null; then
        grep -q 'ext="docx"' "$workspace/discovery.xml"
        docker logs "$container" > "$workspace/server.log" 2>&1
        grep -q 'Install seccomp filter successfully' "$workspace/server.log"
        exit 0
    fi
    [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || break
    sleep 1
done
docker logs --tail 30 "$container" >&2
exit 1
