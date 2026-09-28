# Ziren backend — FastAPI + the trained triage model + optional speech-to-text.
#
# The Whisper ASR model (faster-whisper-small, ~500MB) is downloaded during
# this build and baked into the image, matching the exact call
# app/services/asr_engines.py makes at runtime (same model size, compute
# type, and download_root). That way a fresh container never needs network
# access to Hugging Face at startup, and a redeploy doesn't re-download it.
#
# To build without the ASR model (smaller image, faster build, voice notes
# still stored and playable — see asr_engines.py's docstring on why that's a
# supported state, not a broken one): pass --build-arg BAKE_ASR=false.

FROM python:3.11-slim

WORKDIR /app

# libpq for psycopg2 in case the platform resolves a source dist instead of
# the manylinux wheel; harmless extra ~30MB if unused.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# A plain glob (not "COPY app public ./") so the build doesn't fail on a
# fresh checkout where public/downloads hasn't been created yet — it's
# git-ignored (a build artefact, not source; see main.py's comment on the
# /download mount) and also excluded from a normal `railway up` for the same
# reason (see .railwayignore). Ship the APK there and deploy with
# `railway up --no-gitignore` if you want it served; if it's absent the app
# still starts, just without that mount.
#
# Dest must be "./public/", not "./" — a glob-matched directory copies its
# CONTENTS into dest (same as a plain directory COPY), so "./" would land
# the contents of local public/ (i.e. "downloads/") directly at /app/downloads
# instead of /app/public/downloads, which is what main.py's mount looks for.
COPY app ./app
COPY public* ./public/

ARG BAKE_ASR=true
RUN if [ "$BAKE_ASR" = "true" ]; then \
      python -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8', download_root='/app/app/ml/asr_models')"; \
    fi

EXPOSE 8000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
