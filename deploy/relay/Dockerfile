# vBank relay node — see deploy/relay/README.md
FROM dart:stable AS build
WORKDIR /src
# The relay reuses the app's IPFS layer; the vendored dart_ipfs lives in third_party/.
COPY . .
RUN dart pub get
# `dart build cli` (not `dart compile exe`): some dependencies ship native
# build hooks, and this produces bundle/bin/vbank_relay + bundle/lib/*.so.
RUN dart build cli -t bin/vbank_relay.dart -o /out

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/bundle /opt/vbank-relay
ENV VBANK_RELAY_DATA=/data VBANK_RELAY_PORT=4001
VOLUME ["/data"]
EXPOSE 4001/tcp
ENTRYPOINT ["/opt/vbank-relay/bin/vbank_relay"]
