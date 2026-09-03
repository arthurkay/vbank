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
echo 'VBANK_RELAY_PUBLIC_HOST=relay.example.com' > .env   # DNS A record → your VPS
docker compose pull && docker compose up -d
docker compose logs -f relay                              # look for "relay address:"
```

Use a **hostname** (`VBANK_RELAY_PUBLIC_HOST`) whenever you can: members then
get a `/dns4/relay.example.com/tcp/4001/p2p/…` address that keeps working if
the VPS's IP changes — devices resolve the name right before each dial. Without
DNS, set `VBANK_RELAY_PUBLIC_IP=203.0.113.7` for a plain `/ip4/…` address.

Optional `VBANK_RELAY_IDENTITY_SEED` (output of `openssl rand -base64 32`) pins
the peer id — the `/p2p/…` part of the address — independently of the data
volume, so you can wipe or move the volume and keep the same address. Treat it
like a private key.

To build the image yourself instead: `docker build -f deploy/relay/Dockerfile -t vbank-relay .`
from the repository root and set `image: vbank-relay` in the compose file.

Open TCP port **4001** in the VPS firewall / security group. The log prints the
address to give to members, e.g.

```
[relay] relay address: /dns4/relay.example.com/tcp/4001/p2p/12D3KooW…
```

The node identity (and therefore the `/p2p/…` part) lives in the `relay-data`
volume; keep the volume and the address stays the same across restarts and
upgrades. `restart: unless-stopped` brings it back after a reboot.

## The built-in relay (vbank.localhost.co.zm)

Every copy of vBank ships knowing one relay host, `vbank.localhost.co.zm`
(`kBuiltInRelayHosts` in `lib/core/relay/relay_directory.dart`). Only the
**hostname** is in the app; the relay's peer id is published as a DNS TXT
record in the libp2p `dnsaddr` form, and the app looks it up over
DNS-over-HTTPS (Cloudflare, then Google) at most hourly, keeping the last good
answer for offline starts. Rotating the relay therefore never needs an app
update. Members can switch the built-in relay off and add their own.

To publish it, after `docker compose up` shows the address:

```
_dnsaddr.vbank.localhost.co.zm.  IN TXT  "dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooW…"
vbank.localhost.co.zm.           IN A    203.0.113.7
```

Check it with `dig +short TXT _dnsaddr.vbank.localhost.co.zm`. Several
`dnsaddr=` records are allowed (e.g. a second relay); the app uses them all.
Because the TXT record carries the peer id, set `VBANK_RELAY_IDENTITY_SEED` so
the id survives volume changes — otherwise update the record when it changes.

## Point the apps at it (other relays)

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
build/relay/bundle/bin/vbank_relay --data /var/lib/vbank-relay --port 4001 --public-host relay.example.com
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
