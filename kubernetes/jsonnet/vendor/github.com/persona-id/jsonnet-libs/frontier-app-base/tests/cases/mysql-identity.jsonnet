local cfg = import '../../config.libsonnet';
local serviceAccount = import '../../lib/serviceaccount.libsonnet';

local mysqlIdentityCfg = cfg {
  appName: 'mysql-identity',
  namespace: 'frontier-mysql-identity-prod',
  gcpProject: 'persona-frontier-staging',
  mysql: {
    enabled: true,
  },
};

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-identity-test' },
  data: {
    generatedIdentity:
      serviceAccount.mysqlProxy(mysqlIdentityCfg).metadata.annotations['iam.gke.io/gcp-service-account'],
  },
}
