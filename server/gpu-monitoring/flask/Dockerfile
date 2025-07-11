FROM nvidia/cuda:12.2.0-base-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3-pip python3-dev gcc g++ libgl1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install flask docker gunicorn

COPY app.py /app.py
COPY templates /templates

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
