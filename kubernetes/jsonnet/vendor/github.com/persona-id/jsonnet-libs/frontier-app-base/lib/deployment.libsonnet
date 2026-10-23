// Deployments: background workers, and each Valkey instance.
local h = import 'helpers.libsonnet';
local k = (import 'libs.libsonnet').k;

local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

{
  // A Valkey instance; see `valkeyInstances` in helpers.libsonnet.
  //
  // Without the instance's own `computeClass`, no nodeSelector or toleration,
  // deliberately: the pod owns a pd-balanced disk, compute-class nodes are
  // hyperdisk-only, and a disk cannot change zone. Omitting the toleration lets the
  // class taint keep the pod on the untainted pool, where its disk can attach. Only
  // the job queue takes a class, `jobQueue.computeClass`, which also moves it to a
  // Hyperdisk claim. It never takes the app's `tolerations`.
  valkey(cfg, instance)::
    local selector = h.valkeySelector(cfg, instance);
    local placement = h.placement(cfg { tolerations: [] }, instance.computeClass);

    deployment.new(instance.name, replicas=1, containers=[
      container.new(instance.name, '%s:%s' % [instance.image.repository, instance.image.tag])
      + container.livenessProbe.exec.withCommand(['sh', '-c', 'valkey-cli ping'])
      + container.resources.withLimits(instance.resources.limits)
      + container.resources.withRequests(instance.resources.requests)
      + container.securityContext.capabilities.withDrop(['ALL'])
      + container.securityContext.withAllowPrivilegeEscalation(false)
      + container.securityContext.withReadOnlyRootFilesystem(true)
      + container.startupProbe.exec.withCommand(['sh', '-c', 'valkey-cli ping'])
      + container.withArgs(['/etc/valkey/valkey.conf'])
      + container.withCommand(['valkey-server'])
      + container.withImagePullPolicy('IfNotPresent')
      + container.withPorts([k.core.v1.containerPort.newNamed(h.valkeyPort, 'tcp') + k.core.v1.containerPort.withProtocol('TCP')])
      + container.withVolumeMounts([
        volumeMount.new('data', '/data'),
        volumeMount.new('config', '/etc/valkey', readOnly=true),
      ]),
    ])
    + deployment.metadata.withLabels(h.valkeyLabels(cfg, instance))
    + deployment.spec.selector.withMatchLabels(selector)
    + deployment.spec.strategy.withType(instance.strategy)
    // Restarts the pod when the config changes; valkey reads its config once at boot.
    + deployment.spec.template.metadata.withAnnotations({ 'checksum/config': std.substr(std.md5(instance.conf), 0, 16) })
    + deployment.spec.template.metadata.withLabels(selector)
    + (if placement.nodeSelector != {} then deployment.spec.template.spec.withNodeSelector(placement.nodeSelector) else {})
    + (if instance.priorityClassName != '' then deployment.spec.template.spec.withPriorityClassName(instance.priorityClassName) else {})
    + (if placement.tolerations != [] then deployment.spec.template.spec.withTolerations(placement.tolerations) else {})
    + deployment.spec.template.spec.securityContext.seccompProfile.withType('RuntimeDefault')
    // fsGroup so the mounted disk is writable by the unprivileged user.
    + deployment.spec.template.spec.securityContext.withFsGroup(1000)
    + deployment.spec.template.spec.securityContext.withRunAsGroup(1000)
    + deployment.spec.template.spec.securityContext.withRunAsNonRoot(true)
    + deployment.spec.template.spec.securityContext.withRunAsUser(1000)
    + deployment.spec.template.spec.withAutomountServiceAccountToken(false)
    + deployment.spec.template.spec.withServiceAccountName(instance.name)
    + deployment.spec.template.spec.withVolumes([
      if instance.storage != null
      then volume.fromPersistentVolumeClaim('data', instance.storage.claimName)
      else volume.fromEmptyDir('data'),
      volume.fromConfigMap('config', '%s-config' % instance.name),
    ]),

  // A long-running process that is not the web service. A Deployment rather than a
  // Knative revision because Knative sizes from request concurrency, which a worker
  // never generates.
  //
  // Runs as the `app` ServiceAccount — the only identity the backing services'
  // AuthorizationPolicies accept — and takes the app's env, secrets and mounts.
  worker(cfg, worker)::
    local name = h.normalize(worker.name);
    local placement = h.workloadPlacement(cfg, worker);
    local singleInstance = h.get(worker, 'singleInstance', false);
    local volumes = h.podVolumes(cfg);
    local source = h.sourceAnnotations(cfg);
    local podAnnotations = h.sourceAnnotations(cfg, h.get(worker, 'annotations', {}));

    deployment.new(
      name,
      replicas=if singleInstance then 1 else h.get(worker, 'replicas', 1),
      containers=[
        // Always named `worker`, so a Datadog log annotation key is predictable.
        h.workloadContainer(cfg, 'worker', worker)
        + (if std.objectHas(worker, 'livenessProbe') then { livenessProbe: worker.livenessProbe } else {})
        + (if std.objectHas(worker, 'readinessProbe') then { readinessProbe: worker.readinessProbe } else {}),
      ],
    )
    + (if source != {} then deployment.metadata.withAnnotations(source) else {})
    + deployment.metadata.withLabels(h.labels(cfg) {
      'app.kubernetes.io/component': 'worker',
      'frontier.withpersona.com/workload': name,
    })
    + deployment.spec.selector.withMatchLabels({ 'frontier.withpersona.com/workload': name })
    // Recreate keeps a redeploy from briefly running two copies of a worker that
    // must be a singleton.
    + (if singleInstance then deployment.spec.strategy.withType('Recreate') else {})
    + (if podAnnotations != {} then deployment.spec.template.metadata.withAnnotations(podAnnotations) else {})
    + deployment.spec.template.metadata.withLabels(h.workloadLabels(cfg, worker, 'worker', name))
    + (if placement.nodeSelector != {} then deployment.spec.template.spec.withNodeSelector(placement.nodeSelector) else {})
    + (if cfg.mysql.enabled then { spec+: { template+: { spec+: { initContainers: [h.mysqlProxyContainer(cfg, nativeSidecar=true)] } } } } else {})
    + deployment.spec.template.spec.withServiceAccountName('app')
    // Time a worker gets to finish the job in hand after SIGTERM.
    + deployment.spec.template.spec.withTerminationGracePeriodSeconds(h.get(worker, 'terminationGracePeriodSeconds', 30))
    + (if placement.tolerations != [] then deployment.spec.template.spec.withTolerations(placement.tolerations) else {})
    + (if volumes != [] then deployment.spec.template.spec.withVolumes(volumes) else {}),
}
