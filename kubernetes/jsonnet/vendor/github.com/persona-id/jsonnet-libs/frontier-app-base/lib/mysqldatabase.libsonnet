// One dedicated Cloud SQL instance, database and IAM user for an opted-in
// Frontier namespace. Config Connector creates the GCP resources. The app logs
// in as its generated Google service account; Cloud SQL IAM database users are
// users, service accounts or groups, so a Kubernetes principal URL cannot be
// the database user.
local h = import 'helpers.libsonnet';

local profiles = {
  zonal: { availabilityType: 'ZONAL', tier: 'db-custom-2-7680' },
  'regional-ha': { availabilityType: 'REGIONAL', tier: 'db-custom-2-7680' },
};

local abandon = {
  'cnrm.cloud.google.com/deletion-policy': 'abandon',
};

local secretScript = |||
  set -eu
  api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}"
  token="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
  ca=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  auth="Authorization: Bearer ${token}"
  secret_url="${api}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets/${SECRET_NAME}"
  if curl --fail --silent --show-error --cacert "${ca}" --header "${auth}" --output /dev/null "${secret_url}"; then
    exit 0
  fi
  password="$(head -c 48 /dev/urandom | base64 | tr -d '\n' | head -c 48)"
  encoded_password="$(printf %s "${password}" | base64 | tr -d '\n')"
  body="$(printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"%s","namespace":"%s"},"type":"Opaque","data":{"password":"%s"}}' "${SECRET_NAME}" "${SECRET_NAMESPACE}" "${encoded_password}")"
  curl --fail --silent --show-error --cacert "${ca}" --header "${auth}" --header "Content-Type: application/json" --data "${body}" "${api}/api/v1/namespaces/${SECRET_NAMESPACE}/secrets"
|||;

local grantScript = |||
  set -eu
  i=0
  while [ "$i" -lt 60 ]; do
    if mysql --protocol=TCP --skip-ssl --host=127.0.0.1 --user=mysql-provisioner --password="$MYSQL_PROVISIONER_PASSWORD" --execute="GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%'"; then
      exit 0
    fi
    i=$((i + 1))
    sleep 10
  done
  exit 1
|||;

