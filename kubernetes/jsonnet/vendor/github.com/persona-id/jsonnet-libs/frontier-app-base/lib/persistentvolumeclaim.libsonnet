// PersistentVolumeClaims: the disk behind each Valkey instance that keeps one.
local h = import 'helpers.libsonnet';
local pvc = (import 'libs.libsonnet').k.core.v1.persistentVolumeClaim;

{
  valkey(cfg, instance)::
    local storage = instance.storage;
    pvc.new(storage.claimName)
    + pvc.metadata.withLabels(h.valkeyLabels(cfg, instance))
    + pvc.spec.resources.withRequests({ storage: storage.size })
    + pvc.spec.withAccessModes(['ReadWriteOnce'])
    + (if storage.storageClass != '' then pvc.spec.withStorageClassName(storage.storageClass) else {})
    + pvc.spec.withVolumeMode('Filesystem'),
}
