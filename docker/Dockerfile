FROM ubuntu:24.04

ARG MINIRV32IMA_DOCKER_CONTEXT_HASH=unknown
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG no_proxy

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    WORKDIR=/work \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    ALL_PROXY=${ALL_PROXY} \
    NO_PROXY=${NO_PROXY} \
    http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    all_proxy=${all_proxy} \
    no_proxy=${no_proxy}

LABEL org.mini-rv32ima.docker-context-hash=${MINIRV32IMA_DOCKER_CONTEXT_HASH}

RUN apt-get update && apt-get install -y \
    bash \
    bc \
    binutils \
    bison \
    build-essential \
    bzip2 \
    ca-certificates \
    cpio \
    curl \
    device-tree-compiler \
    file \
    flex \
    g++ \
    gawk \
    gcc \
    gdb \
    git \
    gzip \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    make \
    patch \
    perl \
    python3 \
    rsync \
    sed \
    tar \
    unzip \
    vim-tiny \
    wget \
    xz-utils \
    zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["make", "everything"]
