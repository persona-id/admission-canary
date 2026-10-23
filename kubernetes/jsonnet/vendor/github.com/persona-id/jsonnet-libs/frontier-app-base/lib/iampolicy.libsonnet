// Config Connector IAMPartialPolicies: each GCS bucket's permissions. Config
// Connector manages only the members listed here and leaves the bucket's other
// members alone, so a preview environment's IAMPolicyMember can sit beside them.
// https://docs.cloud.google.com/config-connector/docs/reference/resource-docs/iam/iampartialpolicy
local h = import 'helpers.libsonnet';
local cnrmIam = (import 'libs.libsonnet').cnrm.iam.v1beta1;
local iamPartialPolicy = cnrmIam.iamPartialPolicy;
local iamPolicyMember = cnrmIam.iamPolicyMember;

local binding = iamPartialPolicy.spec.bindings;

// The roles a preview environment may take on a dev bucket; none can change the bucket's IAM.
local previewBucketRoles = ['roles/storage.objectCreator', 'roles/storage.objectUser', 'roles/storage.objectViewer'];

// The `app` ServiceAccount, through GKE workload identity; no static keys.
local appMember(cfg) =
  'principal://iam.googleapis.com/projects/1081356511525/locations/global/workloadIdentityPools/persona-frontier.svc.id.goog/subject/ns/%s/sa/app'
  % cfg.namespace;

local members(list) = [binding.members.withMember(m) for m in list];

{
  // `item` is a `gcsStorageBuckets` entry. The app's role joins that role's binding
  // if `additionalPermissions` has one.
  bucket(cfg, item)::
    local name = h.bucketName(item);
    local appRole = h.bucketAppRole(item);
    local additional = h.get(item, 'additionalPermissions', {});

    iamPartialPolicy.new(name)
    + iamPartialPolicy.metadata.withLabels(h.labels(cfg))
    + iamPartialPolicy.spec.resourceRef.withKind('StorageBucket')
    + iamPartialPolicy.spec.resourceRef.withName(name)
    + iamPartialPolicy.spec.withBindings(
      [
        binding.withMembers(members(additional[role] + (if role == appRole then [appMember(cfg)] else [])))
        + binding.withRole(role)
        for role in std.objectFields(additional)
      ]
      + (if std.objectHas(additional, appRole) then [] else [
           binding.withMembers(members([appMember(cfg)])) + binding.withRole(appRole),
         ])
    ),

  // Grants a preview environment's `app` the dev app's role on dev bucket `item`.
  // The reference only resolves to a StorageBucket in `devNamespace`, so a preview
  // reaches its own app's dev buckets and no others.
  previewBucket(cfg, devNamespace, item)::
    local name = h.bucketName(item);
    local role = h.bucketAppRole(item);
    assert std.member(previewBucketRoles, role) :
           'gcsStorageBuckets appPermissions "%s" cannot be granted to a preview environment; use one of %s.'
           % [role, std.join(', ', previewBucketRoles)];

    iamPolicyMember.new(name)
    + iamPolicyMember.metadata.withLabels(h.labels(cfg))
    + iamPolicyMember.spec.resourceRef.withKind('StorageBucket')
    + iamPolicyMember.spec.resourceRef.withName(name)
    + iamPolicyMember.spec.resourceRef.withNamespace(devNamespace)
    + iamPolicyMember.spec.withMember(appMember(cfg))
    + iamPolicyMember.spec.withRole(role),
}
