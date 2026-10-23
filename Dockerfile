# The Frontier exemplar app: TypeScript on Node, built in one stage and run
# from compiled JavaScript with production dependencies only in the next.
#
# Requirements for any Frontier app image, if you replace this one:
# - Listen on $PORT (Knative sets it; 8080 by default)
# - Keep the SOURCE_* ARG/LABEL block in the FINAL stage for image provenance.
#   deploy-dev.yaml and release.yaml pass the commit they build; skaffold passes
#   fresh git values for both local Docker and remote Kaniko.

FROM node:26-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:26-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist

# The base image's `node` user. Numeric, so Kubernetes' runAsNonRoot can verify it.
USER 1000:1000

ARG SOURCE_REPOSITORY
ARG SOURCE_REVISION
LABEL org.opencontainers.image.source=$SOURCE_REPOSITORY \
      org.opencontainers.image.revision=$SOURCE_REVISION
# dd-trace reports the commit as the `version` tag. Empty under a plain
# `docker build`, where dd-trace falls back to package.json's version.
# DD_GIT_COMMIT_SHA and DD_GIT_REPOSITORY_URL come from frontier-app-base.
ENV DD_VERSION=$SOURCE_REVISION

EXPOSE 8080
# dd-trace hooks ESM through --import, which is what auto-instruments express
# and outbound HTTP. With no agent reachable it starts and drops traces quietly.
CMD ["node", "--import", "dd-trace/initialize.mjs", "dist/index.js"]
