// App config shared by every environment, passed to the frontier-app-base jsonnet
// library. Each environment's main.jsonnet deep-merges its own config over this:
// objects merge key by key, lists and scalars replace.
// All available options and their defaults:
// https://github.com/persona-id/jsonnet-libs/blob/main/frontier-app-base/config.libsonnet
local app = import 'app.libsonnet';

{
  // Plain environment variables for the app container, as { name, value }.
  // A list, so an environment's config that sets `env` replaces this one rather
  // than adding to it: production/config.libsonnet and
  // development/config.libsonnet extend it with `common.env + [...]`. Add
  // variables every environment needs here.
  //
  // Datadog APM: dd-trace (started by the Dockerfile's CMD) reports to the
  // cluster's agent under DD_SERVICE, the app's name. DD_ENV is set per
  // environment. frontier-app-base adds DD_GIT_COMMIT_SHA and
  // DD_GIT_REPOSITORY_URL itself.
  //
  // FRONTIER_APP_NAME and FRONTIER_VISIBILITY tell the landing page its repo and
  // whether to show Build in Oracle. FRONTIER_VISIBILITY follows `visibility`
  // below; an environment that overrides `visibility` must override it too.
  env: [
    { name: 'DD_AGENT_HOST', value: 'datadog-agent.datadog.svc.cluster.local' },
    { name: 'DD_SERVICE', value: app.name },
    { name: 'FRONTIER_APP_NAME', value: app.name },
    { name: 'FRONTIER_VISIBILITY', value: $.visibility },
  ],

  // Custom domains the application will also be accessible on.
  // This is a list of fully qualified domain names (FQDNs) that
  // the application will be accessible on in addition to the
  // auto-generated domain name. This will make the application
  // publicly accessible even if public access is not enabled.
  // Currently, we only support records in `*.withpersona.app`.
  // This uses the knative custom domains feature.
  // https://knative.dev/docs/serving/services/custom-domains
  //
  // Note: The application needs to be granted access to use the
  // custom domain name in the persona-kubernetes repo. As an
  // example see https://github.com/persona-id/persona-kubernetes/pull/17289/changes#diff-b323be6a55593c703ffbbbd6088b34681812dc7f5e7dff0e1fe91bd078478e47R40.
  // The fqdn needs to be listed in `environments/knative-serving/main.jsonnet`.
  customDomains: [
    // { fqdn: 'foo.withpersona.app' },
  ],

  // Google cloud storage bucket (object storage)
  // This is a list of gcs buckets to create for a frontier application and their
  // associated configurations. All buckets will have a fully managed policy and
  // must be configured with this library. Frontier application access will be granted
  // using workload identity federation. Buckets and the attached IAM policy are
  // managed using gcp config connector. The permissions assigned to the bucket
  // are authoritative. This will create an IAM policy attached to the bucket this
  // means all permissions must be assigned by the library. Any clickops changes to
  // permissions in the gcp console will be replaced by the permissions on the k8s
  // IAMPolicy resource. Permissions are also granted at the bucket level rather
  // than at a project level. This ensures access is scoped correctly.
  // https://docs.cloud.google.com/config-connector/docs/overview
  // https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/storage/storagebucket
  // gcsStorageBuckets: [
  //   {
  //     // name of the gcs bucket. This will be prefixed with "persona-frontier-"
  //     name: 'foo-bucket',
  //     // Inherit or enforce public access prevention. If set to "inherited", the
  //     // configuration is defined by the organization policy. If "enforced", public
  //     // access is prevented.
  //     preventPublicAccess: 'enforced',
  //     // Additional iam role permissions to assign to users, groups, and service
  //     // accounts. Members of the role use the gcp standard prefix for specifying
  //     // types of accounts. This is optional.
  //     // https://docs.cloud.google.com/iam/docs/roles-permissions/storage
  //     // https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/iam/iampolicy
  //     additionalPermissions: {
  //       'roles/storage.objectUser': [
  //         'user:foo@example.com',
  //         'group:bar@withpersona.com',
  //       ],
  //       'roles/storage.objectAdmin': [
  //         'user:example@withpersona.com',
  //       ],
  //     },
  //     // Role to assign to the frontier application service account. This is the iam permission
  //     // the application will have for the gcs bucket. This uses gcp gke workload
  //     // identity of the kubernetes service account to access the gcs bucket. No
  //     // static keys are necessary.
  //     // https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#kubernetes-resources-iam-policies
  //     appPermissions: 'roles/storage.objectUser',
  //     // Enable or disable bucket object versioning.
  //     versioningEnabled: true,
  //   },
  // ],

  // Per-app MongoDB on Frontier's shared Atlas cluster.
  // Injects MONGODB_URI (sensitive) + MONGODB_DB_NAME into app container.
  // mongo: {
  //   enabled: true,
  // },

  // Who may manage the app's namespaces: the owner and each collaborator get
  // RoleBindings to the `edit` and `frontier-namespace-owner` ClusterRoles.
  // Usernames without @withpersona.com.
  permissions: {
    owner: 'chaitanya.prasad',  // required: your-username (without @withpersona.com)
    // additionalCollaborators: [
    //   'username',
    // ],
  },

  // The Homestead catalog the app is listed in: prod, or dev for homestead-dev apps.
  homestead: {
    catalog: 'prod',
  },

  // 1Password secrets configuration
  // secrets: {
  //   sources: {
  //     onePassword: {
  //       // Items to sync from 1Password (uses default Frontier Secrets vault)
  //       items: [
  //         { name: 'my-secret' },
  //       ],
  //     },
  //   },
  //
  //   // Environment variables from secrets
  //   envVars: [
  //     { name: 'MY_SECRET_VALUE', secretKey: 'password', fromSecretName: 'my-secret' },
  //   ],
  //
  //   // Mount secrets as files
  //   mounts: [
  //     { path: '/secrets/my-secret', fromSecretName: 'my-secret' },
  //   ],
  // },

  // Sealed secrets (encrypted; safe to commit) are written by bin/create-secret
  // into each environment's secrets.libsonnet: development/secrets.libsonnet and
  // production/secrets.libsonnet.

  // Valkey key-value store. When enabled, provisions a dedicated in-cluster Valkey instance and injects
  // REDIS_URL=redis://valkey:6379 and VALKEY_URL=redis://valkey:6379 automatically.
  // Each deploy that changes Valkey recreates it, with ~20-30s of downtime.
  //
  // valkey: {
  //   enabled: true,
  //   // Optional Configuration:
  //   dataStorage: {
  //     requestedSize: '2Gi',  // default: 1Gi
  //   },
  //   resources: {
  //     requests: {
  //       cpu: '100m',  // default: 100m
  //       memory: '256Mi',  // default: 256Mi
  //     },
  //     limits: {
  //       memory: '512Mi',  // default: 350Mi
  //     },
  //   },
  //   // default: maxmemory 200mb
  //   valkeyConfig: |||
  //     maxmemory 400mb
  //     maxmemory-policy allkeys-lru
  //   |||,
  // },

  // Durable Valkey for background job queues — Sidekiq, asynq, Valkey Streams.
  // Separate from `valkey` above, which is a cache and drops keys when it fills; a
  // queue must never drop a job. Enable both if you want both.
  //
  // Injects JOB_QUEUE_URL=redis://job-queue:6379 into the app container, workers
  // and scheduled jobs. Naming your library as `client` also sets the variable
  // that library reads, so you never write the address yourself:
  //
  //   sidekiq   also sets REDIS_URL=redis://job-queue:6379
  //   bullmq    also sets REDIS_URL=redis://job-queue:6379
  //   asynq     also sets REDIS_ADDR=job-queue:6379   (host:port, not a URL)
  //
  // Leave `client` out for Valkey Streams, an unlisted library, or durable
  // non-queue use such as locks and idempotency keys.
  //
  // Keep job payloads small — send a reference to the work, not the work itself.
  //
  // jobQueue: {
  //   enabled: true,
  //   client: 'sidekiq',  // optional: sidekiq | bullmq | asynq
  //   // Optional configuration:
  //   diskSize: '16Gi',  // default: 8Gi
  //   maxMemory: '1gb',  // default: 512mb — keep well under the memory limit
  //   resources: {
  //     requests: {
  //       memory: '512Mi',  // default: 512Mi
  //     },
  //     limits: {
  //       memory: '2Gi',  // default: 1Gi
  //     },
  //   },
  // },

  // Background work: anything that isn't the web service answering a request.
  // Queue consumers, timer loops and scheduled work go here rather than in the web
  // service, which scales on inbound requests and cuts off long work at the request
  // timeout.
  //
  // Workers and scheduled jobs take your env, secrets and service account, and
  // default to your image; usually only the start command differs.
  //
  // backgroundJobs: {
  //   enabled: true,
  //
  //   // Processes kept running. Two shapes, same mechanism: consumers that wait
  //   // for work, and loops that wake themselves up.
  //   workers: [
  //     {
  //       name: 'sidekiq',
  //       command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml'],
  //       replicas: 2,
  //       // CPU and memory: small | medium | large, default small. The library's
  //       // config.libsonnet has the numbers.
  //       size: 'medium',
  //     },
  //     {
  //       name: 'sync',
  //       // Some apps pick their role from the environment, not the command.
  //       env: [
  //         { name: 'ROLE', value: 'worker' },
  //       ],
  //       // One copy only, including across a redeploy, for work that would double
  //       // up if two overlapped. Also means no copy runs during a node drain.
  //       singleInstance: true,
  //       // Seconds to finish the job in hand after being asked to stop.
  //       terminationGracePeriodSeconds: 60,
  //       // A tier with one value nudged — keeps medium's CPU and memory requests.
  //       size: 'medium',
  //       resources: {
  //         limits: { memory: '3Gi' },
  //       },
  //       // Added to the pod. The container is always named `worker`, so the
  //       // Datadog log annotation key is predictable.
  //       labels: {
  //         'tags.datadoghq.com/service': 'my-app-sync',
  //       },
  //       annotations: {
  //         'ad.datadoghq.com/worker.logs': '[{"source":"ruby"}]',
  //       },
  //       // Optional, off by default: a worker serves no traffic, so any health
  //       // signal has to come from the worker itself.
  //       livenessProbe: {
  //         exec: {
  //           command: ['test', '-f', '/tmp/sidekiq-ready'],
  //         },
  //       },
  //     },
  //   ],
  //
  //   // Work that runs on a schedule and exits. Cheaper than a sleeping loop, and
  //   // Kubernetes handles retries, history and missed runs.
  //   //
  //   // Takes the same size, resources, labels, annotations and image as a worker.
  //   scheduled: [
  //     {
  //       name: 'nightly-report',
  //       schedule: '0 2 * * *',
  //       command: ['bin/report'],
  //       timeZone: 'America/Los_Angeles',  // optional; the schedule is UTC without it
  //       // Defaults: skip a run if the previous one is still going, retry 3 times,
  //       // keep the last 3 successes and 1 failure.
  //       activeDeadlineSeconds: 3600,  // optional hard timeout for one run
  //       suspend: false,  // pause it without deleting it
  //       // Delete finished Jobs at this age. The history limits cap how MANY are
  //       // kept; this caps how OLD they get.
  //       ttlSecondsAfterFinished: 604800,
  //     },
  //
  //     // Any workload — worker or scheduled job — can run an image other than
  //     // your app's, and still gets the app's env, secrets and service account.
  //     // Best for upstream images, which are already built; a second image from
  //     // your repo needs its own build.
  //     {
  //       name: 'db-backup',
  //       schedule: '0 2 * * *',
  //       image: 'postgres:17-alpine',
  //       command: ['/bin/sh', '-c'],
  //       args: ['pg_dump "$DATABASE_URL" | gzip > /tmp/db.sql.gz'],
  //     },
  //   ],
  // },

  // private = VPN only; public = open internet; none = no hostname, only other apps can
  // reach it at http://app.<namespace>.svc.cluster.local
  visibility: 'private',

  // Who may use which paths. Routes are checked top to bottom and the first match decides;
  // a path no route matches is refused. /metrics and /healthz are always open.
  //
  // Each route sets `humans`: none, anyone (no login) or okta (Persona login first), plus
  // any other callers allowed on those paths:
  //   frontierApps: namespaces of other Frontier apps, e.g. ['frontier-other-app-prod']
  //   principals:   'forge/<forge-app>' (one named Forge app, e.g. 'forge/persona-cf-app-oracle';
  //                 most Forge apps are '<repo>-prod' in production) or full spiffe:// identities
  //                 of other mesh callers
  //
  // Other apps must call the cluster-local address, http://app.<namespace>.svc.cluster.local.
  // Through the hostname they look like a person and get whatever `humans` allows.
  //
  // A Forge app reaches only the routes that name it, and `humans` rules never admit one.
  //
  // Behind okta, the app can read the caller from x-auth-request-user,
  // x-auth-request-email and x-auth-request-groups.
  routes: [
    { paths: ['/*'], humans: 'anyone' },
  ],

  // Example: a webhook anyone can hit, an internal API one app calls, and Okta everywhere
  // else for one team. Paths are exact (/webhooks/stripe), prefix (/api/*) or suffix (*.png);
  // `/api/*` does not match `/api`.
  //
  // routes: [
  //   { paths: ['/webhooks/stripe'], humans: 'anyone' },
  //   { paths: ['/api/internal/*'], humans: 'none', frontierApps: ['frontier-other-app-prod'] },
  //   { paths: ['/mcp/*'], humans: 'none', principals: ['forge/persona-cf-app-oracle'] },
  //   {
  //     paths: ['/*'],
  //     humans: 'okta',
  //     groups: ['Role-Engineering'],  // optional; Okta only sends Role-* groups
  //     emails: ['teammate@withpersona.com'],  // optional; matching either gets in
  //   },
  // ],
}
