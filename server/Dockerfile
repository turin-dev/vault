FROM rust:1-bookworm AS build
WORKDIR /src
COPY Cargo.lock ./
COPY core core
COPY server server
# app/rust(Flutter용)는 이미지에 없으므로 서버 전용 워크스페이스로 재구성
RUN printf '[workspace]\nresolver = "2"\nmembers = ["core", "server"]\n\n[profile.release]\nlto = true\ncodegen-units = 1\nstrip = true\n' > Cargo.toml \
    && cargo build --release -p geumgo-server

FROM debian:bookworm-slim
RUN useradd -r -u 10001 geumgo && mkdir -p /data && chown geumgo /data
COPY --from=build /src/target/release/geumgo-server /usr/local/bin/geumgo-server
USER geumgo
ENV GEUMGO_DB=/data/geumgo-server.db
ENV GEUMGO_ADDR=0.0.0.0:8080
EXPOSE 8080
VOLUME /data
CMD ["geumgo-server"]
