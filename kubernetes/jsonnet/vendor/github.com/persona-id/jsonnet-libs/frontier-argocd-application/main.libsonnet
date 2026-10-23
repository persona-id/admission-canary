// frontier-argocd-application: the ArgoCD Application an app on Frontier is deployed by,
// built with argo-cd-libsonnet.
//
//   local argocd = import 'github.com/persona-id/jsonnet-libs/frontier-argocd-application/main.libsonnet';
//
// `newFrontierApp` is the Application for one environment of a repo built from
// persona-template-frontier-app, whose kubernetes/jsonnet/<env>/main.jsonnet renders
// frontier-app-base. `newProject` is the AppProject for one app registered in
// frontier-app-registry, `newPreviewProject` the one for its pull request previews,
// and `newPreviewAccessProject` the one for their access to dev.
local argocd = import 'github.com/jsonnet-libs/argo-cd-libsonnet/3.2/main.libsonnet';

local application = argocd.argoproj.v1alpha1.application;
local appProject = argocd.argoproj.v1alpha1.appProject;
local source = application.spec.source;

local githubOrg = 'https://github.com/persona-id/';

// The repository name in `repoURL`, which names a registered app everywhere: its
// registry/<name>.json in frontier-app-registry, its AppProject and its namespaces.
// The registry's checks apply: lowercase letters, digits and dashes, starting and
// ending with a letter or digit, and at most 47 characters, so that
// frontier-<name>-prod still fits a namespace's 63.
local appNameOf(repoURL) =
  assert std.startsWith(repoURL, githubOrg) && !std.endsWith(repoURL, '.git') :
         'repoURL must be %s<repository> without a .git suffix, got %s' % [githubOrg, repoURL];
  local name = std.substr(repoURL, std.length(githubOrg), std.length(repoURL));
  local edge = 'abcdefghijklmnopqrstuvwxyz0123456789';
  assert name != '' && std.all([std.member(edge + '-', c) for c in std.stringChars(name)])
         && std.member(edge, name[0]) && std.member(edge, name[std.length(name) - 1]) :
         'the repository name in repoURL must use lowercase letters, digits and dashes, got %s' % name;
  assert std.length(name) <= 47 : 'the repository name in repoURL must be at most 47 characters, got %s' % name;
  name;

// The namespaces frontier-<name> lets its Applications deploy to.
local namespacesOf(name) = ['frontier-%s-%s' % [name, env] for env in ['dev', 'prod']];

// The kinds frontier-app-base's `preview` renders, by API group. Preview manifests
// come from unreviewed pull request heads, so anything else, such as an
// ExternalSecret, SecretStore, OnePasswordItem, Config Connector resource or
// MongoDatabase, must fail at sync rather than reach another namespace's data.
local previewKinds = {
  '': ['ConfigMap', 'PersistentVolumeClaim', 'Service', 'ServiceAccount'],
  apps: ['Deployment'],
  batch: ['CronJob'],
  'networking.istio.io': ['VirtualService'],
  policy: ['PodDisruptionBudget'],
  'rbac.authorization.k8s.io': ['RoleBinding'],
  'security.istio.io': ['AuthorizationPolicy', 'PeerAuthentication', 'RequestAuthentication'],
  'serving.knative.dev': ['Service'],
};

// The kinds frontier-app-base's `previewAccess` renders, by API group.
local previewAccessKinds = {
  '': ['ServiceAccount'],
  'external-secrets.io': ['ExternalSecret', 'SecretStore'],
  'iam.cnrm.cloud.google.com': ['IAMPolicyMember'],
  'rbac.authorization.k8s.io': ['Role', 'RoleBinding'],
};

