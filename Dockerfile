ARG BUILD_FROM

FROM --platform=amd64 golang:1.26.8-alpine@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS builder

WORKDIR /usr/src
ARG BUILD_ARCH
ARG COREDNS_VERSION
# Raised above what the CoreDNS release pins.
ARG GRPC_VERSION=1.79.3
ENV GOTOOLCHAIN=local

# Build CoreDNS
COPY plugins plugins
RUN \
    set -x \
    && apk add --no-cache \
        git \
        make \
        bash \
    && git clone --depth 1 -b v${COREDNS_VERSION} https://github.com/coredns/coredns \
    && cp -rf plugins/* coredns/plugin/ \
    && cd coredns \
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
    && go get "google.golang.org/grpc@v${GRPC_VERSION}" \
    && go mod tidy \
    && go generate \
    && \
        if [ "${BUILD_ARCH}" = "armhf" ]; then \
            make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARM=6 GOARCH=arm"; \
        elif [ "${BUILD_ARCH}" = "armv7" ]; then \
            make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARM=7 GOARCH=arm"; \
        elif [ "${BUILD_ARCH}" = "aarch64" ]; then \
            make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARCH=arm64"; \
        elif [ "${BUILD_ARCH}" = "i386" ]; then \
            make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARCH=386"; \
        elif [ "${BUILD_ARCH}" = "amd64" ]; then \
            make coredns SYSTEM="CGO_ENABLED=0 GOOS=linux GOARCH=amd64"; \
        else \
            exit 1; \
        fi

FROM ${BUILD_FROM}

SHELL ["/bin/ash", "-o", "pipefail", "-c"]
ARG BUILD_ARCH

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
