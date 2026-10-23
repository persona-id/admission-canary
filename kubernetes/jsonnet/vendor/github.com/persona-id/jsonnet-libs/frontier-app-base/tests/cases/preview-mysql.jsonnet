// A preview of a MySQL app must not provision a database, migrate, or connect.
local frontier = import '../../main.libsonnet';

local rendered = frontier.toList(frontier.preview({
  appName: 'demo-dev',
  namespace: 'frontier-demo-dev',
  permissions: { owner: 'owner' },
  mysql: {
    enabled: true,
    migration: { enabled: true, command: ['bin/run-migrations'] },
  },
}, '7'));

local kinds = std.set([item.kind for item in rendered]);
local names = std.set([item.metadata.name for item in rendered]);
local containerNames = std.set(std.flatMap(
  function(item)
    if std.objectHas(item, 'spec') && std.objectHas(item.spec, 'template') then
      [std.get(container, 'name', '') for container in std.get(item.spec.template.spec, 'containers', [])]
      + [std.get(container, 'name', '') for container in std.get(item.spec.template.spec, 'initContainers', [])]
    else [],
  rendered
));
local mysqlEnv = std.set(std.flatMap(
  function(item)
    if std.objectHas(item, 'spec') && std.objectHas(item.spec, 'template') then
      [
        env.name
        for container in std.get(item.spec.template.spec, 'containers', [])
        for env in std.get(container, 'env', [])
        if std.startsWith(env.name, 'MYSQL_')
      ]
    else [],
  rendered
));

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'preview-mysql-test' },
  data: {
    hasCloudSqlProxy: std.toString(std.member(containerNames, 'cloud-sql-proxy')),
    hasMysqlDatabase: std.toString(std.member(kinds, 'MysqlDatabase') || std.member(kinds, 'SQLInstance')),
    hasMysqlMigration: std.toString(std.member(names, 'mysql-migrate')),
    mysqlEnv: std.join(',', mysqlEnv),
  },
}
