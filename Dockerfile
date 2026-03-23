FROM node:22-slim AS build
RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM node:22-slim
RUN apt-get update && apt-get install -y git python3 make g++ curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

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

# Install Railway CLI v4.33.0 via direct tarball (bypasses install script GitHub API call).
# Binary is renamed to railway-bin; a wrapper script gates access by checking
# $AGENT_ID against $RAILWAY_ALLOWED_AGENTS CSV list.
ARG RAILWAY_VERSION=4.33.0
RUN curl -fsSL "https://github.com/railwayapp/cli/releases/download/v${RAILWAY_VERSION}/railway-v${RAILWAY_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /usr/local/bin \
    && mv /usr/local/bin/railway /usr/local/bin/railway-bin \
    && printf '#!/bin/sh\n\
if [ -z "$AGENT_ID" ]; then\n\
  echo "ERROR: AGENT_ID not set. Cannot verify authorization." >&2\n\
  exit 1\n\
fi\n\
if [ -z "$RAILWAY_ALLOWED_AGENTS" ]; then\n\
  echo "ERROR: RAILWAY_ALLOWED_AGENTS not set. No agents are authorized." >&2\n\
  exit 1\n\
fi\n\
case ",$RAILWAY_ALLOWED_AGENTS," in\n\
  *",$AGENT_ID,"*) ;;\n\
  *) echo "ERROR: Agent $AGENT_ID is not authorized to use Railway CLI." >&2; exit 1 ;;\n\
esac\n\
exec railway-bin "$@"\n' > /usr/local/bin/railway \
    && chmod +x /usr/local/bin/railway

ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "dist/main.js"]
