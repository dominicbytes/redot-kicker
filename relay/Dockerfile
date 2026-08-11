FROM node:24.18.0-alpine3.24@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src ./src
RUN npm run build
RUN npm prune --omit=dev --ignore-scripts

FROM node:24.18.0-alpine3.24@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS runtime

LABEL org.opencontainers.image.title="Redot Kicker Relay" \
      org.opencontainers.image.description="Self-hosted single-tenant Kick relay for Redot games" \
      org.opencontainers.image.source="https://github.com/dominicbytes/redot-kicker" \
      org.opencontainers.image.licenses="MIT"

ENV NODE_ENV=production
ENV REDOT_KICKER_HOST=0.0.0.0
ENV REDOT_KICKER_PORT=8080

WORKDIR /app
RUN mkdir -p /var/lib/redot-kicker && chown node:node /var/lib/redot-kicker
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist/src ./dist/src
COPY --chown=node:node package.json ./
COPY --chown=node:node LICENSE ./LICENSE

USER node
EXPOSE 8080
VOLUME ["/var/lib/redot-kicker"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:8080/v1/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]
CMD ["node", "dist/src/index.js"]
