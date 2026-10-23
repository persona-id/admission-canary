// Defaults for every option `new()` takes. Mirrors the Helm chart's values.yaml:
// the same keys, the same defaults, deep-merged the same way (`std.mergePatch`),
// so an app's values.yaml converts to a config object key for key.
{
  // The app's name, e.g. my-app-prod. Required. The Namespace's `app` label.
  appName: '',

  // Namespace the app is deployed into, e.g. frontier-my-app-prod. Required.
  // Stands in for Helm's `.Release.Namespace`: a `-prod` suffix marks the app as
  // production, and it scopes the `app` ServiceAccount's identity. The library
  // renders the Namespace itself, labelled the way the Frontier kro resource did.
  namespace: '',

  // Who may manage the app's namespace. Replaces the bootstrap chart's Frontier
  // resource, which kro turned into the same RoleBindings. Usernames are Okta
  // usernames without @withpersona.com.
  permissions: {
    // Required. Gets the `edit` ClusterRole and `frontier-namespace-owner`, which
    // covers the kinds `edit` leaves out (Mongo databases, 1Password items, Istio
    // policies, buckets and their IAM policies, Roles and RoleBindings).
    owner: '',

    // Get the same access as the owner.
    additionalCollaborators: [],
  },

  // The Homestead catalog the app is listed in: prod, or dev for homestead-dev
  // apps. The Namespace's `homestead.withpersona.com/catalog` label.
  homestead: {
    catalog: 'prod',
  },

  // The Namespace's `environment` label: the environment of the cluster, not of
  // the app, so the same value for its -dev and -prod namespaces. Frontier runs in
  // one development cluster.
  clusterEnvironment: 'development',

  // Stands in for Helm's `.Release.Name` in the `app.kubernetes.io/instance` label.
  // Defaults to `appName`.
  releaseName: '',

  // The `app.kubernetes.io/managed-by` label on every object.
  managedBy: 'tanka',

  // Who may reach which paths. Routes are checked top to bottom, and the first
  // route whose paths match decides who gets in. Paths no route matches are
  // refused. `/metrics` and `/healthz` are always open to anyone who can reach
  // the app.
  //
  // Each route:
  //   paths:  exact (`/webhooks/stripe`), prefix (`/public/*`) or suffix (`*.png`)
  //           matches, or URI templates (`{*}` one segment, `{**}` many). No
  //           regexes. Case-sensitive, and `/api` does not cover `/api/`.
  //   humans: `none`, `anyone` (no login) or `okta` (Okta login first).
  //           With `okta`, `groups` and `emails` narrow it to those users; a user
  //           matching either gets in. Only `Role-*` groups are in the token.
  //           Okta users arrive with `x-auth-request-user`, `x-auth-request-email`
  //           and `x-auth-request-groups` headers.
  //   frontierApps: namespaces of Frontier apps that may call these paths, e.g.
  //           `frontier-some-app-prod`.
  //   principals: other callers. `forge/<forge-app>` is one named Forge
  //           (Cloudflare Worker) app, proven by its signed pass. Forge's deploy
  //           sets the name: `<repo>` in staging, `<repo>-prod` in production;
  //           Oracle has one environment and is `forge/persona-cf-app-oracle`.
  //           Anything else is a full `spiffe://` identity, e.g. a workload in
  //           another cluster.
  //   Callers must use http://app.<this-namespace>.svc.cluster.local; a call
  //   through the hostname arrives as a person. With `humans: okta`, the callers
  //   listed here skip the Okta login; everyone else still gets it. A Forge app
  //   reaches only the routes that name it; `humans` rules never admit one.
  //
  //   [
  //     { paths: ['/api/internal/*'], humans: 'none', frontierApps: ['frontier-some-app-prod'], principals: ['forge/persona-cf-app-oracle'] },
  //     { paths: ['/*'], humans: 'okta', groups: ['Role-Engineering'] },
  //   ]
  //
  // Replaces the deprecated `auth` keys below.
  routes: [],

  // How `forge/<forge-app>` callers are verified: the Worker that signs their
  // tokens, and the gateway listener their requests arrive through. Cluster-wide
  // values; apps should not need to touch these.
  forgeIdentity: {
    issuer: 'https://persona-cf-app-forge-identity-prod.persona-app.workers.dev',
    // Inline, so istiod fetches nothing and the Worker needs no public endpoint.
    jwks: '{"keys":[{"alg":"ES256","crv":"P-256","kid":"persona-cf-app-forge-identity.UaiwbHC9ncPRNLvyu7xqkgaaShz-JFDynppBLQwWtUE","kty":"EC","use":"sig","x":"IXebg7TgZyIOYe-FXmcDbYSDmKMDijZVVPoitcWAp3U","y":"Lrhm0qqB0BJ2YYBg9zim1bjeG85Wy4y0lRymToMpPYo"}]}',
    gateway: 'istio-gateways/istio-forge-gateway',
    gatewayPrincipal: 'cluster.local/ns/istio-gateways/sa/istio-ingressgateway-internal',
  },

  // Okta endpoints used to verify the forwarded ID token when a route limits
  // Okta users. Cluster-wide values; apps should not need to touch these.
  oidc: {
    issuer: 'https://persona.okta.com',
    jwksUri: 'https://persona.okta.com/oauth2/v1/keys',
  },

  // DEPRECATED, do not use. Use `routes` instead. Still read when `routes` is
  // empty so existing apps keep working; will be removed. Setting both fails the
  // render.
  auth: {
    // Require SSO for requests to the app. Off by default so enabling auth is
    // always a deliberate, reviewable change.
    required: false,

    // Paths exempted from the auth check, anything listed here is reachable
    // by anyone who can reach the app, e.g. ['/webhooks/stripe', '/public/*'].
    // Same matching rules as `routes[].paths`.
    unauthedPaths: [],

    // The inverse of `unauthedPaths`, for an app that is mostly public: only the
    // paths listed here go through SSO and everything else is reachable by anyone
    // who can reach the app, e.g. ['/admin/*']. Same matching rules as above.
    //
    // Setting both lists fails the render, since they disagree about what an
    // unlisted path means. Setting neither gates every path.
    authedPaths: [],

    // Restrict access to specific identities. When both lists are empty, any
    // authenticated user in an allowed email domain gets in — that is the default.
    // A caller matching either list gets in. Needs `required: true`; setting these
    // without it fails the render rather than leaving the app open.
    allow: {
      // Exact addresses, matched against the `email` claim.
      emails: [],
      // Okta group names, matched against the `groups` claim. A user in any one
      // of them is allowed. Only `Role-*` groups are in the claim.
      groups: [],
    },
  },

  // Background work: processes that are not the web service, and work that runs on
  // a schedule. Anything that consumes a queue, loops on a timer, or runs to a
  // schedule belongs here rather than in the Knative service, which sizes itself
  // from inbound request concurrency.
  //
  // Workers and scheduled jobs take the app's environment, secrets and
  // ServiceAccount, and default to its image. Somewhere to keep the jobs themselves
  // is `jobQueue`.
  backgroundJobs: {
    enabled: false,

    // Size for any worker or scheduled job that names neither `size` nor `resources`.
    // No tier sets a CPU limit; the memory limit is the OOM guard.
    //
    //   small    cpu 100m, memory 256Mi, memory limit 512Mi
    //   medium   cpu 500m, memory 1Gi,   memory limit 2Gi
    //   large    cpu 1,    memory 4Gi,   memory limit 8Gi
    //
    // A workload can set `resources` outright, or set both and have `resources`
    // merge over the tier.
    defaultSize: 'small',

    // Processes kept running. Two shapes, one mechanism:
    //   - consumers that wait for work (Sidekiq, asynq, Valkey Streams)
    //   - loops that wake themselves up (a sleep loop, an in-process scheduler)
    //
    // Each entry takes:
    //   name                           required, unique across workers and scheduled
    //   command, args                  defaults to the image's entrypoint
    //   replicas                       default 1
    //   singleInstance                 one copy, never two, including across a redeploy
    //   terminationGracePeriodSeconds  seconds to finish the job in hand, default 30
    //   size, resources                see `defaultSize`
    //   env                            merged over the app's env
    //   labels, annotations            added to the pod; the library's labels win a clash
    //   computeClass                   overrides the top-level `computeClass`
    //   livenessProbe, readinessProbe  off by default
    //   image                          defaults to the app's image
    workers: [],

    // Work that runs on a schedule and exits. Cheaper than a sleeping loop, and
    // Kubernetes handles retries, history and missed runs.
    //
    // Takes the same `size`, `resources`, `env`, `labels`, `annotations`,
    // `computeClass` and `image` as a worker, plus:
    //   schedule                     required, cron syntax
    //   timeZone                     optional, schedule is UTC without it
    //   concurrencyPolicy            default Forbid
    //   suspend                      default false
    //   backoffLimit                 default 3
    //   successfulJobsHistoryLimit   default 3
    //   failedJobsHistoryLimit       default 1
    //   startingDeadlineSeconds, activeDeadlineSeconds, ttlSecondsAfterFinished
    scheduled: [],
  },

  // GKE compute class used to schedule the app's pods. Rendered as the
  // `cloud.google.com/compute-class` node selector on the Knative revision.
  // Set to '' to fall back to the cluster's default scheduling.
  //
  // Two classes are available:
  //   standard          — the default; suits most apps
  //   standard-highcpu  — use when the app's CPU:memory ratio is closer to 1:2
  //                       (i.e. roughly 2Gi of memory per vCPU requested)
  //
  // Nodes backing the class carry a matching `cloud.google.com/compute-class`
  // taint, so the library also emits the toleration for it — see `tolerations`.
  //
  // Note: Knative drops nodeSelector and tolerations from the revision unless the
  // cluster has `kubernetes.podspec-nodeselector: enabled` and
  // `kubernetes.podspec-tolerations: enabled` in the `config-features` ConfigMap.
  //
  // The Valkey instances deliberately get neither the nodeSelector nor the
  // toleration, because they own a disk — see lib/deployment.libsonnet. The job
  // queue takes its own, `jobQueue.computeClass`.
  computeClass: 'standard',

  // Additional pod tolerations. The toleration for the `computeClass` taint is
  // always rendered whenever `computeClass` is set; anything listed here is
  // appended to it.
  tolerations: [],

  // Custom domains the application will also be accessible on, as
  // [{ fqdn: 'foo.withpersona.app' }]. This makes the application publicly
  // accessible even if public access is not enabled. Currently only records in
  // `*.withpersona.app` are supported. Uses the Knative custom domains feature.
  // https://knative.dev/docs/serving/services/custom-domains
  //
  // Note: The application needs to be granted access to use the custom domain name
  // in the persona-kubernetes repo; the fqdn needs to be listed in
  // `environments/knative-serving/main.jsonnet`.
  customDomains: [],

  // Plain (non-secret) environment variables injected into the container, as
  // [{ name: 'LOG_LEVEL', value: 'debug' }]. Values are stringified.
  env: [],

  // Google Cloud Storage buckets to create for the app, managed with GCP Config
  // Connector. Each bucket gets an IAMPartialPolicy: the members listed here are kept
  // in their roles, and members granted anywhere else, such as a preview
  // environment's or the console's, are left alone rather than removed.
  // App access is granted to the `app` ServiceAccount via workload identity. `preview`
  // only grants appPermissions of roles/storage.objectViewer, objectCreator or objectUser.
  // https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/storage/storagebucket
  //
  // Each entry takes:
  //   name                   required; prefixed with "persona-frontier-"
  //   preventPublicAccess    "enforced" (default) or "inherited"
  //   additionalPermissions  { 'roles/storage.objectUser': ['user:foo@example.com'] }
  //   appPermissions         role for the app, default roles/storage.objectUser
  //   versioningEnabled      default true
  gcsStorageBuckets: [],

  // GKE Workload Identity binding for the app's ServiceAccount.
  // When enabled, the ServiceAccount is annotated with iam.gke.io/gcp-service-account
  // so pods can impersonate the named GCP service account.
  gcpServiceAccount: {
    enabled: false,
    // GCP service account email. Defaults to <appName>@persona-frontier.iam.gserviceaccount.com.
    email: '',
  },

  // Optional deploy source provenance, usually supplied by CI. Rendered as
  // annotations rather than labels, so full repository URLs and SHA-256 revisions
  // fit. Changing these creates a new Knative revision and rolls the workers,
  // even when the image is unchanged. DD_GIT_COMMIT_SHA and DD_GIT_REPOSITORY_URL
  // default to these values; explicit entries in `env` or a background workload's
  // `env` win.
  source: {
    // Canonical, credential-free URL, e.g. https://github.com/persona-id/my-app.
    repository: '',
    // Full git commit SHA; keep dirty state separate.
    revision: '',
    // Optional boolean (or 'true'/'false'); '' means unknown.
    dirty: '',
  },

  // Image configuration. Required.
  image: {
    repository: '',
    tag: '',
  },

  // A durable place to keep background jobs.
  //
  // Separate from `valkey` because a cache and a queue want opposite behaviour when
  // memory fills: a cache should drop the least recently used keys, a queue must
  // never drop a job. This instance keeps every job on disk as it arrives and
  // refuses new work rather than deleting old work. An app can enable both.
  //
  // Enabling it injects JOB_QUEUE_URL=redis://job-queue:6379 into the web
  // container, workers and scheduled jobs.
  //
  // `client` is optional. Name the job library you use and the library also sets
  // the variable that library reads, so your app never has to write our address:
  //
  //   sidekiq   also sets REDIS_URL=redis://job-queue:6379
  //   bullmq    also sets REDIS_URL=redis://job-queue:6379
  //   asynq     also sets REDIS_ADDR=job-queue:6379   (host:port, not a URL)
  //
  // Leave it empty and you get JOB_QUEUE_URL alone — right for Valkey Streams,
  // for a library not listed here, and for durable non-queue use such as
  // distributed locks or idempotency keys. Naming your own variable in `env`
  // still wins either way.
  //
  // There is deliberately no replica setting: read replicas with no failover are
  // useless for a queue where every operation is a write.
  jobQueue: {
    enabled: false,

    // Optional: sidekiq | bullmq | asynq
    client: '',

    diskSize: '8Gi',
    storageClass: '',

    // Optional: a compute class to run the queue on, such as `standard`. Separate
    // from the app's `computeClass`, which the queue never takes. The class's nodes
    // are reservation-backed but only attach Hyperdisk, so the disk becomes Hyperdisk
    // Balanced (`hyperdisk-balanced-rwo`, unless storageClass says otherwise) and its
    // claim is named `job-queue-hyperdisk` instead of `job-queue`: a claim's storage
    // class can't change. Empty keeps the queue on the untainted pool, which a GCE
    // stock-out can leave with no room.
    //
    // Setting or clearing it moves the queue to a new, empty disk and Argo CD prunes
    // the old claim, so let the queue drain first.
    computeClass: '',

    // Refuses writes past this, rather than evicting jobs.
    maxMemory: '512mb',

    resources: {
      requests: { cpu: '100m', memory: '512Mi' },
      // Headroom over maxMemory: rewriting the append log briefly costs extra.
      limits: { memory: '1Gi' },
    },

    // Optional: a PriorityClass for the queue's pod, such as `product-feature`. Above
    // the default 0, a Pending queue can preempt default-priority pods to fit, and
    // they can no longer preempt it. Higher classes (infrastructure-*) still can.
    // Empty keeps the cluster default.
    priorityClassName: '',

    image: {
      repository: 'docker.io/valkey/valkey',
      tag: '9.0.2',
    },
  },

  // Mongo database on the shared Frontier Atlas cluster. Opt in to provision a
  // database named after `appName` and inject MONGODB_URI and MONGODB_DB_NAME.
  mongo: {
    enabled: false,
  },

  // MySQL database on a dedicated Frontier Cloud SQL instance. Opt in separately
  // in dev and prod to provision one instance for that app environment. The proxy uses
  // Workload Identity and automatic IAM database authentication; no database
  // password is exposed to the app namespace.
  mysql: {
    enabled: false,
    // Project containing the Cloud SQL instance and generated app service account.
    // Required when enabled.
    projectId: '',
    region: 'us-central1',
    // Empty selects this project's default VPC. Set a full network resource name
    // when the instance should use another VPC.
    privateNetwork: '',
    instance: {
      // environment-default selects zonal for dev and regional HA for prod.
      // The concrete zonal and regional-ha profiles can also be selected explicitly.
      profile: 'environment-default',
    },

    // mysql client used to generate the provisioner password and grant the app user.
    client: {
      image: 'us-central1-docker.pkg.dev/persona-container-registry/mirror/alpine/mysql@sha256:08770743847a0fa8a79d79287ec07ba8cacb7ec2ea4fdaec7d97c8a51c57682b',
    },

    // Used only to create the bootstrap Secret through the Kubernetes API.
    secretGenerator: {
      image: 'us-central1-docker.pkg.dev/persona-container-registry/mirror/curlimages/curl@sha256:463eaf6072688fe96ac64fa623fe73e1dbe25d8ad6c34404a669ad3ce1f104b6',
    },

    proxy: {
      image: 'us-central1-docker.pkg.dev/persona-container-registry/mirror/cloud-sql-connectors/cloud-sql-proxy@sha256:ef8786bd894cf1746b432f9eb9e4cb6b50c48629eed75789734f3a7b8df7de28',
      port: 3306,
    },

    // Runs before an Argo CD rollout. Use for Rails-style schema migrations.
    migration: {
      enabled: false,
      command: [],
      args: [],
      activeDeadlineSeconds: 900,
      backoffLimit: 1,
    },
  },

  // Scaling configuration.
  scaling: {
    minScale: 1,  // minimum pods to keep running; a lower value is raised to 1
    maxScale: 0,  // maximum pods to scale up to (0 = unbounded)
  },

  // Application secrets.
  secrets: {
    // Secrets added as environment variables in the container:
    //   { name: 'SOME_USERNAME', secretKey: 'username', fromSecretName: 'some-secret' }
    // `secretKey` is the field of the secret to read, and defaults to `value`.
    envVars: [],

    // Secrets mounted as a directory of files, one per field:
    //   { path: '/secrets/another-secret', fromSecretName: 'another-secret' }
    mounts: [],

    // Services to read secrets from.
    sources: {
      // Read secrets from 1Password via the 1Password secret operator, which
      // syncs each item into a Kubernetes Secret of the same name.
      // https://developer.1password.com/docs/k8s/operator#kubernetes-secret-from-item
      onePassword: {
        // Default vault id to locate secrets in. Can be overridden per item.
        // References the "Frontier Secrets" vault.
        defaultVaultId: 'ihztemi2l6xl4zowypd2ef4sdy',

        // Items to sync: { name: 'some-secret', vaultId: 'optional-override' }
        items: [],
      },

      // Sealed secrets. Each item is self-describing — it carries its own consumer
      // wiring, so it can live in a per-environment file without leaving a dangling
      // reference in the other environment:
      //
      //   {
      //     name: 'my-secret',          // name of the resulting K8s Secret
      //     ciphertext: 'AgB1a2...',    // a Bitnami sealed-secrets ciphertext
      //     envVar: 'MY_SECRET',        // optional: inject as this env var
      //     mountPath: '/secrets/mine', // optional: mount the secret at this path
      //     expiresAt: '2027-01-15',    // optional, set by Homestead: annotation only
      //     updatedAt: '2026-10-14T19:02:11Z', // optional, set by Homestead: annotation only
      //     updatedBy: 'ada@withpersona.com',  // optional, set by Homestead: annotation only
      //   }
      //
      // The cluster's sealed-secrets controller decrypts each item into a K8s Secret
      // of the same `name` with a single data key `value`.
      sealedSecrets: {
        items: [],
      },
    },
  },

  // Service configuration.
  service: {
    port: 8080,
  },

  // Projected ServiceAccount token volumes. Each entry mounts a kubelet-rotated
  // projected ServiceAccount token (a native Kubernetes OIDC token scoped to a
  // custom `audience`) as a file in the container. The kubelet refreshes the file
  // in place, so consumers must read it fresh on each use.
  //
  //   {
  //     name: 'oracle-oidc',                        // volume name (a DNS label)
  //     audience: 'https://oracle.example',         // token `aud`; required
  //     mountPath: '/var/run/secrets/tokens/oracle', // directory mounted read-only
  //     fileName: 'token',                           // optional, default "token"
  //     expirationSeconds: 3600,                     // optional, default 3600
  //   }
  serviceAccountTokens: [],

  // Valkey key-value store, used as a cache. When enabled, provisions a dedicated
  // in-cluster instance and injects REDIS_URL=redis://valkey:6379 and
  // VALKEY_URL=redis://valkey:6379 into the container.
  valkey: {
    enabled: false,
    dataStorage: {
      enabled: true,
      requestedSize: '1Gi',
      storageClass: '',
    },
    // Recreate is required when dataStorage is enabled: a ReadWriteOnce PVC can't
    // attach to two pods at once.
    deploymentStrategy: 'Recreate',
    resources: {
      requests: { cpu: '100m', memory: '256Mi' },
      limits: { memory: '350Mi' },
    },
    // Appended to the base config (port, bind, data dir).
    valkeyConfig: |||
      maxmemory 200mb
      maxmemory-policy allkeys-lru
    |||,
    image: {
      repository: 'docker.io/valkey/valkey',
      tag: '9.0.2',
    },
  },

  // Health checks for the app container. Off by default; each takes a Kubernetes
  // probe as-is. Leave `port` out of httpGet and tcpSocket: Knative probes the
  // serving port (`service.port`) and rejects any other, so the library refuses
  // one. Knative fills in the missing port for readiness and liveness; for
  // startupProbe the library sets it to `service.port`. Knative's queue-proxy
  // runs the readiness probe and sends a pod no requests until it passes.
  readinessProbe: {},
  //   { httpGet: { path: '/readyz' }, periodSeconds: 5, failureThreshold: 3 }
  livenessProbe: {},
  //   { httpGet: { path: '/healthz' }, periodSeconds: 10, failureThreshold: 3 }
  startupProbe: {},
  //   { httpGet: { path: '/healthz' }, periodSeconds: 2, failureThreshold: 30 }

  // Limits voluntary evictions (node drains, cluster upgrades) of the app's pods
  // to one at a time. Rendered only when enabled AND scaling.minScale is 2 or
  // more; with one pod it would either protect nothing or block drains forever.
  // The deployer needs RBAC for policy/poddisruptionbudgets; the Frontier
  // gha-deploy ClusterRole does not grant it yet (see README).
  podDisruptionBudget: {
    enabled: false,
  },

  // Request timeout in seconds. Maximum is enforced by the cluster.
  // Requests exceeding this duration will receive a 504. Also the app pod's
  // shutdown grace period: Knative sets the pod's terminationGracePeriodSeconds
  // to this value and rejects setting it directly.
  timeoutSeconds: 300,

  // Where the app's hostname resolves: private = VPN only; public = open internet;
  // none = no hostname, so only other apps can reach it, at
  // http://app.<namespace>.svc.cluster.local
  visibility: 'private',
}
