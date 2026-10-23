# Persona Template Frontier App

Template repository for Frontier applications. Create a new repo from this template to deploy to the Frontier cluster.

See [go/frontier-usage](http://go/frontier-usage) for setup instructions, configuration, FAQ, and more.

## The app

A new repo starts with a small working TypeScript service: Express 5 on Node 26,
with Datadog APM on. Keep it and build on it, or replace it with your own stack.

- `GET /` is a Persona-branded landing page: the app's name and environment, a
  link to its Datadog APM service, this README, go/frontier-usage and the
  frontier-app-base config reference. When the app is internal (`visibility`
  `private` or `none`) it also shows **Build in Oracle**, the same button the
  Frontier UI shows on the app's page: describe a change and it opens a new
  Oracle chat that dispatches an Editor session on this repo.
- `GET /healthz` answers 200.

Run it locally (Node 22 or later; production runs Node 26):

```sh
npm ci
npm run dev        # http://localhost:8080, restarts on change
npm test           # unit tests (vitest)
npm run typecheck
```

Outside the cluster `FRONTIER_APP_NAME` is unset, so `npm run dev` takes the
app's name from `kubernetes/jsonnet/common/app.libsonnet` (the `name:` field
Frontier sets when it generates the repo). That name drives the page title,
the README link and the Build in Oracle prompt.

| Where | What to change |
|-------|----------------|
| `src/app.ts` | Routes |
| `src/page.ts` | The landing page |
| `src/config.ts` | Settings read from the environment |
| `src/oracle.ts` | The Build in Oracle prompt, copied from persona-frontier-ui's `frontierLinks.ts`; keep them in step |
| `kubernetes/jsonnet/common/config.libsonnet` `env` | Environment variables for every environment |
| `Dockerfile` | The image. Keep the final stage's `SOURCE_*` block (see below) |

### Datadog APM

The image starts the app with `node --import dd-trace/initialize.mjs`, which
traces Express and outbound HTTP with no code changes. `kubernetes/jsonnet` sets:

| Variable | Value |
|----------|-------|
| `DD_AGENT_HOST` | `datadog-agent.datadog.svc.cluster.local` |
| `DD_SERVICE` | the app's name, from `common/app.libsonnet` |
| `DD_ENV` | `production` or `development`, from each environment's `config.libsonnet` |
| `DD_VERSION` | the commit the image was built from (Dockerfile) |

frontier-app-base adds `DD_GIT_COMMIT_SHA` and `DD_GIT_REPOSITORY_URL`. Traces
show up at `https://app.datadoghq.com/apm/entity/service%3A<name>?env=<env>`,
linked from the landing page. Locally there is no agent, and dd-trace drops
traces quietly.

`env` is a list, and lists replace rather than merge across config layers, so
`production/config.libsonnet` and `development/config.libsonnet` extend common's
list with `common.env + [...]`. Do the same when you add a per-environment
variable.

## How it deploys

ArgoCD deploys the app. GitHub Actions only build and push images.

1. Frontier registers the repo in
   [frontier-app-registry](https://github.com/persona-id/frontier-app-registry). An
   ApplicationSet there renders `kubernetes/deploy`, which holds one ArgoCD
   Application per environment.
2. Each Application renders `kubernetes/jsonnet/<env>/main.jsonnet` with the
   [frontier-app-base](https://github.com/persona-id/jsonnet-libs/tree/main/frontier-app-base)
   library, and passes the commit sha it resolved as the image tag.

| Environment | Namespace | Follows | Image pushed by |
|-------------|-----------|---------|-----------------|
| development | `frontier-<name>-dev` | the `frontier-dev` branch | `deploy-dev.yaml`, on each push to `frontier-dev` |
| production | `frontier-<name>-prod` | the highest `vX.Y.Z` release | `release.yaml`, on each merge to `main`, which then publishes the next patch release |

To roll production back, have ArgoCD sync an older release. To bump the minor or
major version, publish a release by hand (`vX.Y+1.0`); later merges bump the patch
from there.

`make dev` deploys your working copy to your own namespace,
`frontier-<name>-dev-<you>`, outside ArgoCD. `make help` lists the other targets.

## Configuration

| File | What it holds |
|------|---------------|
| `kubernetes/jsonnet/common/app.libsonnet` | The app's name, which must be the repository's name |
| `kubernetes/jsonnet/common/config.libsonnet` | Config shared by every environment: owner, visibility, routes, Valkey, background jobs, ... |
| `kubernetes/jsonnet/<env>/config.libsonnet` | Per-environment overrides |
| `kubernetes/jsonnet/<env>/secrets.libsonnet` | Sealed secrets for that environment, written by `bin/create-secret` |

Every option and its default is in frontier-app-base's
[`config.libsonnet`](https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet).
To render an environment the way ArgoCD does:

```sh
cd kubernetes/jsonnet
jsonnet -J vendor --tla-str imageTag="$(git rev-parse HEAD)" production/main.jsonnet
```

ArgoCD doesn't run `jb install`, so the libraries are committed under
`kubernetes/jsonnet/vendor`. To pick up a new jsonnet-libs release, run `jb update`
in `kubernetes/jsonnet` and commit the result.

## Deploy source provenance

Every deploy records where it came from in frontier-app-base's `source.repository`,
`source.revision` and `source.dirty`. The library annotates Services/revisions,
workers/pods and scheduled jobs, and defaults Datadog's git env vars. A provenance
change creates a new Knative revision even if the image is unchanged.

- **ArgoCD deploys** record the repository and the commit ArgoCD rendered, never dirty.
- **`make dev`** records what `bin/source-provenance` reads when it starts: the
  checked-out HEAD, the origin normalized to a credential-free GitHub HTTPS URL, and
  whether tracked, staged or untracked files changed (ignored files don't count).
  Commits made while `make dev` runs aren't recorded until it restarts. It never
  blocks a deploy: a value it can't determine (no or non-GitHub origin, not a git
  checkout) is recorded empty, with a warning on stderr.

The Dockerfile's final-stage `ARG`/`LABEL` block records OCI image source/revision;
keep it if you replace the Dockerfile. The image workflows pass the
commit they build, and skaffold passes fresh values on every local build.

Run `python3 -m unittest discover -s tests -v` for the provenance and
`bin/create-secret` contract tests.

## Dependency Updates

Dependabot PRs approve and merge themselves once CI passes, via [.github/workflows/dependabot-automerge.yaml](.github/workflows/dependabot-automerge.yaml). Two repo settings have to be on:

- Settings > Actions > General: allow GitHub Actions to create and approve pull requests
- Settings > Advanced Security: Dependabot security updates (on by default for new persona-id repos)
