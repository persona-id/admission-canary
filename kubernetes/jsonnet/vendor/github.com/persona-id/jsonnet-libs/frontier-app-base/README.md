# frontier-app-base

Everything a Frontier app deploys, built from one config object: its namespace and
who may manage it, the Knative service, who may reach it, background workers and scheduled jobs, Valkey, secrets, GCS buckets
and Mongo.

This is the jsonnet port of the `frontier-app-base` Helm chart in
[persona-frontier-base](https://github.com/persona-id/persona-frontier-base). It
takes the same options under the same keys, so an app's `deploy/values.yaml`
converts to a config object key for key. Objects are built with
[k8s-libsonnet](https://github.com/jsonnet-libs/k8s-libsonnet) and the jsonnet-libs
packages for Knative Serving, Istio and GCP Config Connector.

## Install

```sh
jb install github.com/persona-id/jsonnet-libs/frontier-app-base@main
```

jb pulls in the libraries this one depends on (see `jsonnetfile.json`). They rely on
jb's `legacyImports` (the default), which provides the `doc-util` import path.

## Usage

```jsonnet
local frontier = import 'github.com/persona-id/jsonnet-libs/frontier-app-base/main.libsonnet';

frontier.new({
  appName: 'my-app',
  namespace: 'frontier-my-app-prod',
  permissions: { owner: 'jane.doe', additionalCollaborators: ['sam.smith'] },
  image: { repository: 'ghcr.io/persona-id/my-app', tag: 'abc123' },

  routes: [
    { paths: ['/webhooks/*'], humans: 'anyone' },
    { paths: ['/*'], humans: 'okta' },
  ],
  backgroundJobs: {
    enabled: true,
    workers: [{ name: 'sidekiq', command: ['bundle', 'exec', 'sidekiq'], replicas: 2 }],
  },
  jobQueue: { enabled: true, client: 'sidekiq' },
})
```

`new` returns an object of Kubernetes objects, nested by component, which Tanka
renders as-is:

| Field | Contents |
|-------|----------|
| `namespace` | The app's Namespace |
| `roleBindings` | Keyed by name: `owner-edit`, `owner-crd-access`, and `collaborator-edit-<user>` and `collaborator-crd-access-<user>` for each collaborator |
| `serviceAccount`, `service` | The `app` ServiceAccount and Knative Service |
| `podDisruptionBudget` | When `podDisruptionBudget.enabled` and `scaling.minScale` is 2 or more |
| `authorizationPolicy`, `peerAuthentication`, `allowIntraNamespace` | The app's default-deny policy (`app-s2s`), its STRICT mTLS, and the allowance for its own namespace |
| `domainMappings` | Keyed by fqdn |
| `mongoDatabase` | When `mongo.enabled` |
| `ssoRequireAuth`, `ssoRequestAuthentication` | When a route has `humans: okta` (the second only when it sets `groups` or `emails`) |
| `workers`, `scheduledJobs` | Keyed by normalized name, when `backgroundJobs.enabled` |
| `valkey`, `jobQueue` | Each an instance: `serviceAccount`, `configMap`, `persistentVolumeClaim`, `service`, `deployment`, `peerAuthentication`, `authorizationPolicy` |
| `onePasswordItems`, `sealedSecrets` | Keyed by normalized name |
| `gcsStorageBuckets` | Keyed by name, each with `bucket` and `iamPolicy` (an IAMPartialPolicy) |

Any object can be patched with `+`:

```jsonnet
frontier.new(config) + {
  service+: { metadata+: { annotations+: { 'example.com/owner': 'my-team' } } },
}
```

Outside Tanka, `frontier.toList(frontier.new(config))` flattens the result into a
plain list of objects for `kubectl apply`.

## Preview environments

`frontier.preview(config, prNumber)` renders a pull request's preview environment
from the app's merged development config. persona-kubernetes deploys it for each pull
request labelled `preview-env` and deletes it when the pull request closes or loses
the label. It returns what `new` returns, with these differences:

- Everything lands in `<dev namespace>-pr-<prNumber>`, served at
  `app-<that namespace>.<visibility>.frontier.withpersona.app`. `appName` and
  `releaseName` get the same suffix. The Namespace is labelled
  `frontier.withpersona.com/preview: "true"` and listed in the `dev` catalog. The
  Knative Service's `link.argocd.argoproj.io/external-link` annotation holds that
  URL, which Argo CD shows on the Application and in the pull request comment.
- It uses the dev app's Secrets, Mongo database and buckets, which `previewAccess`
  below gives it. `preview` itself renders none of that.
- Nothing that would duplicate or fight the dev app renders: `sealedSecrets`,
  `onePasswordItems`, `mongoDatabase`, `mysqlDatabase`, `mysqlMigration`,
  `domainMappings` and `gcsStorageBuckets` are absent, so no bucket or bucket policy
  of its own renders. MySQL stays disabled. A preview cannot assume the dev
  database's workload identity, so it gets no Cloud SQL resources, migration, proxy,
  or `MYSQL_*` settings. The `app` ServiceAccount gets no `gcpServiceAccount`
  annotation.
- Valkey and the job queue are the preview's own, so dev workers never run a
  preview's jobs. Workers run, and scheduled jobs are suspended so they don't run
  twice against dev's data.
- `env` values that contain `app-<dev namespace>.` point at the preview's hostname
  instead, and `FRONTIER_PREVIEW=true` and `FRONTIER_PREVIEW_PR=<prNumber>` are set.

`frontier.previewAccess(config, prNumber)` takes the same development config and
returns what gives the preview dev's data:

- `gcsStorageBuckets`: an `IAMPolicyMember` per bucket, in the preview's namespace,
  that grants the preview's `app` ServiceAccount the dev app's role on the dev bucket.
  The role must be object viewer, creator or user. The reference names the
  StorageBucket in the dev namespace, so it only resolves to the app's own dev buckets.
- `devSecrets`, when the app reads any Secret: an External Secrets `ExternalSecret` per
  Secret the app reads, including its sealed and 1Password items and
  `mongo-credentials`, which copies the dev namespace's Secret into the preview under
  the same name. They read through the `SecretStore` `dev-secrets`, which authenticates
  as the ServiceAccount `dev-secret-reader`. A Role and RoleBinding in the dev
  namespace, `<preview namespace>-secret-reader`, let that ServiceAccount get exactly
  those Secrets and no others.

persona-kubernetes deploys `previewAccess` in its own Application, rendered from the
app's default branch rather than the pull request. A pull request is unreviewed,
Config Connector applies an `IAMPolicyMember` with project-wide rights, and a
SecretStore can read whatever its ServiceAccount can. The preview's own AppProject
allows none of these kinds, so `preview` can't render them.

## MySQL

MySQL is off by default. Each long-lived environment opts in separately:

```jsonnet
mysql: {
  enabled: true,
  projectId: 'persona-frontier-staging',
  instance: { profile: 'environment-default' },
}
```

Each opted-in environment gets a separate Config Connector-managed instance.
`environment-default` selects a zonal instance for development and a regional
HA instance for production. The concrete `zonal` and `regional-ha` profiles can
also be selected explicitly, so a production environment can opt into a zonal
non-HA instance when appropriate. These profiles use Cloud SQL Enterprise;
“regional HA” describes availability and does not mean Enterprise Plus. Project,
network, deletion protection, backups and machine policy remain under platform
control.

The profile is chosen when the instance is first created. Changing it means
creating a new instance and migrating the data.

The library creates the Cloud SQL instance, database, IAM user and Workload
Identity binding in the app namespace. Only the `cloud-sql-proxy` ServiceAccount
is annotated with that Google service account; app pods connect to its Service
on port 3306. Dev's zonal profile is `db-custom-1-3840`. Production's regional
HA profile stays `db-custom-2-7680`. Disk autoresize stops at 200 GB. The proxy
waits 30 seconds after SIGTERM before closing. A preview gets none of these
resources.

## Configuration

Every option, its default and what it does is documented in
[`config.libsonnet`](config.libsonnet). Config is deep-merged over those defaults the
way Helm merges values: objects merge key by key, lists and scalars replace. Bad
combinations fail the render with the same messages the chart's `fail` calls give.

### Access

`visibility` says where the app's hostname resolves (`private`, the default, for the
VPN; `public`; or `none`, for no hostname, reachable only from other apps at
`http://app.<namespace>.svc.cluster.local`). `routes` says who may use which paths:
checked top to bottom, the first route whose paths match wins, and a path no route
matches is refused. Each route sets `paths`, `humans` (`none`, `anyone` or `okta`,
optionally narrowed by `groups` and `emails`), and the apps that may call it, as
`frontierApps` namespaces or `principals` (`forge/<forge-app>` or a `spiffe://` identity). On a `humans: okta`
route, those callers skip the Okta login and everyone else still gets it. A Forge app reaches only the
routes that name it, and `humans` rules never admit one. See
[`config.libsonnet`](config.libsonnet) and the chart's README for the details.

The `auth` keys are deprecated: when `routes` is empty they are read as the equivalent
routes, and setting both fails the render. `scaling.minScale` is raised to at least 1,
since a request through Knative's activator hides who is calling.

### Forge apps acting for a person

`delegatedCallers` (default `[]`, off) lists Forge apps, as `forge/<forge-app>`, that may
act for a person on the app's `humans: okta` and `humans: anyone` routes, never on
`humans: none`. It is separate from `principals`: it admits no service calls, and
`principals` admits no people. The twin of the chart's `delegatedCallers`
([persona-frontier-base#90](https://github.com/persona-id/persona-frontier-base/pull/90),
`docs/delegated-callers.md`), with the same claims, headers and sanitizer.

The app's identity-service pass carries the person:

| Claim | Contract (enforced by the identity service) |
|-------|---------------------------------------------|
| `sub` | The Forge app, as for every pass |
| `forge_delegated` | The string `"true"` |
| `forge_user_email` | The person's email |
| `forge_user_groups` | Their groups, a list of exact names |
| `forge_user_groups_csv` | The same groups, comma-joined |

Each delegated rule requires the internal gateway, a pass from a listed app, the
marker and an email. On an Okta route the email must also end in `@withpersona.com`,
and with an allowlist match the route's `emails` or a `forge_user_groups` entry in its
`groups`, either one, as for Okta users. A missing claim refuses the request. Callers
must use the in-cluster name through the Forge listener; the hostnames still go
through Okta.

The app receives `x-forge-caller` (`sub`), `x-forge-user-email` (`forge_user_email`)
and `x-forge-user-groups` (`forge_user_groups_csv`). The Forge VirtualService removes
those three and the six `x-auth-request-*` identity headers a caller sends, and an
EnvoyFilter, `app-forge-header-sanitizer`, clears the three Forge headers first on
every inbound request to the app's sidecar (and the `x-auth-request-*` headers when a
pass is present), so a caller cannot set them. Browser requests keep oauth2-proxy's
headers.

The trust boundary is the identity service (`forgeIdentity.issuer`): it validates
the claims' syntax, types and bounds before signing. An Istio AuthorizationPolicy
can only match claim values and cannot validate their shape.

Listing `forge/persona-cf-app-oracle` labels the Knative Service (not its revisions)
`frontier.withpersona.com/oracle-access: "true"`. The label is for discovery only and
grants nothing.

### Health checks and disruptions

The app container has no probes unless you set them. `readinessProbe`, `livenessProbe`
and `startupProbe` take a Kubernetes probe as-is; leave `port` out, because Knative
only probes the serving port and the library refuses any other. Knative fills in the
missing port for `readinessProbe` and `livenessProbe`; for `startupProbe` it does not,
so the library sets it to `service.port`.

The pod's shutdown grace period is `timeoutSeconds`: Knative copies it to
`terminationGracePeriodSeconds` and does not let the library set that field.

`podDisruptionBudget.enabled: true` lets node drains evict one app pod at a time. It
renders only when `scaling.minScale` is 2 or more.

The deployer must be allowed to manage `poddisruptionbudgets` in the `policy` API
group. The Frontier `gha-deploy` ClusterRole in persona-kubernetes
(`lib/frontier/rbac.libsonnet`) does not grant that yet, so an app deployed by GitHub
Actions fails with `Forbidden` if it enables the budget before that role is extended.

```jsonnet
{
  scaling: { minScale: 2 },
  readinessProbe: { httpGet: { path: '/readyz' } },
  livenessProbe: { httpGet: { path: '/healthz' } },
  podDisruptionBudget: { enabled: true },
}
```

### Namespace and permissions

The library renders the app's Namespace and the RoleBindings that let people manage
it, which the `frontier-app-bootstrap` chart's `Frontier` resource used to have kro
create. The Namespace carries the same labels kro gave it: `app` (`appName`), `name`,
`environment` (`clusterEnvironment`), `homestead.withpersona.com/catalog`
(`homestead.catalog`) and `istio.io/rev: stable`, without which the app's pods get no
Istio sidecar.

`permissions.owner` is required, and it and each of
`permissions.additionalCollaborators` get the `edit` ClusterRole plus
`frontier-namespace-owner` from persona-kubernetes, which covers what `edit` leaves out.
They are usernames without `@withpersona.com`, as in the bootstrap chart's values.

An app moving off the bootstrap chart has its namespace owned by the `Frontier`
resource in `frontier-system`. Deleting that resource has kro delete the namespace and
everything in it, so take over the namespace before removing it.

### Deploy source

`source.repository`, `source.revision` and `source.dirty`, usually set by CI, record
where a deploy came from. They render as `org.opencontainers.image.source`,
`org.opencontainers.image.revision` and `frontier.withpersona.com/source-dirty`
annotations on the Knative Service, workers and scheduled jobs and on their pod
templates, winning a clash with a workload's own annotations. Every container also
gets `DD_GIT_COMMIT_SHA` and `DD_GIT_REPOSITORY_URL`, which explicit `env` entries
override. Unset fields render nothing. Changing them rolls out a new revision even
when the image is unchanged.

### Options that stand in for Helm

Options that stand in for things Helm provided:

| Option | Replaces | Notes |
|--------|----------|-------|
| `namespace` | `.Release.Namespace` | Required. A `-prod` suffix sets `environment: production`. |
| `releaseName` | `.Release.Name` | The `app.kubernetes.io/instance` label. Defaults to `appName`. |
| `managedBy` | `.Release.Service` | The `app.kubernetes.io/managed-by` label. Defaults to `tanka`. |

## Differences from the Helm chart

- **Valkey is built here rather than taken from the upstream valkey chart.** It is the
  same shape as the job queue: the config file is mounted directly instead of being
  assembled by an init container, and its options are the ones the chart's
  `values.yaml` documents (`dataStorage`, `deploymentStrategy`, `resources`,
  `valkeyConfig`) plus `image`. The object names, labels and selectors the rest of the
  library relies on (`valkey`, `valkey-config`, `app.kubernetes.io/name: valkey`) are
  unchanged. There is no `replica` option.
- **Labels.** `helm.sh/chart` is gone and `app.kubernetes.io/managed-by` comes from
  `managedBy`.
- **Explicit zeroes are kept.** Helm's `default` treats `0`, `false` and `""` as unset;
  here only a missing, `null` or `""` value falls back, so `backoffLimit: 0` means no
  retries. A worker's `computeClass: ''` opts it out of the app's compute class
  rather than inheriting it.
- **Config checksums** on the Valkey pods hash the whole config file, so any config
  change restarts the pod.
- **No `helm.sh/resource-policy: keep` on the job queue's claim.** Argo CD ignores it.
  The claim's name still follows the chart: `job-queue-hyperdisk` when
  `jobQueue.computeClass` is set, `job-queue` otherwise, so a queue moved from the
  chart keeps its disk.
- **The bootstrap chart is folded in.** The Namespace and RoleBindings it had kro create
  are rendered here, from the same `permissions` and `homestead` values. The cluster's
  environment, which kro took from its own config, is `clusterEnvironment`.
- **The Forge VirtualService removes identity headers only with `delegatedCallers`.**
  The chart removes them on every app with a Forge route; here an app without the
  opt-in renders exactly as before.
- The chart's `NOTES.txt`, including its warning when the deprecated `auth` keys are
  set, has no equivalent.

## Development

`lib/` has one file per Kubernetes kind, named after it in lowercase
(`serviceaccount.libsonnet`, `deployment.libsonnet`, …; the Knative Service is
`knativeservice.libsonnet`). Each exports constructors for the objects of that kind,
such as `deployment.worker(cfg, worker)` and `deployment.valkey(cfg, instance)`, and
[`main.libsonnet`](main.libsonnet) assembles them into what `new` returns. Pieces
shared across kinds live in `lib/helpers.libsonnet`, and every render-time check is
in `lib/validation.libsonnet`.

```sh
make install   # jb install, from the repo root
make test      # render tests/cases and compare with the golden .json files
make fmt
```

`tests/cases/*.jsonnet` render to the `.json` next to them; rerun with
`UPDATE=1 tests/run.sh` after an intended change and review the diff.
`tests/errors/*.jsonnet` must fail with the message on their `// expect:` line.

To add a dependency, run `jb install <package>` in this directory and commit
`jsonnetfile.json` and `jsonnetfile.lock.json`. Upstream library versions are pinned
in [`lib/libs.libsonnet`](lib/libs.libsonnet).
