// One dedicated Cloud SQL instance for an opted-in Frontier namespace, plus the
// app database, any extra databases, the app's IAM user and any extra IAM
// users. Config Connector creates the GCP resources. The app logs in as its
// generated Google service account; Cloud SQL IAM database users are users,
// service accounts or groups, so a Kubernetes principal URL cannot be the
// database user.
local h = import 'helpers.libsonnet';
local serviceAccount = import 'serviceaccount.libsonnet';

local secretScript = |||
  set -eu
  api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}"
  token="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
  ca=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  export SSL_CERT_FILE="${ca}"
  auth="Authorization: Bearer ${token}"
  secret_url="${api}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets/${SECRET_NAME}"
  if wget -q --header="${auth}" -O /dev/null "${secret_url}"; then
    exit 0
  fi
  password="$(head -c 48 /dev/urandom | base64 | tr -d '\n' | head -c 48)"
  encoded_password="$(printf %s "${password}" | base64 | tr -d '\n')"
  body="$(printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"%s","namespace":"%s"},"type":"Opaque","data":{"password":"%s"}}' "${SECRET_NAME}" "${SECRET_NAMESPACE}" "${encoded_password}")"
  wget -q --header="${auth}" --header="Content-Type: application/json" --post-data="${body}" -O /dev/null "${api}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets"
|||;

local grantScript = |||
  set -eu
  i=0
  while [ "$i" -lt 30 ]; do
    if mysql --connect-timeout=10 --protocol=TCP --skip-ssl --host=127.0.0.1 --user=mysql-provisioner --execute="$MYSQL_GRANTS"; then
      exit 0
    fi
    i=$((i + 1))
    sleep 10
  done
  exit 1
|||;

