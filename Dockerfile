ARG UBUNTU_VER=24.04
ARG TARGETPLATFORM

FROM ghcr.io/by275/base:ubuntu AS prebuilt
FROM ghcr.io/by275/base:ubuntu${UBUNTU_VER} AS base

# 
# BUILD
# 
FROM base AS ytdlp

ARG DEBIAN_FRONTEND="noninteractive"

RUN \
    echo "*** install yt-dlp/FFmpeg-Builds ***" && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        xz-utils \
    && \
    export FFMPEG_FILE=$(case ${TARGETPLATFORM:-linux/amd64} in \
    "linux/amd64")   echo "ffmpeg-master-latest-linux64-gpl.tar.xz"    ;; \
    "linux/arm64")   echo "ffmpeg-master-latest-linuxarm64-gpl.tar.xz" ;; \
    *)               echo ""        ;; esac) && \
    curl -LJ "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/${FFMPEG_FILE}" -o /tmp/ffmpeg.tar.xz && \
    tar -xf /tmp/ffmpeg.tar.xz --strip-components=2 --no-anchored -C /usr/local/bin/ "ffmpeg" "ffprobe"

RUN \
    echo "*** install yt-dlp ***" && \
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp

FROM base AS deno

ARG DEBIAN_FRONTEND="noninteractive"

RUN \
    echo "*** install deno ***" && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        unzip \
    && \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- -y

# 
# COLLECT
# 
FROM base AS collector

ARG DEBIAN_FRONTEND="noninteractive"

# add s6 overlay
COPY --from=prebuilt /s6/ /bar/
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/adduser /bar/etc/cont-init.d/10-adduser

# add go-cron
COPY --from=prebuilt /go/bin/go-cron /bar/usr/local/bin/

# add ffmpeg ffprobe yt-dlp
COPY --from=ytdlp --chown=0:0 /usr/local/bin/ffmpeg /bar/usr/local/bin/
COPY --from=ytdlp --chown=0:0 /usr/local/bin/ffprobe /bar/usr/local/bin/
COPY --from=ytdlp /usr/local/bin/yt-dlp /bar/usr/local/bin/

# add deno
COPY --from=deno /usr/local/bin/deno /bar/usr/local/bin/

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/app/bin \
        /bar/config \
        /bar/down \
        /bar/downloads

# add local files
COPY root/ /bar/

RUN \
    echo "**** permissions ****" && \
    chmod a+x \
        /bar/app/bin/* \
        /bar/usr/local/bin/* \
        /bar/etc/cont-init.d/* \
        /bar/etc/s6-overlay/s6-rc.d/*/run

RUN \
    echo "**** s6: resolve dependencies ****" && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do mkdir -p "$dir/dependencies.d"; done && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "$dir/dependencies.d/legacy-cont-init"; done && \
    echo "**** s6: create a new bundled service ****" && \
    mkdir -p /tmp/app/contents.d && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "/tmp/app/contents.d/$(basename "$dir")"; done && \
    echo "bundle" > /tmp/app/type && \
    mv /tmp/app /bar/etc/s6-overlay/s6-rc.d/app && \
    echo "**** s6: deploy services ****" && \
    rm /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services && \
    touch /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/app

FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source=https://github.com/by275/docker-yt-dlp

ARG DEBIAN_FRONTEND="noninteractive"

# install packages
RUN \
    echo "**** install runtime packages ****" && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        python3-mutagen \
        rsync \
        && \
    echo "**** cleanup ****" && \
    rm -rf \
        /root/.cache \
        /tmp/* \
        /var/tmp/* \
        /var/cache/* \
        /var/lib/apt/lists/*

# add build artifacts
COPY --from=collector /bar/ /

# environment settings
ENV \
    XDG_CACHE_HOME=/tmp \
    TZ=Asia/Seoul \
    PATH="/app/bin:${PATH}"

WORKDIR /config
VOLUME /config /down /downloads

ENTRYPOINT ["/init"]
