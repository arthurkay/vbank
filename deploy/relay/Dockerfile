# vBank relay node — see deploy/relay/README.md
# Image: ghcr.io/arthurkay/vbank-relay (built by .github/workflows/relay-image.yml)
# The relay lives in the app package (it reuses lib/core/ipfs), whose pubspec
# depends on the Flutter SDK, so the build stage needs Flutter's Dart — same
# version as the app (see FLUTTER_VERSION in .github/workflows/release.yml).
FROM ghcr.io/cirruslabs/flutter:3.41.6 AS build
WORKDIR /src
# The vendored dart_ipfs lives in third_party/.
COPY pubspec.yaml pubspec.lock ./
COPY third_party ./third_party
RUN flutter pub get
COPY lib ./lib
COPY bin ./bin
# `dart build cli` (not `dart compile exe`): some dependencies ship native
# build hooks, and this produces bundle/bin/vbank_relay + bundle/lib/*.so.
RUN dart build cli -t bin/vbank_relay.dart -o /out

FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/arthurkay/vbank" \
      org.opencontainers.image.description="vBank relay node: always-on peer that lets village banking groups sync over the internet. Stores encrypted blocks only." \
      org.opencontainers.image.licenses="MIT"
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home /data vbank && mkdir -p /data && chown vbank:vbank /data
COPY --from=build /out/bundle /opt/vbank-relay
ENV VBANK_RELAY_DATA=/data VBANK_RELAY_PORT=4001
USER vbank
VOLUME ["/data"]
EXPOSE 4001/tcp
ENTRYPOINT ["/opt/vbank-relay/bin/vbank_relay"]
