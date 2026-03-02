FROM node:22
RUN apt-get update && apt-get install -y supervisor && rm -rf /var/lib/apt/lists/*
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global \
    PATH="/home/node/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
