ARG BUILD_FROM

# GA: cross-compile on the amd64 build host (no QEMU for the Go build).
# Digest-pinned Go toolchain, newer than upstream's 1.26.5.
FROM --platform=amd64 golang:1.26.8-alpine@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS builder

WORKDIR /usr/src
ARG TARGETARCH
ARG TARGETVARIANT
ARG COREDNS_VERSION="1.14.7"
ENV GOTOOLCHAIN=local

# Build CoreDNS
# GA: the arm case is ours - upstream dropped 32-bit ARM; we build armv7 only.
COPY plugins plugins
COPY patches patches
RUN \
    set -x \
    && apk add --no-cache \
        git \
        make \
        bash \
    && git clone --depth 1 -b v${COREDNS_VERSION} https://github.com/coredns/coredns \
    && cp -rf plugins/* coredns/plugin/ \
    && cd coredns \
    && git apply --verbose ../patches/*.patch \
    && sed -i "/^template:template/d" plugin.cfg \
    && sed -i "/^hosts:.*/a template:template" plugin.cfg \
    && sed -i "/^forward:.*/i fallback:fallback" plugin.cfg \
    && sed -i "/^hosts:.*/a mdns:mdns" plugin.cfg \
    && sed -i "/route53:route53/d" plugin.cfg \
    && sed -i "/clouddns:clouddns/d" plugin.cfg \
    && sed -i "/k8s_external:k8s_external/d" plugin.cfg \
    && sed -i "/kubernetes:kubernetes/d" plugin.cfg \
    && sed -i "/etcd:etcd/d" plugin.cfg \
    && sed -i "/grpc:grpc/d" plugin.cfg \
    && sed -i "/nomad:nomad/d" plugin.cfg \
    && sed -i "/trace:trace/d" plugin.cfg \
    && go mod tidy \
    && go generate \
    && if [ -z "${TARGETARCH}" ]; then \
            echo "TARGETARCH is not set, please use Docker BuildKit for the build." && exit 1; \
        fi \
    && case "${TARGETARCH}" in \
            amd64|arm64) \
                make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH}" ;; \
            arm) \
                [ "${TARGETVARIANT}" = "v7" ] || { echo "Unsupported arm variant: ${TARGETVARIANT}" && exit 1; } \
                && make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7" ;; \
            *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
        esac

# GA: upstream's multi-arch base:3.24 has no armv7; the armv7 base ends at
# 3.22 and is passed in digest-pinned by the GA workflow.
FROM ${BUILD_FROM}

SHELL ["/bin/ash", "-o", "pipefail", "-c"]
ARG BUILD_ARCH

# Everything in this image runs s6-supervised and is stopped gracefully
# by s6-rc: skip the blind SIGTERM-to-SIGKILL grace sleep at shutdown.
ENV S6_KILL_GRACETIME=0

# The armv7 base image is no longer rebuilt upstream, so its Alpine packages
# only age. Pull the current 3.22 package updates on top of it.
# hadolint ignore=DL3017
RUN apk upgrade --no-cache

# tempio from its current release (the base image carries an older build).
# Checksum-pinned; only the armv7 binary is pinned because only armv7 is built.
ARG TEMPIO_VERSION=2026.07.0
ARG TEMPIO_SHA256=1887c4721317ee166de703ddb30f906c9f98f01f08a6b2da295c10946a0c8110
RUN \
    curl -Lfso /usr/bin/tempio "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}" \
    && echo "${TEMPIO_SHA256}  /usr/bin/tempio" | sha256sum -c - \
    && chmod a+x /usr/bin/tempio

WORKDIR /config
COPY --from=builder /usr/src/coredns/coredns /usr/bin/coredns
COPY rootfs /

LABEL \
    io.hass.type="dns" \
    org.opencontainers.image.title="Home Assistant DNS Plugin" \
    org.opencontainers.image.description="Home Assistant Supervisor plugin for DNS" \
    org.opencontainers.image.authors="The Home Assistant Authors" \
    org.opencontainers.image.url="https://www.home-assistant.io/" \
    org.opencontainers.image.documentation="https://www.home-assistant.io/docs/" \
    org.opencontainers.image.licenses="Apache License 2.0"
