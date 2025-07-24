# Dockerfile
FROM nvidia/cuda:12.2.0-base-ubuntu22.04

RUN apt update && \
    apt install -y python3 python3-pip procps curl gnupg2 && \
    pip3 install flask gunicorn

RUN apt-get install -y software-properties-common

RUN apt-get install -y curl gnupg2 ca-certificates lsb-release procps python3 python3-pip && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
    apt-get update && \
    apt-get install -y docker-ce-cli

COPY app.py /app/app.py
WORKDIR /app

CMD ["gunicorn", "-b", "0.0.0.0:8080", "app:app"]
