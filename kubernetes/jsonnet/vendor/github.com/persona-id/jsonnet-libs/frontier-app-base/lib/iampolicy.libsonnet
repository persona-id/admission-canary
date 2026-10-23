// Config Connector IAMPolicies: each GCS bucket's permissions. Authoritative, so
// permissions set anywhere else, including the console, are reverted.
// https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/iam/iampolicy
local h = import 'helpers.libsonnet';
local iamPolicy = (import 'libs.libsonnet').cnrm.iam.v1beta1.iamPolicy;

local binding = iamPolicy.spec.bindings;

// The `app` ServiceAccount, through GKE workload identity; no static keys.
local appMember(cfg) =
  'principal://iam.googleapis.com/projects/1081356511525/locations/global/workloadIdentityPools/persona-frontier.svc.id.goog/subject/ns/%s/sa/app'
  % cfg.namespace;

{
  // `item` is a `gcsStorageBuckets` entry. The app's role joins that role's binding
  // if `additionalPermissions` has one.
  bucket(cfg, item)::
    local name = h.bucketName(item);
    local appRole = h.get(item, 'appPermissions', 'roles/storage.objectUser');
    local additional = h.get(item, 'additionalPermissions', {});

    iamPolicy.new(name)
    + iamPolicy.metadata.withLabels(h.labels(cfg))
    + iamPolicy.spec.resourceRef.withKind('StorageBucket')
    + iamPolicy.spec.resourceRef.withName(name)
    + iamPolicy.spec.withBindings(
      [
        binding.withMembers(additional[role] + (if role == appRole then [appMember(cfg)] else []))
        + binding.withRole(role)
        for role in std.objectFields(additional)
      ]
      + (if std.objectHas(additional, appRole) then [] else [
           binding.withMembers([appMember(cfg)]) + binding.withRole(appRole),
         ])
    ),
}
