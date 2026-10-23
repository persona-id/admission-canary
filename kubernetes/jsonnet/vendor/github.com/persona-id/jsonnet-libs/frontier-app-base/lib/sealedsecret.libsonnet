// SealedSecrets: encrypted secrets kept in the app's repo. The sealed-secrets
// controller decrypts each into a Secret of the same name with a single data key
// `value`.
// https://github.com/bitnami-labs/sealed-secrets
local h = import 'helpers.libsonnet';

// No jsonnet-libs package covers this CRD; shaped like the generated constructors.
local sealedSecret = {
  metadata:: {
    withLabels(labels):: { metadata+: { labels: labels } },
    withAnnotations(annotations):: { metadata+: { annotations: annotations } },
  },
  new(name):: { apiVersion: 'bitnami.com/v1alpha1', kind: 'SealedSecret', metadata: { name: name } },
  spec:: {
    template:: {
      metadata:: { withName(name):: { spec+: { template+: { metadata+: { name: name } } } } },
      withType(type):: { spec+: { template+: { type: type } } },
    },
    withEncryptedData(encryptedData):: { spec+: { encryptedData: encryptedData } },
  },
};

// Item metadata Homestead reads from the cluster. Passed through as strings,
// unvalidated: Homestead flags a bad date rather than failing the deploy.
local annotationKeys = {
  expiresAt: 'frontier.withpersona.com/expires-at',
  updatedAt: 'frontier.withpersona.com/updated-at',
  updatedBy: 'frontier.withpersona.com/updated-by',
};

{
  // `item` is a `secrets.sources.sealedSecrets.items` entry.
  item(cfg, item)::
    local name = h.normalize(item.name);
    local annotations = {
      [annotationKeys[field]]: std.toString(item[field])
      for field in std.objectFields(annotationKeys)
      if h.get(item, field, '') != ''
    };
    sealedSecret.new(name)
    + sealedSecret.metadata.withLabels(h.labels(cfg))
    + (if std.length(annotations) > 0 then sealedSecret.metadata.withAnnotations(annotations) else {})
    + sealedSecret.spec.template.metadata.withName(name)
    + sealedSecret.spec.template.withType('Opaque')
    + sealedSecret.spec.withEncryptedData({ value: item.ciphertext }),
}