// An Application in `project` that deploys `path` in `repoURL`, at `targetRevision`,
// to `namespace` in the cluster ArgoCD runs in.
//
// With autoSync (the default) it syncs whenever the resolved revision changes,
// without anyone pressing Sync. prune deletes resources the source no longer
// renders, and selfHeal reverts changes made to the live resources outside git. An
// empty render is never synced (allowEmpty defaults to false), so a broken source
// can't prune the whole app. With autoSync=false the Application only syncs when
// someone presses Sync (or runs `argocd app sync`).
//
// It isn't exported: an app's project only allows the app's own repository and
// namespaces, which `newFrontierApp` works out from repoURL.
local newApplication(name, namespace, project, repoURL, path, targetRevision, autoSync) =
  application.new(name)
  + application.metadata.withNamespace('argocd')
  // Deleting the Application (e.g. when its app is removed from frontier-app-registry)
  // deletes the resources it deployed instead of leaving them running.
  + application.metadata.withFinalizers(['resources-finalizer.argocd.argoproj.io'])
  + application.spec.withProject(project)
  + source.withRepoURL(repoURL)
  + source.withTargetRevision(targetRevision)
  + source.withPath(path)
  + application.spec.destination.withServer('https://kubernetes.default.svc')
  + application.spec.destination.withNamespace(namespace)
  + (
    if autoSync then
      application.spec.syncPolicy.automated.withPrune(true)
      + application.spec.syncPolicy.automated.withSelfHeal(true)
    else {}
  )
  + application.spec.syncPolicy.withSyncOptions(['CreateNamespace=true']);

