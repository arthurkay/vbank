# vBank relay node

Members' phones sit behind mobile-network NAT and cannot accept connections, so
two phones on different networks never reach each other directly. A **relay** is
a small always-on vBank peer with a public address. Every device dials it out,
pushes its records to it and pulls what it lacks from it — joins, sync and
notifications then work from anywhere, and records for members who are offline
wait on the relay until they next open the app.

**What the relay can and cannot see:** every record is encrypted on the device
with the group passphrase-derived key before it is sent. The relay stores opaque
blocks under opaque group ids and learns only which peers talk about which group
id. It never holds a group key and cannot read amounts, names or anything else.

**The default relay.** Every copy of vBank ships knowing one relay host,
**`vbank.localhost.co.zm`** (`kBuiltInRelayHosts` in
`lib/core/relay/relay_directory.dart`). Only the hostname is in the app: the
relay's peer id is published as a DNS TXT record (the libp2p `dnsaddr`
convention) and the app looks it up over DNS-over-HTTPS at most hourly, keeping
the last good answer for offline starts. Rotating or moving the relay therefore
never needs an app update. Members can switch the built-in relay off and add
their own.

The container image is **`ghcr.io/arthurkay/vbank-relay`** (`latest` = main,
plus one tag per release such as `1.7.0`), built by
`.github/workflows/relay-image.yml`. It runs as an unprivileged user (uid 10001)
and keeps its data in `/data`.

---

## Deploying the default relay (vbank.localhost.co.zm)

You need: a Linux VPS with a public IPv4 (1 vCPU / 512 MB is plenty), Docker
with the compose plugin, and access to the DNS zone of `localhost.co.zm`.

### 1. DNS: point the name at the server

```
vbank.localhost.co.zm.   IN A   <VPS public IPv4>
```

Wait until `dig +short vbank.localhost.co.zm` returns the IP.

### 2. Open the port

Allow inbound **TCP 4001** in the VPS firewall / cloud security group (and
`ufw allow 4001/tcp` if ufw is on). Nothing else needs to be open.

### 3. Install and start

```sh
sudo mkdir -p /opt/vbank-relay && cd /opt/vbank-relay
sudo curl -fsSLO https://raw.githubusercontent.com/arthurkay/vbank/main/deploy/relay/docker-compose.yml
sudo curl -fsSLo .env https://raw.githubusercontent.com/arthurkay/vbank/main/deploy/relay/.env.example

# Generate the identity ONCE and put it in .env (this fixes the /p2p/… id).
sudo sed -i "s|^VBANK_RELAY_IDENTITY_SEED=.*|VBANK_RELAY_IDENTITY_SEED=$(openssl rand -base64 32)|" .env
sudo chmod 600 .env

sudo docker compose pull && sudo docker compose up -d
sudo docker compose logs relay | grep "relay address"
```

`.env` already names `vbank.localhost.co.zm` as the public host. The log prints
the address members will use:

```
[relay] relay address: /dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooW…
```

**Back up `.env` now** (a password manager is fine). It holds the identity seed;
with it you can rebuild the relay on any server and keep the same address.

### 4. DNS: publish the address for the app

Take the `/p2p/…` part from the log and add the TXT record:

```
_dnsaddr.vbank.localhost.co.zm.   IN TXT   "dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooW…"
```

Verify from anywhere:

```sh
dig +short TXT _dnsaddr.vbank.localhost.co.zm
curl -s 'https://cloudflare-dns.com/dns-query?name=_dnsaddr.vbank.localhost.co.zm&type=TXT' -H 'accept: application/dns-json'
```

The second command is exactly what the app does. Once it returns the record,
every install picks the relay up on its next lookup: within five minutes while
the record was missing, otherwise within the hour, and immediately on the next
app start.

### 5. Check from the app

Settings → Sync status shows **"vBank relay · vbank.localhost.co.zm — On · 12D3KooW…"**
and the activity log gains `Connected to relay /dns4/vbank.localhost.co.zm/…`.
On the server, `docker compose logs -f relay` shows `stored`/`forwarded` lines as
members sync. Two devices on different networks (one on mobile data) should now
see each other's records within a sync round (~2 minutes).

---

## Operations

* **Upgrading:** `cd /opt/vbank-relay && sudo docker compose pull && sudo docker compose up -d`.
  Identity comes from `.env`, blocks from the `relay-data` volume; both survive.
* **Moving to another server:** copy `.env` and `docker-compose.yml`, start the
  container, then change the A record. The `/p2p/…` id is unchanged, so the TXT
  record stays valid. Blocks are re-pushed by members' devices within a few
  rounds — the relay is a cache, devices are the source of truth.
* **Rotating the identity** (seed leaked or lost): set a new seed, restart, and
  update the TXT record with the new `/p2p/…`. Apps follow within an hour.
* **A second relay:** deploy another instance and add a second `dnsaddr=`
  TXT record, or let groups add it themselves (below). The app uses all of them.
* **Disk:** blocks are a few KB; a busy group produces well under a megabyte a
  month. Ledger: `relay_ledger.json` in the volume.
* **Logs:** one line per stored block / forwarded notification, a heartbeat every
  10 minutes. `VBANK_RELAY_VERBOSE=1` adds libp2p detail.
* **Reboots:** `restart: unless-stopped` brings the container back.

### Troubleshooting

| Symptom | Check |
| --- | --- |
| App says "Looking up its address…" for more than an hour | `dig +short TXT _dnsaddr.vbank.localhost.co.zm` must return the `dnsaddr=` record; the value must contain `/p2p/`. |
| App log: `Relay unreachable /dns4/vbank.localhost.co.zm/...` | Port 4001 closed, or the A record points elsewhere: `nc -vz vbank.localhost.co.zm 4001` from another network. |
| Address in the log differs from the TXT record | `.env` seed changed or missing → the relay generated a new identity. Restore `.env` or update the record. |
| `did not take <cid>` warnings on a device, once, right after connecting | Normal: the first request over a fresh connection can time out while the relay warms up; the next round reconciles. |

---

## Other relays (per group)

Groups can run their own relay with the same image; use their own hostname in
`VBANK_RELAY_PUBLIC_HOST` (or `VBANK_RELAY_PUBLIC_IP` for a bare IP) and skip
the TXT record. Then on the group owner's device: **Settings → Sync status →
Relay server → Add**, paste the address from the log. Every invite link the
owner creates carries it (`relay=`), so new members are configured
automatically; existing members can paste it too. The built-in relay can be
switched off there as well.

## Building the image yourself

```sh
docker build -f deploy/relay/Dockerfile -t vbank-relay .     # from the repository root
```

and set `image: vbank-relay` in the compose file. Without Docker:

```sh
dart pub get
dart build cli -t bin/vbank_relay.dart -o build/relay          # bundle/bin/vbank_relay + bundle/lib/*.so
build/relay/bundle/bin/vbank_relay --data /var/lib/vbank-relay --port 4001 \
  --public-host vbank.localhost.co.zm --identity-seed "$(cat seed.b64)"
```

(`dart compile exe` refuses because some dependencies use native build hooks.)
A systemd unit only needs `ExecStart` pointing at that command and `Restart=always`.
Flags mirror the environment variables: `--data`, `--port`, `--public-host`,
`--public-ip`, `--public-port`, `--identity-seed`, `--verbose`.
