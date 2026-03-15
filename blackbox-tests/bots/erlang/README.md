# Snatch Echo Bot

Echo bot for blackbox performance testing using the Erlang Snatch library.

## Build

```bash
rebar3 escriptize
```

Or build with Docker (no local Erlang toolchain needed):

```bash
docker build -t rnatch/snatch-echo-builder:latest .
container_id="$(docker create rnatch/snatch-echo-builder:latest)"
mkdir -p _build/default/bin
docker cp "$container_id:/opt/snatch-echo/_build/default/bin/snatch_echo" "_build/default/bin/snatch_echo"
docker rm "$container_id"
chmod +x _build/default/bin/snatch_echo
```

## Run

```bash
./_build/default/bin/snatch_echo \
  --xmpp-host localhost \
  --xmpp-port 5275 \
  --xmpp-domain echo.localhost \
  --xmpp-password secret
```
