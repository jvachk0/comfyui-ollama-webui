FROM runpod/comfyui:cuda13.0@sha256:976ebfd8fe76d2899bbe31fbeb56970d2a409763aadff81377578842e27fe997

ARG OLLAMA_VERSION=0.32.6
ARG OLLAMA_SHA256=dec2fa50d24e6868ca3c4c977d69d059399372105f951a9acc320a5a79aadcfc

COPY zstdcat.c /tmp/zstdcat.c

# The base image contains libzstd.so.1 but no zstd executable. This is the
# exact libzstd streaming extraction path validated in the running Pod.
RUN set -eux; \
    mkdir -p /opt/ollama-dist; \
    curl -fL --retry 3 \
      -o /opt/ollama-dist/ollama-linux-amd64.tar.zst \
      "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst"; \
    printf '%s  %s\n' "${OLLAMA_SHA256}" /opt/ollama-dist/ollama-linux-amd64.tar.zst | sha256sum -c -; \
    cc -O2 -o /opt/ollama-dist/zstdcat /tmp/zstdcat.c /lib/x86_64-linux-gnu/libzstd.so.1; \
    /opt/ollama-dist/zstdcat </opt/ollama-dist/ollama-linux-amd64.tar.zst | tar -x -C /usr; \
    /usr/bin/ollama --version || true; \
    rm -f /opt/ollama-dist/ollama-linux-amd64.tar.zst

COPY requirements-open-webui.txt /opt/open-webui/requirements.txt

# PIP_CONSTRAINT belongs to the official ComfyUI runtime. It is suppressed
# only for commands in this independent venv.
RUN set -eux; \
    python3 -m venv /opt/open-webui/venv; \
    env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip install --no-cache-dir --upgrade pip; \
    env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip install --no-cache-dir -r /opt/open-webui/requirements.txt; \
    env -u PIP_CONSTRAINT /opt/open-webui/venv/bin/python -m pip check; \
    /opt/open-webui/venv/bin/python -c 'import open_webui, torch, transformers, sentence_transformers, chromadb, accelerate; print(torch.__version__); print(torch.__file__)'

COPY start.sh /opt/ollama-open-webui/start.sh
RUN chmod 0755 /opt/ollama-open-webui/start.sh

EXPOSE 3000 8188 8888

ENTRYPOINT ["/sbin/docker-init", "--"]
CMD ["/opt/ollama-open-webui/start.sh"]
