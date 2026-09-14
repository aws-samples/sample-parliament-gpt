# Bedrock AgentCore runtime container for the Bundestag agent.
# Multi-stage, non-root, minimal.
# Debian pinned to trixie (13, current stable): `python:3.12-slim` re-targets new Debian releases over
# time, which would swap the whole OS underneath a routine rebuild. Security patches for
# the pinned release are applied explicitly below.
FROM public.ecr.aws/docker/library/python:3.12-slim-trixie@sha256:78387bc3881b8273120a12ebe6c1ab22b018ccc2c9adf565ae1ac9b536e184ea AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Apply Debian security updates: the base image lags the security repos, so patched
# package versions (gnutls, glibc, systemd libs, dpkg, ...) are pulled at build time.
# The stamp busts the layer cache so `apt-get upgrade` actually runs on a rebuild
# instead of replaying a weeks-old cached layer. scripts/bump-base-images.sh moves it.
ARG OS_PATCH_STAMP=2026-08-19
RUN echo "os-patch-stamp: $OS_PATCH_STAMP" \
  && apt-get update \
  && apt-get -y upgrade \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# System deps kept minimal; no build toolchain needed for pure-python wheels.
RUN useradd --create-home --uid 10001 appuser

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
ENV PYTHONPATH=/app/src

USER appuser

# AgentCore runtime contract: container serves the agent. The BedrockAgentCoreApp
# exposes the required HTTP contract on 0.0.0.0:8080 when run.
EXPOSE 8080
# Liveness for local runs and image scanners, against the AgentCore /ping contract;
# the managed runtime performs its own health checking and ignores this.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/ping', timeout=3).status==200 else 1)"]
CMD ["python", "-m", "parlamentgpt_agent.main"]
