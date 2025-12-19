# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

FROM ghcr.io/boukehaarsma23/aur-builder:main AS builder

# Base Image
FROM docker.io/archlinux/archlinux:base

COPY --from=builder /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=builder,source=/tmp/repo,target=/repo \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### BOOTC + LINTING
LABEL containers.bootc 1
RUN bootc container lint
