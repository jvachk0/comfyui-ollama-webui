# Reproducible RunPod ComfyUI + Ollama + Open WebUI image

This project reproduces the configuration validated in the running official RunPod Pod on 2026-08-08. It has not been built or pushed yet.

## Exact base image

The read-only RunPod Pod API returned:

```text
imageName:  runpod/comfyui:cuda13.0
templateId: 2lv7ev3wfp
```

Docker Hub's OCI registry returned:

```text
OCI index:           sha256:976ebfd8fe76d2899bbe31fbeb56970d2a409763aadff81377578842e27fe997
linux/amd64 manifest: sha256:b4a3c477f59dd5c53da6efd291e000c058987b897b311504dfebc2b6f559e37f
base compressed layers: 4,305,813,777 bytes (4.306 GB decimal)
```

The Dockerfile pins the index digest in `FROM`; Docker selects its linux/amd64 manifest. A tag alone would remain mutable.

## Files

- `Dockerfile`: exact base, pinned Ollama installation, isolated Open WebUI venv, ports and entrypoint.
- `start.sh`: runtime wrapper; starts Ollama and Open WebUI, then executes the untouched official `/start.sh`.
- `requirements-open-webui.txt`: direct Open WebUI pin.
- `versions.env`: audited version and digest inventory.
- `zstdcat.c`: minimal extractor needed because the exact base has `libzstd.so.1` but no `zstd` executable.

## Commands copied from the working Pod

The following are direct transfers of commands that succeeded in the experiment:

```bash
curl -fL --retry 3 -o /opt/ollama-dist/ollama-linux-amd64.tar.zst \
  https://github.com/ollama/ollama/releases/download/v0.32.6/ollama-linux-amd64.tar.zst
printf '%s  %s\n' dec2fa50d24e6868ca3c4c977d69d059399372105f951a9acc320a5a79aadcfc \
  /opt/ollama-dist/ollama-linux-amd64.tar.zst | sha256sum -c -
cc -O2 -o /opt/ollama-dist/zstdcat zstdcat.c /lib/x86_64-linux-gnu/libzstd.so.1
/opt/ollama-dist/zstdcat </opt/ollama-dist/ollama-linux-amd64.tar.zst | tar -x -C /usr

python3 -m venv /opt/open-webui/venv
env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip install --upgrade pip
env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip install open-webui==0.11.0
env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip check
```

The successful resolver result contains Open WebUI `0.11.0`, Torch `2.13.0+cu130` and its own CUDA 13 wheels. System/ComfyUI Torch remains `2.10.0+cu130`.

## Startup behavior

No program is installed or downloaded by `start.sh`.

1. Creates `/workspace/ollama`, `/workspace/open-webui/data`, and `/workspace/logs`.
2. Uses a supplied `WEBUI_SECRET_KEY`. If absent, creates a mode-0600 persistent key at `/workspace/open-webui/.webui_secret_key` and reuses it on later starts.
3. Starts Ollama with `OLLAMA_HOST=127.0.0.1:11434` and waits for `/api/tags`.
4. Starts Open WebUI at `0.0.0.0:3000` with authentication/login enabled and waits for `/ready`.
5. Executes the original RunPod `/start.sh`, which continues to own SSH, FileBrowser, Jupyter and ComfyUI startup.

For production, pass `WEBUI_SECRET_KEY` as a RunPod secret. The persistent-file fallback preserves authentication sessions when `/workspace` is persistent. The value must never be baked into the image.

Published by Docker metadata:

```text
3000 Open WebUI
8188 ComfyUI
8888 Jupyter
```

Ollama `11434` is deliberately neither exposed nor externally bound. In RunPod, configure `3000/http`, `8188/http`, and `8888/http`; do not add `11434`.

## Embedding cache alternatives

Open WebUI `0.11.0` loaded `sentence-transformers/all-MiniLM-L6-v2` during the validated first startup. It is an embedding model, not an Ollama LLM.

### A — do not bake it

- Default cache path in the validated runtime: `/root/.cache/huggingface`.
- Measured cache size: approximately `889M` (`du` units).
- Startup effect: the validated first readiness took 22 seconds on a fast connection and downloaded the model repository; slower/rate-limited networking increases this and offline first startup may fail or be degraded.
- Advantage: smaller base image and easy upstream model refresh.
- Disadvantages: first-start network dependency, variable readiness time, and cache is lost unless its path is persisted.

The current Dockerfile represents this alternative and does not prefetch the model.

### B — bake the cache

After Open WebUI installation, add a Docker build step equivalent to:

```dockerfile
ENV HF_HOME=/opt/open-webui/hf-cache
RUN env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -c \
    'from sentence_transformers import SentenceTransformer; SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")'
```

- Image cache path: `/opt/open-webui/hf-cache`.
- Measured comparable runtime cache: approximately `889M` unpacked; compressed registry growth is expected to be lower but must be measured by an actual build.
- Startup effect: removes this model download and makes first readiness more deterministic/offline-capable.
- Advantages: repeatable first start and no Hugging Face rate-limit dependency at runtime.
- Disadvantages: larger image, a model revision becomes implicitly pinned to build time unless an exact Hugging Face revision is specified, and updates require rebuilding.

No alternative has been applied to a built image; the two choices remain documented for the next decision.

## Expected image size

Measured additions in the working Pod:

```text
Open WebUI venv                         6.9G unpacked
  Torch package                        1.1G
  separate NVIDIA/CUDA wheels          2.7G
Ollama installed tree                  2.1G
retained Ollama distribution archive   1.4G
pip cache generated by install         3.3G
optional HF embedding cache (B)        889M
```

For strict first-pass reproduction, the Dockerfile does not optimize these. It can therefore add roughly `13.7G` unpacked beyond the base for option A, or roughly `14.6G` with option B. Registry-compressed size cannot be exact without the forbidden build; a reasonable planning range is approximately `11–14 GB` total for A and up to roughly another `0.4–0.9 GB` for B. The exact base alone is `4.306 GB` compressed.

## Later optimization candidates (not applied)

- Use `pip --no-cache-dir` or a BuildKit cache mount so the `3.3G` pip cache is not stored in the final layer.
- Remove the retained `1.4G` Ollama archive after checksum-verified extraction.
- Investigate sharing the base CUDA/Torch stack only after compatibility testing; currently the independent stack is intentional.
- Pin the complete Python transitive lock with hashes rather than only the direct Open WebUI version.
- Pin an exact Hugging Face model revision if choosing option B.
- Run services under dedicated non-root users and add a production CORS policy.

These are deliberately deferred until the first image reproduces the proven Pod behavior.

## Future build command (not executed)

```bash
docker build -t YOUR_REGISTRY/runpod-comfy-ollama-webui:2026-08-08 ./docker-image
```

No build, push, template update, or startup modification was performed during project generation.
