# vBank relay node

Members' phones sit behind mobile-network NAT and cannot accept connections, so
two phones on different networks never reach each other directly. A **relay** is
a small always-on vBank peer with a public address. Every device dials it out,
pushes its records to it and pulls what it lacks from it — joins, sync and
notifications then work from anywhere.

What the relay can and cannot see: every record is encrypted on the device with
the group passphrase-derived key before it is sent; the relay stores opaque
blocks under opaque group ids and learns only which peers talk about which group
id. It never holds a group key and cannot read amounts, names or anything else.

## Run it on a Linux VPS (Docker)

The image is published to GitHub Container Registry as
**`ghcr.io/arthurkay/vbank-relay`** (`latest` = main, plus one tag per release,
e.g. `1.7.0`) by `.github/workflows/relay-image.yml`. No checkout needed:

```sh
mkdir -p vbank-relay && cd vbank-relay
curl -fsSLO https://raw.githubusercontent.com/arthurkay/vbank/main/deploy/relay/docker-compose.yml
echo 'VBANK_RELAY_PUBLIC_IP=203.0.113.7' > .env      # your VPS public IPv4
docker compose pull && docker compose up -d
docker compose logs -f relay                         # look for "relay address:"
```

To build the image yourself instead: `docker build -f deploy/relay/Dockerfile -t vbank-relay .`
from the repository root and set `image: vbank-relay` in the compose file.

Open TCP port **4001** in the VPS firewall / security group. The log prints the
address to give to members, e.g.

```
[relay] relay address: /ip4/203.0.113.7/tcp/4001/p2p/12D3KooW…
```

The node identity (and therefore the `/p2p/…` part) lives in the `relay-data`
volume; keep the volume and the address stays the same across restarts and
upgrades. `restart: unless-stopped` brings it back after a reboot.

## Point the apps at it

* **Settings → Sync status → Relay server → Add** on a phone or desktop, paste the
  address. Do this once on the group owner's device.
* From then on every **invite link** the owner creates carries the relay
  (`relay=` parameter), so new members are configured automatically when they
  join. Existing members can paste it too, or ask for a new invite link.

Several relays can be added; devices use all of them.

## Without Docker

```sh
dart pub get
dart build cli -t bin/vbank_relay.dart -o build/relay     # bundle/bin/vbank_relay + bundle/lib/*.so
build/relay/bundle/bin/vbank_relay --data /var/lib/vbank-relay --port 4001 --public-ip 203.0.113.7
```

(`dart compile exe` refuses because some dependencies use native build hooks.)

A systemd unit only needs `ExecStart` pointing at that command and
`Restart=always`.

## Operations

* Disk: blocks are a few KB each; a busy group produces well under a megabyte a
  month. The ledger is `relay_ledger.json` in the data directory.
* Logs: one line per stored block / forwarded notification; a heartbeat every
  10 minutes. `--verbose` (or `VBANK_RELAY_VERBOSE=1`) adds libp2p detail.
* Upgrading: `docker compose pull && docker compose up -d`; the data volume keeps
  identity and blocks. The container runs as an unprivileged user (uid 10001).
