# syntax=docker/dockerfile:1.7
# Rebuild the curl library carried by free Collabora CODE, including its static TLS dependency.
FROM collabora/code:26.04.6.1.1@sha256:95f29f1c0a1778999125f53f058d968fe0afb37c95e32ebfb9f3444140faebd2 AS code
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS compile
ARG TARGETARCH
ARG BUILD_JOBS=4
RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils ca-certificates gcc libc6-dev make patchelf perl pkg-config xz-utils zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
ADD --checksum=sha256:dbd0e057df18259374d3ea014b4383967864d540b5103675342e0e18cef603af \
    https://codeload.github.com/openssl/openssl/tar.gz/81162ed421d98f527f55bfff205994f53831223b openssl.tar.gz
ADD --checksum=sha256:8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5 \
    https://curl.se/download/curl-8.23.0.tar.xz curl.tar.xz
RUN --network=none set -eu; \
    mkdir openssl curl; \
    tar xf openssl.tar.gz -C openssl --strip-components=1; \
    tar xf curl.tar.xz -C curl --strip-components=1; \
    case "$TARGETARCH" in \
      amd64) openssl_target=linux-x86_64 ;; \
      arm64) openssl_target=linux-aarch64 ;; \
      *) exit 1 ;; \
    esac; \
    cd openssl; \
    ./Configure "$openssl_target" --prefix=/opt/tls --libdir=lib \
      no-dso no-shared no-tests -fPIC; \
    make -j "$BUILD_JOBS" build_libs; \
    make install_dev

# Match CODE's feature selection and retain its local-library lookup path.
RUN --network=none set -eu; \
    cd curl; \
    export PKG_CONFIG_PATH=/opt/tls/lib/pkgconfig; \
    ./configure --with-openssl=/opt/tls --with-zlib --enable-shared --disable-static \
      --disable-ftp --enable-http --enable-ipv6 --without-libidn2 --without-libpsl \
      --without-libssh2 --without-nghttp2 --without-libssh \
      --without-brotli --without-ngtcp2 --without-quiche --without-zstd \
      --without-libgsasl --without-gssapi --disable-ipfs --disable-mqtt \
      --disable-ares --disable-dict --disable-file --disable-gopher --disable-imap \
      --disable-ldap --disable-ldaps --disable-manual --disable-pop3 --disable-rtsp \
      --disable-smtp --disable-telnet --disable-tftp --without-ca-bundle --without-ca-path; \
    make -C lib -j "$BUILD_JOBS"; \
    install -D -m 644 lib/.libs/libcurl.so.4 /output/libcurl.so.4; \
    patchelf --set-rpath '$ORIGIN' /output/libcurl.so.4; \
    install -D -m 644 COPYING /output/curl.COPYING; \
    install -D -m 644 ../openssl/LICENSE.txt /output/openssl.LICENSE.txt

COPY --from=code /opt/collaboraoffice/program/libcurl.so.4 /vendor/libcurl.so.4
COPY verify-library.sh /tmp/verify-library.sh
RUN --network=none sh /tmp/verify-library.sh /vendor/libcurl.so.4 /output/libcurl.so.4

FROM scratch AS library
COPY --from=compile /output/ /

# This candidate still needs a whole-image scan and a WOPI runtime test before promotion.
FROM code AS candidate
COPY --from=compile /output/libcurl.so.4 /opt/collaboraoffice/program/libcurl.so.4
COPY --from=compile /output/curl.COPYING /usr/share/doc/lykomi-code-repair/curl.COPYING
COPY --from=compile /output/openssl.LICENSE.txt /usr/share/doc/lykomi-code-repair/openssl.LICENSE.txt
