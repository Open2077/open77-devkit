# The hosted Devkit MCP: Streamable HTTP on :8787, docs tools only (no
# filesystem, no Warden). Built from the repository so the embedded index
# snapshot ships with it; the container refreshes from the CDN like any other
# install. Runs as an unprivileged user with a read-only root; the index cache
# lives on a tmpfs.

FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
COPY index ./index
COPY skill ./skill
COPY README.md LICENSE ./
RUN npm run build && node dist/cli.js verify-index --dir index && npm prune --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production \
    PORT=8787 \
    OPEN77_MCP_CACHE=/tmp/open77-mcp
WORKDIR /app
COPY --from=build /src/package.json /src/README.md /src/LICENSE ./
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/dist ./dist
COPY --from=build /src/index ./index
COPY --from=build /src/skill ./skill
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD wget -qO- http://127.0.0.1:8787/healthz || exit 1
CMD ["node", "dist/cli.js", "serve-http", "--host", "0.0.0.0", "--port", "8787"]
