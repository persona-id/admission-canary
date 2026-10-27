// The Frontier MySQL admission policy scopes its enforcement to namespaces
// carrying this label, so only MySQL-opted-in apps are affected.
local cfg = import '../../config.libsonnet';
local namespace = import '../../lib/namespace.libsonnet';

local withoutMysql = cfg { appName: 'demo', namespace: 'frontier-demo-prod' };
local withMysql = withoutMysql { mysql+: { enabled: true, projectId: 'persona-frontier-staging' } };

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'mysql-namespace-label-test' },
  data: {
    withoutMysql: std.toString('frontier.withpersona.com/mysql-database' in namespace.app(withoutMysql).metadata.labels),
    withMysql: namespace.app(withMysql).metadata.labels['frontier.withpersona.com/mysql-database'],
  },
}
