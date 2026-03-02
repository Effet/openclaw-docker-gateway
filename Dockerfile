FROM node:22
RUN apt-get update && apt-get install -y supervisor && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
