// FrontierPreviews: the Secrets a preview environment borrows from its app's dev
// namespace. Provisioned by kro in persona-kubernetes, which works out the dev
// namespace from the CR's own namespace and copies each named Secret from it.
local h = import 'helpers.libsonnet';

// No jsonnet-libs package covers this CRD; shaped like the generated constructors.
local frontierPreview = {
  metadata:: { withLabels(labels):: { metadata+: { labels: labels } } },
  new(name):: { apiVersion: 'frontier.withpersona.com/v1alpha1', kind: 'FrontierPreview', metadata: { name: name } },
  spec:: {
    withSecrets(secrets):: { spec+: { secrets: secrets } },
  },
};

{
  // Every Secret the app's workloads read: its sealed and 1Password items, the ones
  // its env vars and mounts name, and Mongo's credentials.
  secretNames(cfg)::
    local sources = cfg.secrets.sources;
    local resolved = h.resolvedSecrets(cfg);
    std.set(
      [h.normalize(item.name) for item in sources.sealedSecrets.items + sources.onePassword.items]
      + [h.normalize(s.fromSecretName) for s in resolved.envVars + resolved.mounts]
      + (if cfg.mongo.enabled then ['mongo-credentials'] else [])
    ),

  app(cfg)::
    frontierPreview.new('preview')
    + frontierPreview.metadata.withLabels(h.labels(cfg))
    + frontierPreview.spec.withSecrets($.secretNames(cfg)),
}