{
  // The argo-cd-libsonnet Application builders, for patching what `newFrontierApp`
  // returns, e.g.
  //   argocd.newFrontierApp(...) + argocd.application.metadata.withLabels({ team: 'x' })
  application:: application,

  // The Application for environment `env` of a repo built from
  // persona-template-frontier-app. It renders kubernetes/jsonnet/<env>/main.jsonnet,
  // which merges that environment's config.libsonnet over the common one and
  // renders frontier-app-base.
  //
  // `config` is the environment's config.libsonnet. The Application's name and
  // destination namespace come from it (releaseName, falling back to appName the way
  // frontier-app-base does, and namespace), so the resources ArgoCD renders and the
  // Application tracking them can't drift apart. autoSync (the default) syncs whenever
  // the resolved revision changes, with prune and selfHeal. With autoSync=false the
  // Application only syncs when someone presses Sync.
  //
  // The Application is in the app's own project, frontier-<repository> (see
  // `newProject`), so the namespace has to be frontier-<repository>-dev or
  // frontier-<repository>-prod. Anything else fails here rather than at sync.
  newFrontierApp(env, config, repoURL, targetRevision, autoSync=true)::
    local releaseName = std.get(config, 'releaseName', '');
    local name = if releaseName != '' then releaseName else std.get(config, 'appName', '');
    assert name != '' : 'config needs a releaseName or appName; it names the Application';
    assert std.get(config, 'namespace', '') != '' : "config needs a namespace; it is the Application's destination";
    assert targetRevision != '' : 'targetRevision is required';
    local appName = appNameOf(repoURL);
    local namespaces = namespacesOf(appName);
    assert std.member(namespaces, config.namespace) :
           "config's namespace must be %s or %s, the namespaces project frontier-%s allows, got %s"
           % (namespaces + [appName, config.namespace]);

    newApplication(name, config.namespace, 'frontier-' + appName, repoURL, 'kubernetes/jsonnet/' + env, targetRevision, autoSync)
    // Only the entrypoint. ArgoCD would otherwise also render any .json/.yaml file
    // that lands in this directory.
    + source.directory.withInclude('main.jsonnet')
    // ArgoCD does not run `jb install`, so frontier-app-base and its dependencies are
    // committed under kubernetes/jsonnet/vendor. Relative to the repository root.
    + source.directory.jsonnet.withLibs(['kubernetes/jsonnet/vendor'])
    // ArgoCD substitutes $ARGOCD_APP_REVISION with the commit sha targetRevision
    // resolved to, which the image has to be pushed under.
    + source.directory.jsonnet.withTlas([{ name: 'imageTag', value: '$ARGOCD_APP_REVISION' }]),

  // The AppProject for the app registered in frontier-app-registry with `repoURL`,
  // named frontier-<repository>. It only lets the app's Applications deploy that
  // repository, to its own frontier-<repository>-dev and frontier-<repository>-prod
  // namespaces, so one app can't write to another's. It allows any namespaced kind
  // and, of cluster-scoped kinds, only Namespace, which frontier-app-base renders.
  //
  // An app repository can't be trusted with its own project, so this is for the
  // platform to apply from the registry, never from an app's kubernetes/deploy.
  newProject(repoURL)::
    local name = appNameOf(repoURL);

    appProject.new('frontier-' + name)
    + appProject.metadata.withNamespace('argocd')
    + appProject.spec.withDescription('Frontier app %s, registered in frontier-app-registry' % name)
    + appProject.spec.withSourceRepos([repoURL])
    + appProject.spec.withDestinations([
      appProject.spec.destinations.withServer('https://kubernetes.default.svc')
      + appProject.spec.destinations.withNamespace(namespace)
      for namespace in namespacesOf(name)
    ])
    + appProject.spec.withClusterResourceWhitelist(
      appProject.spec.clusterResourceWhitelist.withGroup('')
      + appProject.spec.clusterResourceWhitelist.withKind('Namespace')
    ),

  // The namespace pull request `prNumber`'s preview environment of the app with
  // `repoURL` deploys to, the one frontier-app-base's `preview` renders into.
  previewNamespace(repoURL, prNumber)::
    local pr = std.toString(prNumber);
    assert pr != '' && pr[0] != '0' && std.all([std.member('0123456789', c) for c in std.stringChars(pr)]) :
           'prNumber must be a positive integer, got "%s"' % pr;
    'frontier-%s-dev-pr-%s' % [appNameOf(repoURL), pr],

  // The AppProject for the pull request preview environments of the app registered in
  // frontier-app-registry with `repoURL`, named preview-frontier-<repository> so it
  // can't collide with any app's frontier-<repository>. It only lets them deploy that
  // repository to frontier-<repository>-dev-pr-* namespaces, and only the kinds
  // frontier-app-base's `preview` renders. Like `newProject`, it is for the platform to
  // apply from the registry, never from an app's repository.
  newPreviewProject(repoURL)::
    local name = appNameOf(repoURL);

    appProject.new('preview-frontier-' + name)
    + appProject.metadata.withNamespace('argocd')
    + appProject.spec.withDescription('Pull request preview environments of Frontier app %s, registered in frontier-app-registry' % name)
    + appProject.spec.withSourceRepos([repoURL])
    + appProject.spec.withDestinations([
      appProject.spec.destinations.withServer('https://kubernetes.default.svc')
      + appProject.spec.destinations.withNamespace('frontier-%s-dev-pr-*' % name),
    ])
    + appProject.spec.withClusterResourceWhitelist(
      appProject.spec.clusterResourceWhitelist.withGroup('')
      + appProject.spec.clusterResourceWhitelist.withKind('Namespace')
    )
    + appProject.spec.withNamespaceResourceWhitelist([
      appProject.spec.namespaceResourceWhitelist.withGroup(group)
      + appProject.spec.namespaceResourceWhitelist.withKind(kind)
      for group in std.objectFields(previewKinds)
      for kind in previewKinds[group]
    ]),

  // The AppProject for the Applications that give `repoURL`'s pull request previews
  // dev's Secrets and buckets. Their Role and RoleBinding go in the dev namespace.
  newPreviewAccessProject(repoURL)::
    local name = appNameOf(repoURL);

    appProject.new('preview-access-frontier-' + name)
    + appProject.metadata.withNamespace('argocd')
    + appProject.spec.withDescription('Dev Secrets and buckets for the pull request preview environments of Frontier app %s, registered in frontier-app-registry' % name)
    + appProject.spec.withSourceRepos([repoURL])
    + appProject.spec.withDestinations([
      appProject.spec.destinations.withServer('https://kubernetes.default.svc')
      + appProject.spec.destinations.withNamespace(namespace)
      for namespace in ['frontier-%s-dev' % name, 'frontier-%s-dev-pr-*' % name]
    ])
    + appProject.spec.withClusterResourceWhitelist(
      appProject.spec.clusterResourceWhitelist.withGroup('')
      + appProject.spec.clusterResourceWhitelist.withKind('Namespace')
    )
    + appProject.spec.withNamespaceResourceWhitelist([
      appProject.spec.namespaceResourceWhitelist.withGroup(group)
      + appProject.spec.namespaceResourceWhitelist.withKind(kind)
      for group in std.objectFields(previewAccessKinds)
      for kind in previewAccessKinds[group]
    ]),
}
