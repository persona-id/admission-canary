# frontier-argocd-application

The ArgoCD `Application` an app on Frontier is deployed by, built with
[argo-cd-libsonnet](https://github.com/jsonnet-libs/argo-cd-libsonnet). Every
Application it returns:

- lives in the `argocd` namespace, in the app's own `frontier-<repository>` project
- deploys to the cluster ArgoCD runs in (`https://kubernetes.default.svc`)
- syncs automatically with `prune` and `selfHeal`, unless `autoSync=false`
- creates its destination namespace (`CreateNamespace=true`)
- deletes the resources it deployed when it is deleted (the
  `resources-finalizer.argocd.argoproj.io` finalizer), so removing an app from
  frontier-app-registry tears its environments down

It also builds the `AppProject` for one registered app (see
[An app's AppProject](#an-apps-appproject)).

## Install

```sh
jb install github.com/persona-id/jsonnet-libs/frontier-argocd-application@main
```

jb pulls in argo-cd-libsonnet and doc-util. They rely on jb's `legacyImports` (the
default), which provides the `doc-util` import path.

argo-cd-libsonnet is generated per ArgoCD minor version, and its newest is 3.2. The
`Application` API (`argoproj.io/v1alpha1`) it builds is the one ArgoCD 3.4 serves.

## Usage

### A repo built from persona-template-frontier-app

`newFrontierApp(env, config, repoURL, targetRevision)` is the Application for one
environment of a repo built from the template:

- It renders `kubernetes/jsonnet/<env>/main.jsonnet`, and only that file.
- Its jsonnet library path is `kubernetes/jsonnet/vendor`, where frontier-app-base
  is committed, because ArgoCD does not run `jb install`.
- It passes the `imageTag` top-level argument as `$ARGOCD_APP_REVISION`, the commit
  sha `targetRevision` resolved to.

`config` is the environment's `config.libsonnet`. The Application is named after its
`releaseName`, or `appName` when that is unset, and deploys to its `namespace`.

The Application is in the app's own project, `frontier-<repository>`, which the
platform creates when the app is registered in
[frontier-app-registry](https://github.com/persona-id/frontier-app-registry) (see
[An app's AppProject](#an-apps-appproject)). That project only allows the
`frontier-<repository>-dev` and `frontier-<repository>-prod` namespaces, so any other
`namespace` fails to render. `repoURL` has to follow the same rules as for
`newProject`.

```jsonnet
local argocd = import 'github.com/persona-id/jsonnet-libs/frontier-argocd-application/main.libsonnet';

argocd.newFrontierApp(
  'production',
  import '../jsonnet/production/config.libsonnet',
  'https://github.com/persona-id/my-app',
  '>=0.0.0',  // the highest release tag
)
```

If the template's layout changes, `newFrontierApp` has to change with it.

It also takes `autoSync=false`, which leaves out `syncPolicy.automated`. The
Application then shows as OutOfSync when the source changes, and only syncs when
someone presses Sync or runs `argocd app sync`.

To set anything else, patch the result with the argo-cd-libsonnet builders,
re-exported as `application`:

```jsonnet
argocd.newFrontierApp(...)
+ argocd.application.metadata.withLabels({ team: 'my-team' })
```

There's no function for an Application from any other source. An app's project only
allows the app's own repository, so an Application deploying anything else, such
as a chart from a Helm repository, could never sync.

### An app's AppProject

`newProject(repoURL)` is the `AppProject` for the app registered in
[frontier-app-registry](https://github.com/persona-id/frontier-app-registry) with
`repoURL`. It is named `frontier-<repository>` and:

- allows only `repoURL` as a source
- allows only the `frontier-<repository>-dev` and `frontier-<repository>-prod`
  namespaces as destinations, so one app can't deploy into another's
- allows any namespaced kind, and `Namespace` as the only cluster-scoped kind

```jsonnet
argocd.newProject('https://github.com/persona-id/my-app')
```

The repository name follows the registry's rules for a file name: lowercase
letters, digits and dashes, at most 47 characters. Anything else fails to render.

Apply it from somewhere the platform controls, never from an app's
`kubernetes/deploy`. An app that renders its own project can loosen it.
`newFrontierApp` puts Applications in this project.

## Tests

`tests/run.sh` renders each `tests/cases/*.jsonnet` and compares it with the `.json`
next to it, and checks each `tests/errors/*.jsonnet` fails with the message on its
`// expect:` line. Run `jb install` first, or `make test` from the repository root.
Rerun with `UPDATE=1` to rewrite the `.json` files after an intended change.