{
  app(cfg)::
    local profileName =
      if cfg.mysql.instance.profile == 'environment-default' then
        if h.isProduction(cfg) then 'regional-ha' else 'zonal'
      else cfg.mysql.instance.profile;
    local profile = profiles[profileName];
    local accountId = h.mysqlAccountId(cfg);
    local projectId = cfg.mysql.projectId;
    local instanceName = cfg.namespace;
    local databaseName = cfg.appName;
    local privateNetwork =
      if cfg.mysql.privateNetwork == ''
      then 'projects/%s/global/networks/default' % projectId
      else cfg.mysql.privateNetwork;
    // Datadog routes Cloud SQL monitors by the GCP user label `environment`.
    // The label follows the GCP project, not the app namespace: a -prod
    // namespace in the staging project is still a staging database.
    local environmentLabel =
      if std.endsWith(projectId, '-staging') then 'staging'
      else if h.isProduction(cfg) then 'production'
      else 'development';
    local iamServiceAccount = '%s@%s.iam.gserviceaccount.com' % [accountId, projectId];
    local connectionName = '%s:%s:%s' % [projectId, cfg.mysql.region, instanceName];
    local secretName = '%s-mysql-provisioner' % accountId;
    local labels = h.labels(cfg);
    local cnrmAnnotations = abandon { 'cnrm.cloud.google.com/project-id': projectId };

    {
      serviceAccount: {
        apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
        kind: 'IAMServiceAccount',
        metadata: {
          annotations: cnrmAnnotations,
          labels: labels,
          name: accountId,
        },
        spec: {
          displayName: 'Frontier %s MySQL' % cfg.appName,
          resourceID: accountId,
        },
      },

      // Lets the app's `app` KSA act as the service account above. Cloud SQL
      // Auth Proxy IAM login needs that service account's token.
      iamPolicy: {
        apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
        kind: 'IAMPolicy',
        metadata: {
          annotations: abandon,
          labels: labels,
          name: '%s-workload-identity' % accountId,
        },
        spec: {
          bindings: [{
            members: [
              'serviceAccount:%s.svc.id.goog[%s/app]' % [projectId, cfg.namespace],
            ],
            role: 'roles/iam.workloadIdentityUser',
          }],
          resourceRef: {
            apiVersion: 'iam.cnrm.cloud.google.com/v1beta1',
            kind: 'IAMServiceAccount',
            name: accountId,
          },
        },
      },

      instance: {
        apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
        kind: 'SQLInstance',
        metadata: {
          annotations: cnrmAnnotations,
          // Config Connector copies these onto the Cloud SQL user labels.
          labels: labels { environment: environmentLabel },
          name: instanceName,
        },
        spec: {
          databaseVersion: 'MYSQL_8_0',
          region: cfg.mysql.region,
          resourceID: instanceName,
          settings: {
            activationPolicy: 'ALWAYS',
            availabilityType: profile.availabilityType,
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
            databaseFlags: [
              { name: 'cloudsql_iam_authentication', value: 'on' },
              { name: 'performance_schema', value: 'off' },
            ],
            deletionProtectionEnabled: true,
            diskAutoresize: true,
            diskAutoresizeLimit: 0,
            diskSize: 100,
            diskType: 'PD_SSD',
            edition: 'ENTERPRISE',
            ipConfiguration: {
              ipv4Enabled: false,
              privateNetworkRef: { external: privateNetwork },
              sslMode: 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED',
            },
            maintenanceWindow: { day: 2, hour: 4 },
            pricingPlan: 'PER_USE',
            tier: profile.tier,
          },
        },
      },

      secretGeneratorServiceAccount: {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'PreSync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
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
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
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
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
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
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
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
                image: cfg.mysql.secretGenerator.image,
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

      database: {
        apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
        kind: 'SQLDatabase',
        metadata: {
          annotations: cnrmAnnotations,
          labels: labels,
          name: databaseName,
        },
        spec: {
          charset: 'utf8mb4',
          collation: 'utf8mb4_0900_ai_ci',
          instanceRef: { name: instanceName },
          resourceID: databaseName,
        },
      },

      user: {
        apiVersion: 'sql.cnrm.cloud.google.com/v1beta1',
        kind: 'SQLUser',
        metadata: {
          annotations: cnrmAnnotations,
          labels: labels,
          name: accountId,
        },
        spec: {
          instanceRef: { name: instanceName },
          resourceID: iamServiceAccount,
          type: 'CLOUD_IAM_SERVICE_ACCOUNT',
        },
      },

      // Uses the built-in provisioner only to grant the app IAM user access to
      // its own database. Retries until Cloud SQL has finished creating both.
      grantJob: {
        apiVersion: 'batch/v1',
        kind: 'Job',
        metadata: {
          annotations: {
            'argocd.argoproj.io/hook': 'Sync',
            'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded',
            'argocd.argoproj.io/sync-wave': '0',
          },
          labels: labels,
          name: '%s-mysql-grants' % accountId,
        },
        spec: {
          activeDeadlineSeconds: 2400,
          backoffLimit: 2,
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
                  failureThreshold: 1800,
                  httpGet: { path: '/startup', port: 9091 },
                  periodSeconds: 1,
                },
              }],
              containers: [{
                args: [grantScript],
                command: ['/bin/sh', '-c'],
                env: [
                  { name: 'MYSQL_DATABASE', value: databaseName },
                  { name: 'MYSQL_USER', value: accountId },
                  {
                    name: 'MYSQL_PROVISIONER_PASSWORD',
                    valueFrom: { secretKeyRef: { key: 'password', name: secretName } },
                  },
                ],
                image: cfg.mysql.client.image,
                name: 'grant',
                securityContext: { allowPrivilegeEscalation: false },
              }],
              restartPolicy: 'Never',
              serviceAccountName: 'app',
            },
          },
        },
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
