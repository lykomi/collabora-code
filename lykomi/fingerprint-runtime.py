#!/usr/bin/env python3
import hashlib
import json
import sys
import tarfile


def sha256_stream(stream):
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1 << 20), b""):
        digest.update(block)
    return digest.hexdigest()


entries = {}
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as rootfs:
    for member in rootfs:
        name = member.name.removeprefix("./").lstrip("/").rstrip("/")
        attributes = {
            "type": member.type.decode("ascii"),
            "mode": member.mode,
            "uid": member.uid,
            "gid": member.gid,
        }
        if member.isfile():
            attributes["sha256"] = sha256_stream(rootfs.extractfile(member))
        if member.issym() or member.islnk():
            attributes["target"] = member.linkname
        if member.ischr() or member.isblk():
            attributes["device"] = [member.devmajor, member.devminor]
        xattrs = {key: value for key, value in member.pax_headers.items()
                  if key.startswith(("SCHILY.xattr.", "LIBARCHIVE.xattr."))}
        if xattrs:
            attributes["xattrs"] = xattrs
        entries[name] = attributes

json.dump(entries, sys.stdout, sort_keys=True, separators=(",", ":"))
