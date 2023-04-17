FROM ubuntu:22.04

RUN apt update
RUN apt install -y curl
# RUN apt install -y bash
RUN apt install -y git
RUN apt install -y cmake
RUN apt install -y gcc
RUN apt install -y libssl-dev
RUN apt install -y libclang-dev
RUN apt install -y libpq-dev
RUN apt install -y build-essential

WORKDIR /app
COPY . .

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

RUN cargo install --locked --git https://github.com/MystenLabs/sui.git --tag devnet-0.27.1 sui
RUN cargo install --git https://github.com/move-language/move move-analyzer --branch sui-move --features "address32"

EXPOSE 80