{
  app(cfg)::
    local instanceSettings = h.mysqlInstanceSettings(cfg);
    // abandon (default) leaves the Cloud SQL instance, database, users and
    // IAM objects in GCP when their Kubernetes object is deleted. delete
    // actually deletes them, with no final backup: Config Connector's
    // version in this cluster doesn't support one. Available in dev and prod.
    local deletionAnnotations =
      if cfg.mysql.instance.deletionPolicy == 'delete' then {}
      else { 'cnrm.cloud.google.com/deletion-policy': 'abandon' };
    local accountId = h.mysqlAccountId(cfg);
    local projectId = h.mysqlProjectId(cfg);
    local instanceName = cfg.namespace;
    local databaseName = h.mysqlAppDatabase(cfg);
    local privateNetwork = h.mysqlPrivateNetwork(cfg);
    // Datadog routes Cloud SQL monitors by the GCP user label `environment`.
    // The label follows the GCP project, not the app namespace: a -prod
    // namespace in the staging project is still a staging database.
    local environmentLabel =
      if std.endsWith(projectId, '-staging') then 'staging'
      else if h.isProduction(cfg) then 'production'
      else 'development';
    local connectionName = '%s:%s:%s' % [projectId, h.mysqlRegion, instanceName];
    local secretName = '%s-mysql-provisioner' % accountId;
    local labels = h.labels(cfg);
    local cnrmAnnotations = deletionAnnotations { 'cnrm.cloud.google.com/project-id': projectId };
    // Cloud SQL's MySQL username is the part before '@' for an IAM user, a
    // service account, and a group. The Cloud SQL API still takes the full email.
    local mysqlLogin(user) = std.split(user.email, '@')[0];
    local databaseSpecs = [
      { name: databaseName, collation: cfg.mysql.collation },
    ] + [
      { name: db.name, collation: h.get(db, 'collation', cfg.mysql.collation) }
      for db in cfg.mysql.databases
    ];
    // The app user gets everything on every database. Each extra user is reset
    // to exactly its configured grants, so narrowing them takes effect.
    // Cloud SQL may leave a built-in root@% that every project service account
    // could reach through the Auth Proxy, so it goes before any grant.
    // The reset is per database: Cloud SQL's partial revokes keep the
    // provisioner out of `sys`, so a global REVOKE ALL is refused (error 3879).
    // MySQL only accepts ALL and GRANT OPTION together in the global form.
    local resetSql(login, privileges, databases) = std.flattenArrays([
      [
        "REVOKE IF EXISTS ALL PRIVILEGES ON `%s`.* FROM '%s'@'%%';" % [db.name, login],
        "REVOKE IF EXISTS GRANT OPTION ON `%s`.* FROM '%s'@'%%';" % [db.name, login],
      ]
      for db in databaseSpecs
    ]) + [
      "GRANT %s ON `%s`.* TO '%s'@'%%';" % [std.join(', ', privileges), db, login]
      for db in databases
    ];
    local grantSql = std.join(' ', ["DROP USER IF EXISTS 'root'@'%';"] + [
      "GRANT ALL PRIVILEGES ON `%s`.* TO '%s'@'%%';" % [db.name, accountId]
      for db in databaseSpecs
    ] + std.flattenArrays([
      resetSql(mysqlLogin(user), h.mysqlUserPrivileges(user), h.mysqlUserDatabases(cfg, user))
      for user in cfg.mysql.users
    ] + [
      resetSql(h.mysqlAccountIdFor(cfg, c), h.mysqlUserPrivileges(c), h.mysqlUserDatabases(cfg, c))
      for c in h.mysqlConnections(cfg)
    ]));
    // The Google service account, its Workload Identity binding and its IAM
    // database user, for the app (connection null) or a `mysql.connections` entry.
    local identity(connection) =
      local id = h.mysqlAccountIdFor(cfg, connection);
      {
        serviceAccount: {
          apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
          kind: 'IAMServiceAccount',
          metadata: {
            annotations: cnrmAnnotations,
            labels: labels,
            name: id,
          },
          spec: {
            displayName: if connection == null then 'Frontier %s MySQL' % cfg.appName else 'Frontier %s MySQL %s' % [cfg.appName, connection.name],
            resourceID: id,
          },
        },

        // Lets the proxy's KSA act as the service account above. Cloud SQL
        // Auth Proxy IAM login needs that service account's token.
        iamPolicy: {
          apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
          kind: 'IAMPolicy',
          metadata: {
            annotations: deletionAnnotations,
            labels: labels,
            name: '%s-workload-identity' % id,
          },
          spec: {
            bindings: [{
              members: [
                'serviceAccount:%s.svc.id.goog[%s/%s]' % [projectId, cfg.namespace, h.mysqlProxyServiceFor(connection)],
              ],
              role: 'roles/iam.workloadIdentityUser',
            }],
            resourceRef: {
              apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
              kind: 'IAMServiceAccount',
              name: id,
            },
          },
        },

        user: {
          apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
          kind: 'SQLUser',
          metadata: {
            annotations: cnrmAnnotations,
            labels: labels,
            name: id,
          },
          spec: {
            instanceRef: { name: instanceName },
            resourceID: '%s@%s.iam.gserviceaccount.com' % [id, projectId],
            type: 'CLOUD_IAM_SERVICE_ACCOUNT',
          },
        },
      };
    // The only pods that run as that service account. App pods connect to the
    // proxy's Service instead of sharing its identity.
    local proxy(connection) =
      local name = h.mysqlProxyServiceFor(connection);
      {
        proxyServiceAccount: serviceAccount.mysqlProxy(cfg, connection),

        proxyDeployment: {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          metadata: {
            // The Frontier Datadog agent turns these into owner_* tags on
            // kubernetes_state.deployment.*, so a proxy-down alert reaches the
            // owner the same way the Cloud SQL instance alerts do.
            labels: labels + {
              ['frontier.withpersona.com/' + key]: value
              for key in std.objectFields(h.mysqlOwnerLabels(cfg))
              for value in [h.mysqlOwnerLabels(cfg)[key]]
            },
            name: name,
          },
          spec: {
            replicas: 2,
            selector: {
              matchLabels: { 'frontier.withpersona.com/workload': name },
            },
            template: {
              metadata: {
                // The proxy receives this through mysql-connection as an env var.
                // Changing its GCP project or instance must restart existing pods.
                annotations: {
                  'frontier.withpersona.com/mysql-connection-name': connectionName,
                },
                labels: labels { 'frontier.withpersona.com/workload': name },
              },
              spec: {
                containers: [h.mysqlProxyContainer(cfg)],
                serviceAccountName: name,
                // Longer than proxy.shutdownDelaySeconds so the process can
                // finish closing connections before the pod is killed.
                terminationGracePeriodSeconds: cfg.mysql.proxy.shutdownDelaySeconds + 15,
                // The two replicas prefer different nodes, so one drain
                // doesn't stop both.
                affinity: {
                  podAntiAffinity: {
                    preferredDuringSchedulingIgnoredDuringExecution: [{
                      weight: 100,
                      podAffinityTerm: {
                        labelSelector: { matchLabels: { 'frontier.withpersona.com/workload': name } },
                        topologyKey: 'kubernetes.io/hostname',
                      },
                    }],
                  },
                },
              },
            },
          },
        },

        // At most one replica is evicted at a time, so a drain always leaves
        // one proxy serving.
        proxyDisruptionBudget: {
          apiVersion: 'policy/v1',
          kind: 'PodDisruptionBudget',
          metadata: {
            labels: labels,
            name: name,
          },
          spec: {
            maxUnavailable: 1,
            selector: { matchLabels: { 'frontier.withpersona.com/workload': name } },
          },
        },

        // MySQL speaks first. Under PERMISSIVE mTLS the proxy's sidecar waits for
        // the client's first bytes to detect TLS while the client waits for the
        // server greeting, so every connection through the Service times out.
        proxyPeerAuthentication: {
          apiVersion: 'security.istio.io/v1',
          kind: 'PeerAuthentication',
          metadata: {
            labels: labels,
            name: '%s-mtls-strict' % name,
          },
          spec: {
            mtls: { mode: 'STRICT' },
            selector: { matchLabels: { 'frontier.withpersona.com/workload': name } },
          },
        },

        proxyService: {
          apiVersion: 'v1',
          kind: 'Service',
          metadata: {
            labels: labels,
            name: name,
          },
          spec: {
            ports: [{
              // A tcp- name makes the port opaque TCP, so Istio never waits to sniff the protocol.
              name: 'tcp-mysql',
              port: cfg.mysql.proxy.port,
              targetPort: cfg.mysql.proxy.port,
            }],
            selector: { 'frontier.withpersona.com/workload': name },
          },
        },
      };
    // Always abandoned: deleting the instance already drops its databases, and
    // Config Connector deletes a database through its instance, so a database
    // pruned alongside a deleted instance would wait on it forever.
    local sqlDatabase(db) = {
      apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
      kind: 'SQLDatabase',
      metadata: {
        annotations: cnrmAnnotations { 'cnrm.cloud.google.com/deletion-policy': 'abandon' },
        labels: labels,
        name: h.mysqlDatabaseObjectName(db.name),
      },
      spec: {
        charset: 'utf8mb4',
        collation: db.collation,
        instanceRef: { name: instanceName },
        resourceID: db.name,
      },
    };

    {
      serviceAccount: identity(null).serviceAccount,
      iamPolicy: identity(null).iamPolicy,

      instance: {
        apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
        kind: 'SQLInstance',
        metadata: {
          annotations: cnrmAnnotations,
          // Config Connector copies these onto the Cloud SQL user labels.
          // owner_* is permissions.owner split on ".", so a CPU alert can
          // address that person. See helpers.mysqlOwnerLabels.
          labels: labels { environment: environmentLabel } + h.mysqlOwnerLabels(cfg),
          name: instanceName,
        },
        spec: {
          databaseVersion: cfg.mysql.version,
          region: h.mysqlRegion,
          resourceID: instanceName,
          settings: {
            activationPolicy: 'ALWAYS',
            availabilityType: instanceSettings.availabilityType,
            backupConfiguration: {
              backupRetentionSettings: {
                retainedBackups: 7,
                retentionUnit: 'COUNT',
              },
              binaryLogEnabled: true,
              enabled: true,
              startTime: '14:00',
              transactionLogRetentionDays: 7,
            },
            // IAM login is always on. performance_schema defaults to off, for
            // the small shared-core tier, unless databaseFlags sets it.
            databaseFlags: [
              { name: 'cloudsql_iam_authentication', value: 'on' },
            ] + (
              if std.member([h.get(f, 'name', '') for f in cfg.mysql.instance.databaseFlags], 'performance_schema') then []
              else [{ name: 'performance_schema', value: 'off' }]
            ) + cfg.mysql.instance.databaseFlags,
            deletionProtectionEnabled: cfg.mysql.instance.deletionPolicy != 'delete',
            diskAutoresize: true,
            diskAutoresizeLimit: instanceSettings.diskAutoresizeLimit,
            diskSize: instanceSettings.diskSize,
            diskType: 'PD_SSD',
            edition: 'ENTERPRISE',
            ipConfiguration: {
              ipv4Enabled: false,
              privateNetworkRef: { external: privateNetwork },
              sslMode: 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED',
            },
            maintenanceWindow: { day: 2, hour: 4 },
            pricingPlan: 'PER_USE',
            tier: instanceSettings.tier,
          },
        },
      },

      secretGeneratorServiceAccount: {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'PreSync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
            'argocd.argoproj.io/sync-wave': '-1',
          },
          labels: labels,
          name: 'mysql-secret-generator',
        },
      },

      secretGeneratorRole: {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'Role',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'PreSync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
            'argocd.argoproj.io/sync-wave': '-1',
          },
          labels: labels,
          name: 'mysql-secret-generator',
        },
        rules: [
          {
            apiGroups: [''],
            resources: ['secrets'],
            verbs: ['create'],
          },
          {
            apiGroups: [''],
            resourceNames: [secretName],
            resources: ['secrets'],
            verbs: ['get'],
          },
        ],
      },

      secretGeneratorRoleBinding: {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'RoleBinding',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'PreSync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
            'argocd.argoproj.io/sync-wave': '-1',
          },
          labels: labels,
          name: 'mysql-secret-generator',
        },
        roleRef: {
          apiGroup: 'rbac.authorization.k8s.io',
          kind: 'Role',
          name: 'mysql-secret-generator',
        },
        subjects: [{
          kind: 'ServiceAccount',
          name: 'mysql-secret-generator',
          namespace: cfg.namespace,
        }],
      },

      // Config Connector gives a built-in MySQL user cloudsqlsuperuser.
      // Generate its password inside the cluster rather than storing it in git.
      provisionerSecretJob: {
        apiVersion: 'batch/v1',
        kind: 'Job',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'PreSync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
          },
          labels: labels,
          name: '%s-mysql-secret' % accountId,
        },
        spec: {
          backoffLimit: 6,
          template: {
            spec: {
              containers: [{
                args: [secretScript],
                command: ['/bin/sh', '-c'],
                env: [
                  { name: 'SECRET_NAME', value: secretName },
                  { name: 'SECRET_NAMESPACE', value: cfg.namespace },
                ],
                image: cfg.mysql.client.image,
                name: 'generate',
                securityContext: { allowPrivilegeEscalation: false },
              }],
              restartPolicy: 'Never',
              serviceAccountName: 'mysql-secret-generator',
            },
          },
        },
      },

      provisionerUser: {
        apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
        kind: 'SQLUser',
        metadata: {
          annotations: cnrmAnnotations,
          labels: labels,
          name: secretName,
        },
        spec: {
          host: '%',
          instanceRef: { name: instanceName },
          password: {
            valueFrom: {
              secretKeyRef: { key: 'password', name: secretName },
            },
          },
          resourceID: 'mysql-provisioner',
        },
      },

      database: sqlDatabase(databaseSpecs[0]),

      extraDatabases: {
        [db.name]: sqlDatabase(db)
        for db in databaseSpecs
        if db.name != databaseName
      },

      // Removing an entry deletes the MySQL user and its grants, whatever the
      // instance's deletionPolicy: a person's access shouldn't outlive the config.
      extraUsers: {
        [user.name]: {
          apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
          kind: 'SQLUser',
          metadata: {
            annotations: { 'cnrm.cloud.google.com/project-id': projectId },
            labels: labels,
            name: user.name,
          },
          spec: {
            instanceRef: { name: instanceName },
            resourceID: user.email,
            type: user.type,
          },
        }
        for user in cfg.mysql.users
      },

      user: identity(null).user,

      // Uses the built-in provisioner only to grant the app IAM user access to
      // its own database. This waits up to five minutes for IAM propagation.
      grantJob: {
        apiVersion: 'batch/v1',
        kind: 'Job',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'Sync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
            // Wait for Config Connector's wave 0 objects first. An admission
            // denial must fail this sync before this hook starts retrying.
            'argocd.argoproj.io/sync-wave': '1',
          },
          labels: labels,
          name: '%s-mysql-grants' % accountId,
        },
        spec: {
          activeDeadlineSeconds: 360,
          backoffLimit: 0,
          template: {
            metadata: {
              labels: labels { 'app.kubernetes.io/name': 'frontier-mysql-provisioner' },
            },
            spec: {
              initContainers: [{
                args: [
                  '--health-check',
                  '--http-address=0.0.0.0',
                  '--http-port=9091',
                  '--private-ip',
                  '--port=3306',
                  connectionName,
                ],
                image: cfg.mysql.proxy.image,
                name: 'cloud-sql-proxy',
                restartPolicy: 'Always',
                securityContext: {
                  allowPrivilegeEscalation: false,
                  runAsNonRoot: true,
                },
                startupProbe: {
                  failureThreshold: 300,
                  httpGet: { path: '/startup', port: 9091 },
                  periodSeconds: 1,
                },
              }],
              containers: [{
                args: [grantScript],
                command: ['/bin/sh', '-c'],
                env: [
                  { name: 'MYSQL_GRANTS', value: grantSql },
                  {
                    name: 'MYSQL_PWD',
                    valueFrom: { secretKeyRef: { key: 'password', name: secretName } },
                  },
                ],
                image: cfg.mysql.client.image,
                name: 'grant',
                securityContext: { allowPrivilegeEscalation: false },
              }],
              restartPolicy: 'Never',
              serviceAccountName: h.mysqlProxyService,
            },
          },
        },
      },

      // The grant job above keeps its own loopback proxy, because that client
      // shares the pod.
      proxyServiceAccount: proxy(null).proxyServiceAccount,
      proxyDeployment: proxy(null).proxyDeployment,
      proxyDisruptionBudget: proxy(null).proxyDisruptionBudget,
      proxyPeerAuthentication: proxy(null).proxyPeerAuthentication,
      proxyService: proxy(null).proxyService,

      // Each `mysql.connections` entry: its own identity, IAM user and proxy.
      connections: {
        [c.name]: identity(c) + proxy(c)
        for c in h.mysqlConnections(cfg)
      },

      connection: {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          labels: labels,
          name: 'mysql-connection',
        },
        data: {
          database: databaseName,
          instanceConnectionName: connectionName,
          // Cloud SQL drops @ and the domain. The MySQL user is the account id.
          user: accountId,
        },
      },
    },
}
