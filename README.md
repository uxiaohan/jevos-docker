# jevos-docker

**English** · [中文](README.zh-CN.md)

[jevos-v5](https://github.com/feder-cr/jev) as a ready-to-run Docker image — the OpenVINO INT8 decision engine, CPU only.

It is not an LLM. You send a piece of text and a set of questions; it answers with yes/no probabilities, the most likely option, or a score. 30–130 ms per request on a native x86 CPU, no GPU required.

## Images

| Registry | Tags |
|---|---|
| `ghcr.io/uxiaohan/jevos-docker` | `<short sha>` / `latest` |
| `docker.io/uxiaohan/jevos` | `<short sha>` / `latest` |

Both registries get the same build, pushed once — same image, two names. Pin the short commit hash (6 chars, e.g. `c7c497`) or the digest in production: `latest` moves on every rebuild.

**linux/amd64 only.** Upstream ships an x86-64 Linux binary and nothing else. On Apple Silicon it runs under qemu emulation — it works, but roughly 10× slower.

## Run

### Docker Compose

Save this as `compose.yaml` and run `docker compose up -d`:

```yaml
services:
  jevos:
    image: ghcr.io/uxiaohan/jevos-docker:latest   # or docker.io/uxiaohan/jevos:latest
    container_name: jevos
    restart: unless-stopped
    ports:
      - "8017:8017"
    environment:
      PORT: "8017"
      JEV_API_KEY: "change-me"          # delete this line to disable auth
      WARMUP: "0"
    mem_limit: 4g
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### docker run

```bash
docker run -d --name jevos --restart unless-stopped \
  -p 8017:8017 \
  -e PORT=8017 \
  -e JEV_API_KEY=your-key \
  -e WARMUP=0 \
  --memory=4g \
  uxiaohan/jevos:latest
```

Drop `-e JEV_API_KEY=...` to run without authentication. See [Configuration](#configuration) for the full variable list, and [Images](#images) for pinning a build.

The log tells you where it listens and whether auth is on; `healthy` is printed once the model is loaded:

```
[jevos] listening on http://0.0.0.0:8017
[jevos] auth: key change-me
jev: jevos-v5 on http://0.0.0.0:8017 (Bearer auth), ready in 6.1 s: 2 threads, {...}
[jevos] healthy
```

> The API key is printed in plain text so you can copy it from `docker logs`. Don't ship container logs somewhere public.

## API

```bash
curl http://127.0.0.1:8017/health

curl http://127.0.0.1:8017/v1/systemone \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer your-key' \
  -d '{
    "model": "jevos-v5",
    "state": "My invoice shows a charge I do not recognize.",
    "questions": {
      "billing": {"type": "noul", "instructions": "Is this a billing problem?"}
    }
  }'
```

```json
{"model":"jevos-v5","answers":{"billing":{"type":"noul","noul":0.97}},"usage":{"input_tokens":28,"output_tokens":0}}
```

Question types:

- `noul` — yes/no, returns the probability of "yes"
- `choice` — one of several options, with `criteria` mapping label → description
- `score` — expected level over ordered `criteria`

Several questions can be asked about the same text in one request; it is read only once. Full wire format: [upstream README](https://github.com/feder-cr/jev).

`/health` needs no auth and returns the SHA-256 of the three model files — useful to verify what is actually inside the image.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8017` | Listen port |
| `THREADS` | auto | Inference threads. Defaults to the container's CPU limit (cgroup quota, else the affinity mask) — the binary on its own counts host CPUs and oversubscribes a limited container. Set it only to force a value |
| `WARMUP` | `0` | Prompt lengths `1..N` the server warms while idle, at the cost of idle CPU and memory. `0` disables it: nothing to warm, no growth after load, and the first request at a new token length pays a few ms building its kernels. Raise it (64–384) only if you want that latency back |
| `JEV_API_KEY` | empty = no auth | When set, every request needs `Authorization: Bearer <key>`. `compose.yaml` ships `change-me`; delete the line to disable auth |

## Footprint

- Image: 690 MB download / ~890 MB on disk, of which 667 MB is the model
- Memory: ~1 GB idle, ~1.4 GB with the text cache full
- Startup: ~3–6 s (model load)

**No state.** The model is baked into the image and everything else lives in memory, so there are no volumes to mount — the container also runs fine with `--read-only`.

`compose.yaml` sets `mem_limit: 4g`: budget roughly 1.6 GB after loading plus up to ~0.3 GB once the state cache fills, and the process does not hand memory back while idle — so leave headroom. Under Apple Silicon emulation memory roughly quadruples; give it 8g+.

## Rebuilding

Actions → **docker** → **Run workflow**, with the upstream release tag (default `jevos-v5`). It is manual only; pushing code does not publish anything.

Each run builds, pushes to both registries, then pulls the image back and runs a real decision, asserting `noul > 0.5`. A green build alone does not pass.

Required repo secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (Docker Hub → Account settings → Security → New Access Token, read/write). GHCR uses the built-in `GITHUB_TOKEN`. The Docker Hub repository is private on first push — flip it to public in the package settings.

## License

The jev binary and model inside the image come from upstream; see `/opt/jev/LICENSE` and `/opt/jev/licenses/`. The Dockerfile and workflows in this repo are MIT.
