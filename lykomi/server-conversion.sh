#!/usr/bin/env bash
set -euo pipefail
image=${1:?Expected image reference}
seccomp=${2:?Expected Collabora seccomp profile}
evidence=${3:?Expected evidence directory}
mkdir -p "$evidence"
container=''
cleanup() {
    if [[ -n $container ]]; then
        docker logs "$container" > "$evidence/server.log" 2>&1
        docker rm -f "$container" >/dev/null
    fi
}
trap cleanup EXIT
python3 - "$evidence/test.docx" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as document:
    document.writestr("[Content_Types].xml", """<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>""")
    document.writestr("_rels/.rels", """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>""")
    document.writestr("word/document.xml", """<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:t>LYKOMI CODE sandbox conversion evidence</w:t></w:r></w:p></w:body>
    </w:document>""")
PY
container=$(docker run -d --cap-drop=ALL --security-opt "seccomp=$seccomp" \
    --publish 127.0.0.1::9980 -e DONT_GEN_SSL_CERT=true "$image" \
    --o:ssl.enable=false --o:ssl.termination=false --o:security.capabilities=true \
    --o:security.enable_macros_execution=false)
port=$(docker port "$container" 9980/tcp | awk -F: '{print $NF}')
for _ in {1..35}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:$port/hosting/discovery" \
        -o "$evidence/discovery.xml" 2>/dev/null; then
        break
    fi
    [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || exit 1
    sleep 1
done
python3 - "$evidence/discovery.xml" "$port" <<'PY' > "$evidence/editor-url"
import sys
import urllib.parse
import xml.etree.ElementTree as ET

xml = ET.parse(sys.argv[1])
action = next(action for action in xml.iter("action") if action.get("ext") == "docx" and action.get("name") == "edit")
editor = urllib.parse.urlsplit(action.attrib["urlsrc"])
print(f"http://127.0.0.1:{sys.argv[2]}{editor.path}")
PY
curl -fsS --max-time 20 "$(cat "$evidence/editor-url")" -o "$evidence/editor.html"
grep -qi '<html' "$evidence/editor.html"
curl -fsS --max-time 55 -F "data=@$evidence/test.docx" \
    "http://127.0.0.1:$port/cool/convert-to/pdf" -o "$evidence/test.pdf"
pdftotext "$evidence/test.pdf" "$evidence/test.txt"
grep -Fx 'LYKOMI CODE sandbox conversion evidence' "$evidence/test.txt"
docker logs "$container" > "$evidence/server.log" 2>&1
grep -q 'Install seccomp filter successfully' "$evidence/server.log"
grep -q 'adms_contained=ok_namespaces' "$evidence/server.log"
