FROM rust:latest AS builder

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt --assume-yes install pkg-config clang libssl-dev libudev-dev g++ cmake

RUN --mount=type=cache,target=~/.cargo/ \
    cargo install --locked --git https://github.com/MystenLabs/sui.git --tag devnet-0.27.1 sui

