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
  version: 'MYSQL_8_0',               // or MYSQL_8_4; upgrades in place, never back
  instance: {
    // Leave tier out to start dev on db-g1-small and prod on db-custom-1-3840.
    tier: 'db-custom-2-7680',         // db-g1-small, db-custom-1-3840, db-custom-2-7680, db-custom-4-15360
    availabilityType: 'REGIONAL',     // REGIONAL needs a db-custom tier
    diskSize: 10,                     // whole GB, 10 to 100, and only upwards
    diskAutoresizeLimit: 100,
  },
  collation: 'utf8mb4_0900_ai_ci',    // or utf8mb4_unicode_ci
  databases: [
    { name: 'reporting', collation: 'utf8mb4_unicode_ci' },
  ],
  users: [
    // SELECT on every database unless privileges or databases say otherwise.
    { name: 'billing-reader', type: 'CLOUD_IAM_USER', email: 'reader@withpersona.com' },
    { name: 'etl', type: 'CLOUD_IAM_SERVICE_ACCOUNT', email: 'etl@persona-frontier.iam.gserviceaccount.com',
      privileges: ['SELECT', 'INSERT', 'UPDATE'], databases: ['reporting'] },
  ],
}
```

### Project, region and network

The instance runs in the GCP project of the Frontier cluster that renders the
app, in `us-central1`, on that project's default VPC. There is nothing to set:
the cluster's Argo CD passes its project as the `gcpProject` top-level argument
(see frontier-argocd-application's `newFrontierApp`), and the template's
`main.jsonnet` copies it into the config. The same app config renders
`persona-frontier` on frontier-us-central1 and `persona-frontier-staging` on
frontier-staging-us-central1, for the project annotation, the Workload Identity
pool, the private network and the connection name alike.

An app can't choose the project. Without a `gcpProject` (an older
`main.jsonnet`, or a local render) the project is `persona-frontier`. An older
config that still sets `mysql.projectId` keeps rendering when it matches the
cluster's project, and fails with a message to remove it otherwise. A
`mysql.region` or `mysql.privateNetwork` that disagrees with the cluster fails
the render too, because the cluster's admission policy would reject it anyway.

### Instance

Each opted-in environment gets its own Config Connector-managed instance. An
empty `instance.tier` starts dev on zonal `db-g1-small` and prod on zonal
`db-custom-1-3840`; any tier can be set explicitly in either. Both start with
10 GB and can grow to at most 100 GB. `db-g1-small` is a shared-core machine and
cannot be highly available. A `db-custom-*` tier can be `ZONAL` or `REGIONAL`.
Changing the tier or the availability type restarts the instance in place. Disk
can grow and cannot shrink.

`instance.deletionPolicy` defaults to `abandon`: deleting the app's
Kubernetes objects leaves the Cloud SQL instance, database, app user and IAM
objects in GCP untouched. Setting it to `delete` actually deletes them, in
both dev and prod, with no final backup.

The library creates the Cloud SQL instance, the database named after the
app, any extra `databases`, the app IAM user, any extra `users`, and the
Workload Identity binding in the app namespace. Only the `cloud-sql-proxy`
ServiceAccount is annotated with the app's Google service account; app pods
connect to its Service, `MYSQL_HOST:MYSQL_PORT` (`cloud-sql-proxy:3306`), as
`MYSQL_USER` with no password. When asked to stop, the proxy keeps serving open connections for up to
`proxy.shutdownDelaySeconds` (290) and exits as soon as they close. Each proxy
has a disruption budget of one, and its two replicas prefer different nodes. A preview gets none of these resources.

### Extra users

Extra `users` are IAM users, service accounts or groups. A password user is not
accepted, because Cloud SQL makes those superusers. Each gets `privileges`
(default `['SELECT']`; `['ALL PRIVILEGES']` or a list of table-level privileges)
on `databases` (default: every database on the instance). Every sync resets a
listed user to exactly those grants, so narrowing them takes effect, and
removing an entry deletes that MySQL user whatever `deletionPolicy` says.

Logging in also takes `roles/cloudsql.instanceUser` and `roles/cloudsql.client`
in the Frontier project. Both Frontier projects grant them to their own service
accounts in persona-infrastructure, so a service account entry works as is. A
person or group needs them granted too; until that grant lands in
persona-infrastructure, their entry creates the MySQL user but they can't log
in. The roles only cover connecting and IAM login, so an entry here is what
actually gives someone data access, on this instance and these databases only.

The instance has no public IP. A person connects with the Cloud SQL Auth Proxy
from somewhere that routes to the Frontier VPC:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn "$(kubectl -n <namespace> get configmap mysql-connection -o jsonpath='{.data.instanceConnectionName}')"
mysql --host=127.0.0.1 --user=<email before the @> <database>
```

A service account whose workload already runs on the Frontier VPC needs nothing
more.

### More identities for the app

`connections` gives the app more MySQL identities besides its default one, for
example a read-only identity standing in for a replica (Frontier instances have
none):

```jsonnet
mysql+: {
  connections: [{ name: 'ro' }],   // privileges and databases default as for users: SELECT on every database
}
```

Each entry gets its own Google service account, `app-<namespace without
frontier->-<name>`, its own IAM database user and its own `cloud-sql-proxy-<name>`
Deployment and Service, because the proxy logs in as the pod's identity. Every
app pod gets `MYSQL_<NAME>_HOST`, `MYSQL_<NAME>_PORT` and `MYSQL_<NAME>_USER`
next to the default `MYSQL_*`. Like `users`, each sync resets its grants to
exactly `privileges` on `databases`. A name is lowercase letters and digits, not
`dev` or `prod`, and short enough for the account id to fit 30 characters; the
admission policy checks the same shape, so a connection can't claim another
namespace's account.

