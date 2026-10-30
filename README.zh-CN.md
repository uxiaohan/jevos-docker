# jevos-docker

[English](README.md) · **中文**

把 [jevos-v5](https://github.com/feder-cr/jev)（OpenVINO INT8，纯 CPU 决策引擎）封成开箱即用的 Docker 镜像。

它不是 LLM。输入一段文本和若干问题，输出 yes/no 概率、最可能的选项或分数。原生 x86 上单次 30–130ms，不需要 GPU。

## 镜像

| 仓库 | tag |
|---|---|
| `ghcr.io/uxiaohan/jevos-docker` | `<短 sha>` / `latest` |
| `docker.io/uxiaohan/jevos` | `<短 sha>` / `latest` |

两个仓库是同一次构建推出来的，同一份镜像两个名字。生产环境请钉短 commit hash（6 位，如 `c7c497`）或 digest，`latest` 每次重新构建都会前移。

**仅支持 linux/amd64**：上游只发了 x86-64 的 Linux 二进制。Apple Silicon 上走 qemu 模拟，能跑，但慢一个数量级。

## 运行

### Docker Compose

存成 `compose.yaml`，然后 `docker compose up -d`：

```yaml
services:
  jevos:
    image: ghcr.io/uxiaohan/jevos-docker:latest   # 或 docker.io/uxiaohan/jevos:latest
    container_name: jevos
    restart: unless-stopped
    ports:
      - "8017:8017"
    environment:
      PORT: "8017"
      JEV_API_KEY: "change-me"          # 删掉这行即关闭鉴权
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

去掉 `-e JEV_API_KEY=...` 即无鉴权运行。完整变量见[配置](#配置)，钉版本见[镜像](#镜像)。

启动日志告诉你监听地址和鉴权方式，模型加载完成后打印 `healthy`：

```
[jevos] listening on http://0.0.0.0:8017
[jevos] auth: key change-me
jev: jevos-v5 on http://0.0.0.0:8017 (Bearer auth), ready in 6.1 s: 2 threads, {...}
[jevos] healthy
```

> API key 会明文打在日志里，方便你从 `docker logs` 里复制。别把容器日志外发到公开的地方。

## 调用

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

问题类型：

- `noul` — 是/否，返回「是」的概率
- `choice` — 多选一，`criteria` 是「选项 → 说明」的映射
- `score` — 在有序的 `criteria` 上返回期望档位

一次请求可以对同一段文本问多个问题，文本只读一遍。完整报文格式见[上游 README](https://github.com/feder-cr/jev)。

`/health` 不需要鉴权，还会返回三个模型文件的 SHA-256，可用于核对镜像里到底是什么模型。

## 配置

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8017` | 监听端口 |
| `THREADS` | 自动 | 推理线程数。默认按容器 CPU 限制推算（cgroup 配额，没有配额则看亲和性）——上游二进制自己只数宿主机核数，会把限核容器撑爆。只有要强制指定时才设 |
| `WARMUP` | `0` | 空闲时预热到多长的 prompt。`0` 关闭：空载不占 CPU，加载完成后内存不再增长，代价是某个新长度的第一次请求多花几毫秒编译 kernel。想要收回这点延迟再设 64–384 |
| `JEV_API_KEY` | 空 = 不鉴权 | 设置后所有请求需要 `Authorization: Bearer <key>`。`compose.yaml` 里默认 `change-me`，删掉该行即关闭鉴权 |

## 占用

- 镜像：690MB（拉取）/ 约 890MB（落盘），其中模型 667MB
- 内存：空载约 1GB，文本缓存跑满约 1.4GB
- 启动：约 3–6s（含模型加载）

**无状态**：模型烘在镜像里，其余全在内存，没有需要挂载的卷，`--read-only` 也能正常跑。

`compose.yaml` 里的 `mem_limit: 4g`：加载完约 1.6GB，状态缓存塞满再多约 0.3GB，而且空闲时不归还内存，所以要留余量。Apple Silicon 走 qemu 模拟内存约翻四倍，要调到 8g 以上。

## 重新构建

Actions → **docker** → **Run workflow**，填上游 release tag（默认 `jevos-v5`）。只有手动触发，推代码不会发版。

每次构建会推两个仓库，再把镜像拉回来实跑一次决策，断言 `noul > 0.5`。只绿构建不算过。

需要两个仓库 secret：`DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`（Docker Hub → Account settings → Security → New Access Token，读写权限）。GHCR 用内置的 `GITHUB_TOKEN`。Docker Hub 仓库首次推送后是私有的，去包设置里改成 public。

## 许可

镜像内的 jev 二进制与模型来自上游，许可见 `/opt/jev/LICENSE` 与 `/opt/jev/licenses/`。本仓库的 Dockerfile 与工作流为 MIT。
