// Config Connector StorageBuckets: the app's GCS buckets.
// https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/storage/storagebucket
local h = import 'helpers.libsonnet';
local storageBucket = (import 'libs.libsonnet').cnrm.storage.v1beta1.storageBucket;

{
  // `item` is a `gcsStorageBuckets` entry.
  bucket(cfg, item)::
    storageBucket.new(h.bucketName(item))
    + storageBucket.metadata.withAnnotations({
      'cnrm.cloud.google.com/force-destroy': 'true',
      'cnrm.cloud.google.com/project-id': 'persona-frontier',
    })
    + storageBucket.metadata.withLabels(h.labels(cfg))
    + storageBucket.spec.versioning.withEnabled(h.get(item, 'versioningEnabled', true))
    + storageBucket.spec.withLocation('US-CENTRAL1')
    + storageBucket.spec.withPublicAccessPrevention(h.get(item, 'preventPublicAccess', 'enforced'))
    + storageBucket.spec.withUniformBucketLevelAccess(true),
}
