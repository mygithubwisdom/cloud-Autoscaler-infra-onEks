FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY bootstrap.py .

RUN useradd --create-home --uid 10001 bootstrap

USER bootstrap

CMD ["python", "bootstrap.py"]
