// MongoDatabases: the app's database on the shared Frontier Atlas cluster.
// Provisioned by kro in mongodb-atlas-system, which writes the `mongo-credentials`
// Secret back into the app's namespace; the namespace is the only input.
local h = import 'helpers.libsonnet';

// No jsonnet-libs package covers this CRD; shaped like the generated constructors.
local mongoDatabase = {
  metadata:: { withLabels(labels):: { metadata+: { labels: labels } } },
  new(name):: { apiVersion: 'frontier.withpersona.com/v1alpha1', kind: 'MongoDatabase', metadata: { name: name } },
};

{
  app(cfg)::
    mongoDatabase.new(cfg.appName)
    + mongoDatabase.metadata.withLabels(h.labels(cfg)),
}
