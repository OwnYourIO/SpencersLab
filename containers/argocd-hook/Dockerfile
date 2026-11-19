FROM python:3.11-slim-bookworm

# Relay never imports third-party modules; skip .pyc writes so the chart's
# read-only root filesystem stays sufficient.
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY main.py /app/main.py

# uid/gid 65532 (distroless nonroot convention). groupadd/useradd with pinned
# ids rather than reusing a system user: python:*-slim images ship colliding
# names/uids of their own, and only the pinned account is ours.
RUN groupadd --system --gid 65532 app \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
       --home /home/app --create-home app

USER app

EXPOSE 8080
ENTRYPOINT ["python3", "-u", "/app/main.py"]
