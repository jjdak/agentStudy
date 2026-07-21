ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        bash \
        build-essential \
        ca-certificates \
        cmake \
        diffutils \
        file \
        gdb \
        git \
        jq \
        libtool \
        locales \
        perl \
        pkg-config \
        procps \
        python3 \
        ripgrep \
        strace \
    && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

LABEL org.opencontainers.image.title="agentStudy curl variable toolchain"
LABEL org.opencontainers.image.source="https://github.com/jjdak/agentStudy"

WORKDIR /workspace