### Database flags

`instance.databaseFlags` adds MySQL flags to `cloudsql_iam_authentication`,
which is always on. `performance_schema` defaults to `off` (for the shared-core
tier) unless set here. The accepted names are the ones stack-core's Cloud SQL
databases use: `binlog_row_image`, `innodb_autoinc_lock_mode`,
`innodb_cloudsql_managed_buffer_pool`,
`innodb_cloudsql_managed_buffer_pool_threshold_pct`,
`log_bin_trust_function_creators`, `log_output`, `long_query_time`,
`performance_schema`, `performance_schema_max_thread_instances`,
`slow_query_log` and `table_open_cache_instances`.

```jsonnet
instance+: {
  databaseFlags: [
    { name: 'innodb_cloudsql_managed_buffer_pool', value: 'on' },
    { name: 'innodb_cloudsql_managed_buffer_pool_threshold_pct', value: '90' },
  ],
}
```

### Database name

The app's own database is named after `appName` unless `databaseName` says
otherwise, e.g. a Rails app's existing `persona-billing_production`. MySQL names
may use underscores; the `SQLDatabase` object is named with dashes and keeps
the real name in `resourceID`, so two names that differ only in `_` and `-` are
rejected. `MYSQL_DATABASE` and the grants use the real name.

### Sync order

`mysql.enabled` also labels the app namespace
`frontier.withpersona.com/mysql-database: "true"`. The cluster's Frontier
MySQL admission policy reads that label to scope its Cloud SQL / Workload
Identity shape checks to opted-in namespaces only. The Namespace syncs in wave
-1, ahead of the Config Connector objects in wave 0, so the label is in place
before they are admitted; `newFrontierApp`'s sync retry covers a cache that is
still behind.

### Names

The app's Google service account is `app-<namespace without frontier->`, which
has to fit Cloud IAM's 30 characters, so a MySQL namespace can be at most 35
characters: an app name of at most 21. The admission policy derives the same
name to check that one namespace can't take over another's service account, and
can't verify a hashed or truncated name, so a longer app has to be renamed
before it can enable MySQL.

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
`frontierApps` namespaces or `principals` (`forge-internal/<forge-app>`, `forge-external/<forge-app>` or a `spiffe://` identity). On a `humans: okta`
route, those callers skip the Okta login and everyone else still gets it. A Forge app reaches only the
routes that name it, and `humans` rules never admit one. See
[`config.libsonnet`](config.libsonnet) and the chart's README for the details.

### Forge principals and issuers

A Forge principal is `<prefix>/<forge-app>`, and each prefix names the identity service
that signs its passes (`forgeIdentity.issuers`). `forge-internal/` is the Internal Apps
Cloudflare account; `forge-external/` is the External Apps account, signed by
persona-frontier-gateway's deployment there. `forge/` is a deprecated alias for
`forge-internal/` (`forgeIdentity.aliases`), kept so existing routes keep rendering
until they move; listing both forms of one app admits it once.

`<forge-app>` is the app, its repo, which Forge's deploy stamps on the Worker's binding
along with the environment it deployed to (`staging`, `preview` or `production`).
persona-frontier-gateway signs them into the pass as `sub` (the app, the same in every
environment) and `forge_environment`. `<prefix>/<forge-app>` admits the app's
production Worker; `<prefix>/<forge-app>@<environment>` admits another, e.g.
`forge-external/persona-dashboard-onboard@staging`. A route admits a principal only with a
pass from that prefix's issuer whose `sub` is the app and whose `forge_environment` is the
environment, so a Worker in one account can never pass as one with the same name in the
other, and a staging or preview Worker never passes as production. A pass without
`forge_environment`, from a binding deployed before the stamp or from the retired
forge-identity signer, matches no Forge rule.

The app receives the pass's `sub` in `x-forge-caller` (and `forge_app` in `x-forge-app`),
its environment in `x-forge-environment` and its `iss` in `x-forge-issuer`. A route that
admits both prefixes must check the issuer, since the same name can exist in each account,
and one that admits several environments must check the environment. The Forge
VirtualService removes every identity header a caller sends (the `x-forge-*` headers and
the `x-auth-request-*` ones oauth2-proxy sets for people), as the chart does, so a Forge
caller can't pass itself off as a signed-in person. Trust these headers only on a route
that admits nothing but Forge principals. A
principal with an unknown prefix fails the render.

The `auth` keys are deprecated: when `routes` is empty they are read as the equivalent
routes, and setting both fails the render. `scaling.minScale` is raised to at least 1,
since a request through Knative's activator hides who is calling.

### Forge apps acting for a person

`delegatedCallers` (default `[]`, off) lists Forge apps, as `forge-internal/<forge-app>`
(Internal Apps only; `forge-external/` is refused, and the deprecated `forge/` still
works), that may
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

The app receives `x-forge-caller` (`sub`), `x-forge-issuer` (`iss`), `x-forge-user-email`
(`forge_user_email`) and `x-forge-user-groups` (`forge_user_groups_csv`), beside
`x-forge-app` and `x-forge-environment`. The Forge VirtualService removes those six and
the six `x-auth-request-*` identity headers a caller sends, and an EnvoyFilter, `app-forge-header-sanitizer`, clears the four Forge
headers first on
every inbound request to the app's sidecar (and the `x-auth-request-*` headers when a
pass is present), so a caller cannot set them. Browser requests keep oauth2-proxy's
headers.

The trust boundary is the identity service (`forgeIdentity.issuers.forge`): it validates
the claims' syntax, types and bounds before signing. An Istio AuthorizationPolicy
can only match claim values and cannot validate their shape.

Listing `forge-internal/persona-cf-app-oracle` (or `forge/persona-cf-app-oracle`) labels the Knative Service (not its revisions)
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
