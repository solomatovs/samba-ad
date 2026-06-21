FROM astra-linux:2.12-glibc2.28 AS builder

ARG SAMBA_PATH=/opt/samba
ENV PATH=/usr/local/bin:/usr/local/sbin:$PATH
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig

# build-toolchain
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive                          \
    apt-get install -y --no-install-recommends                 \
        build-essential binutils make gawk bison flex          \
        file xz-utils gettext pkg-config curl                  \
        linux-libc-dev perl libparse-yapp-perl                 \
        zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev     \
        libssl-dev libreadline-dev libffi-dev libsqlite3-dev   \
        libbz2-dev liblzma-dev                                 \
        libgmp-dev libtasn1-6-dev libidn2-dev libp11-kit-dev   \
        libldap2-dev libjansson-dev liblmdb-dev libicu-dev     \
        libacl1-dev libattr1-dev libblkid-dev libbsd-dev       \
        libaio-dev libarchive-dev libgpgme-dev libpcap-dev     \
        libpopt-dev libpam0g-dev libcap-dev libdbus-1-dev      \
        libkeyutils-dev libverto-dev                           \
    && rm -rf /var/lib/apt/lists/*

# libc6-dev (от build-essential) перезаписал заголовки glibc на 2.24 —
# возвращаем 2.28 из базы и перелинковываем arch-заголовки multiarch на них,
COPY --from=astra-linux:2.12-glibc2.28 /usr/include/ /usr/include/
RUN set -eux \
    && cd /usr/include/x86_64-linux-gnu \
    && dpkg -L libc6-dev | grep -E '^/usr/include/x86_64-linux-gnu/[^/]+$' | while read -r p; do \
        n=${p#/usr/include/x86_64-linux-gnu/}; \
        rm -rf "$n"; ln -s "../$n" "$n"; \
    done

# GCC 8
COPY build/artifacts/gcc-src/ /tmp/gcc-src/
RUN cd /tmp                         \
    && tar -xf gcc-src/gcc-*.tar.xz \
    && cd gcc-*                     \
    && tar -xf /tmp/gcc-src/gmp-*.tar.xz    && mv gmp-6.1.2     gmp  \
    && tar -xf /tmp/gcc-src/mpfr-*.tar.xz   && mv mpfr-4.0.2    mpfr \
    && tar -xf /tmp/gcc-src/mpc-*.tar.gz    && mv mpc-1.1.0     mpc  \
    && cd /tmp              \
    && mkdir gcc-build      \
    && cd gcc-build         \
    && ../gcc-*/configure   \
        --enable-languages=c,c++                    \
        --disable-multilib --disable-bootstrap      \
        --disable-libsanitizer --disable-libgomp    \
        --disable-libquadmath --disable-libssp      \
        --disable-libvtv --disable-libada           \
        --with-default-libstdcxx-abi=new            \
    && make -j"$(nproc)"        \
    && make install-strip       \
    && ldconfig                 \
    && cd / && rm -rf /tmp/*

# Python 3.11
COPY build/artifacts/python-src/Python-*.tar.xz /tmp/
RUN cd /tmp                     \
    && tar -xf Python-*.tar.xz  \
    && cd Python-*              \
    && ./configure              \
        --enable-optimizations --with-lto   \
        --enable-shared                     \
        --with-ensurepip=install            \
        LDFLAGS=-Wl,-rpath,/usr/local/lib   \
    && make -j"$(nproc)"    \
    && make install         \
    && ldconfig             \
    && cd / && rm -rf /tmp/*

# pip.conf (закрытый контур) — для pip3 install ниже
COPY build/artifacts/pip.conf* /tmp/pipconf/
RUN if [ -f /tmp/pipconf/pip.conf ]; then cp /tmp/pipconf/pip.conf /etc/pip.conf; fi && rm -rf /tmp/pipconf
RUN pip3 install --no-cache-dir markdown dnspython cryptography

# nettle
COPY build/artifacts/samba-src/nettle-*.tar.gz /tmp/
RUN cd /tmp                 \
    && tar xf nettle-*.tar.gz \
    && cd nettle-*/         \
    && ./configure          \
        --prefix=/usr/local \
        --disable-static    \
        --enable-shared     \
    && make -j"$(nproc)"    \
    && make install         \
    && ldconfig             \
    && cd / && rm -rf /tmp/*

# GnuTLS
COPY build/artifacts/samba-src/gnutls-*.tar.xz /tmp/
RUN cd /tmp                 \
    && tar xf gnutls-*.tar.xz \
    && cd gnutls-*/         \
    && ./configure          \
        --prefix=/usr/local         \
        --with-included-unistring   \
        --without-p11-kit           \
        --disable-doc               \
        --disable-tests             \
        --disable-tools             \
        --disable-static            \
    && make -j"$(nproc)"    \
    && make install         \
    && ldconfig             \
    && cd / && rm -rf /tmp/*

# MIT krb5
COPY build/artifacts/samba-src/krb5-*.tar.gz /tmp/
RUN cd /tmp                                 \
    && tar xf krb5-*.tar.gz                 \
    && cd krb5-*/src                        \
    && ./configure                          \
        --prefix=/usr/local                 \
        --disable-rpath                     \
    && make -j"$(nproc)"    \
    && make install         \
    && ldconfig             \
    && ln -sf /usr/local/sbin/krb5kdc  /usr/sbin/krb5kdc  \
    && ln -sf /usr/local/sbin/kadmind  /usr/sbin/kadmind  \
    && cd / && rm -rf /tmp/*

# samba 4.21 AD DC
COPY build/artifacts/samba-src/samba-*.tar.gz /tmp/
RUN cd /tmp                     \
    && tar xf samba-*.tar.gz    \
    && cd samba-*/              \
    && ./configure              \
        --prefix=/usr           \
        --enable-fhs            \
        --sysconfdir=/etc       \
        --localstatedir=/var    \
        --with-privatedir=/var/lib/samba/private \
        --bundled-libraries=ALL \
        --with-system-mitkrb5   \
        --with-experimental-mit-ad-dc       \
        --without-systemd       \
        --disable-cups          \
        --without-pam           \
    && make -j"$(nproc)"        \
    && make install DESTDIR=${SAMBA_PATH}   \
    && cd / && rm -rf /tmp/*

RUN set -eux \
    && mkdir -p /opt/rootfs/usr/local                       \
    && cp -a ${SAMBA_PATH}/. /opt/rootfs/                   \
    && rm -rf /opt/rootfs/var/lock /opt/rootfs/var/run      \
    && for d in lib lib64 bin sbin; do                      \
         [ -e /usr/local/$d ] && cp -a /usr/local/$d /opt/rootfs/usr/local/ || true; \
       done                                                 \
    && rm -rf /opt/rootfs/usr/local/lib/gcc                 \
              /opt/rootfs/usr/local/libexec                 \
              /opt/rootfs/usr/local/include                 \
    && rm -f  /opt/rootfs/usr/local/bin/*gcc*               \
              /opt/rootfs/usr/local/bin/*g++*               \
              /opt/rootfs/usr/local/bin/c++                 \
              /opt/rootfs/usr/local/bin/cpp                 \
              /opt/rootfs/usr/local/bin/gcov*               \
              /opt/rootfs/usr/local/bin/lto-dump            \
    && find /opt/rootfs/usr/local -name '*.a'  -delete      \
    && find /opt/rootfs/usr/local -name '*.la' -delete      \
    && find /opt/rootfs -type f -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true \
    && find /opt/rootfs -type f \( -path '*/bin/*' -o -path '*/sbin/*' \) -exec strip {} + 2>/dev/null || true


FROM astra-linux:2.12-glibc2.28 AS runtime

ENV PATH=/usr/local/bin:/usr/local/sbin:$PATH

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive                       \
    apt-get install -y --no-install-recommends              \
        libldap-2.4-2 libjansson4 liblmdb0 libicu63         \
        libacl1 libattr1 libblkid1 libbsd0 libaio1          \
        libarchive13 libgpgme11 libpcap0.8 libpopt0         \
        libcap2 libdbus-1-3 libkeyutils1 libverto1          \
        libgmp10 libtasn1-6 libidn2-0 libssl1.1 zlib1g      \
        dnsutils iproute2 procps                            \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/rootfs/ /

RUN set -eux \
    && printf '%s\n' /usr/local/lib /usr/local/lib64 /lib /usr/lib > /etc/ld.so.conf.d/000-runtime.conf \
    && ldconfig \
    && ln -sf /usr/local/sbin/krb5kdc  /usr/sbin/krb5kdc \
    && ln -sf /usr/local/sbin/kadmind  /usr/sbin/kadmind \
    && rm -f /etc/samba/smb.conf \
    && samba --version

COPY build/ad/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /docker-entrypoint-init.d

EXPOSE 53/tcp 53/udp 88/tcp 88/udp 464/tcp 464/udp 389/tcp 636/tcp 3268/tcp 3269/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
