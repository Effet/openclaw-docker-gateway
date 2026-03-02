#!/bin/sh
# Fix ownership of bind-mounted volumes so the node user can write to them.
chown -R node:node \
  /home/node/.npm-global \
  /home/node/.openclaw \
  /home/node/.openclaw/workspace \
  2>/dev/null || true

exec "$@"
