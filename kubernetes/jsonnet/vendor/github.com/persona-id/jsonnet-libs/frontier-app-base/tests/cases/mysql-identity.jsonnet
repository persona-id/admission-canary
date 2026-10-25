local cfg = import '../../config.libsonnet';
local h = import '../../lib/helpers.libsonnet';
local serviceAccount = import '../../lib/serviceaccount.libsonnet';

local mysqlIdentityCfg = cfg {
  appName: 'mysql-identity',
  namespace: 'frontier-mysql-identity-prod',
  mysql: {
    enabled: true,
    projectId: 'persona-frontier-staging',
  },
};

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-identity-test' },
  data: {
    generatedIdentity:
      serviceAccount.mysqlProxy(mysqlIdentityCfg).metadata.annotations['iam.gke.io/gcp-service-account'],
    longName:
      h.mysqlAccountId(cfg {
        namespace: 'frontier-abcdefghijklmnopqrstuvwxyz-prod',
      }),
  },
}
