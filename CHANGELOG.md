# Changelog — GA armv7 build of the Home Assistant DNS plugin

GA-maintained armv7 rebuilds of `home-assistant/plugin-dns`, published as
`ghcr.io/greenautarky/armv7-hassio-dns`. Upstream dropped armv7; each version
here is upstream source at the named tag plus the GA build changes.

## 2026.09.1

- Rebase onto upstream plugin-dns `2026.09.0` (was `2025.08.0`).
- CoreDNS 1.11.4 → 1.14.7 (security fix).
- Taken from upstream: hosts file reloaded every 250 ms with a 60 s record TTL,
  no positive or negative caching for `local.hass.io`, the hosts-file
  open-only-on-change patch, `S6_KILL_GRACETIME=0`.
- Kept GA build changes: armv7 (`GOARM=7`) cross-compile, Go 1.26.8
  (digest-pinned), armv7-base 3.22 (digest-pinned) with `apk upgrade`,
  checksum-pinned tempio 2026.07.0.
- Dropped the gRPC override (1.79.3): CoreDNS 1.14.7 already ships a newer gRPC,
  so the override would have downgraded it.
- CI proves the image reports `CoreDNS-1.14.7` on `linux/arm`, that every plugin
  the Corefile uses is compiled in, and that the tempio-rendered Corefile parses
  and answers from the hosts file for two option sets.

## 2025.08.2

- Rebuild of upstream `2025.08.0` on current Alpine 3.22 packages and Go 1.26.8.

## 2025.08.1

- First GA armv7 rebuild of upstream `2025.08.0` (CoreDNS 1.11.4).
