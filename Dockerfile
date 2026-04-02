FROM node:22-slim AS build
RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM node:22-slim
RUN apt-get update && apt-get install -y git jq python3 make g++ curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY --from=build /app/skills ./skills

# Create global symlinks for lettabot CLI binaries (lettabot-message, lettabot-schedule, etc.)
# Required for heartbeat (silent mode), scheduling, reactions, and channel management
RUN npm link

# Stub out system scheduling tools that don't exist in containers.
# Agents may try cron/crontab/systemctl/at before discovering lettabot-schedule.
# These stubs give immediate, actionable feedback instead of silent failures.
RUN for cmd in crontab cron systemctl systemd at atd; do \
      printf '#!/bin/sh\necho "ERROR: %s is not available in this container. Use lettabot-schedule instead." >&2\necho "  lettabot-schedule create --name \"Job\" --schedule \"0 8 * * *\" --message \"Hello\"" >&2\nexit 1\n' "$cmd" \
        > /usr/local/bin/$cmd && chmod +x /usr/local/bin/$cmd; \
    done

ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "dist/main.js"]
