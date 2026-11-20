# Free CODE security candidate

This build uses the free Collabora CODE image from the `cp-26.04.6-1` release
and rebuilds its bundled `libcurl.so.4` for Linux AMD64 and ARM64. Collabora's
Office engine loads `libcurl` separately, and the replacement includes a
static build of OpenSSL. The image keeps the upstream user and entry point.

The `library` target exports the library and license files. The `candidate`
target overlays them on the exact upstream image. Both require the replacement
to preserve the vendor's exported curl API, SONAME, and library lookup path.
Source archives are checked by SHA-256 and compilation runs without network
access. The OpenSSL archive is a pinned upstream source revision and should be
replaced with the corresponding release archive once OpenSSL publishes it.

```sh
docker buildx build --platform linux/arm64 --target library --output type=local,dest=./code-library-arm64 lykomi
docker buildx build --platform linux/amd64 --target candidate --load -t lykomi-code:26.04.6.1.1-candidate lykomi
```

The candidate carries the original upstream SBOM in its lower layers. That
SBOM describes the vendor image and must not be presented as the derived
image's SBOM. Publish a new inventory describing the replacement, and scan
both platforms before approving a digest. HarfBuzz is unchanged. Its reported
WASM shaper issue needs a build-specific assessment before approval. Test
opening, editing, and saving with LYKOMI, and confirm document sandboxing on
the target runtime.
