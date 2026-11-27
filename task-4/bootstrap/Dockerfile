FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade libzstd1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

RUN python -m pip install --no-cache-dir -r requirements.txt \
    && python -m pip uninstall -y setuptools wheel \
    && python -m pip check

COPY bootstrap.py .

RUN useradd --create-home --uid 10001 bootstrap

USER bootstrap

CMD ["python", "bootstrap.py"]
