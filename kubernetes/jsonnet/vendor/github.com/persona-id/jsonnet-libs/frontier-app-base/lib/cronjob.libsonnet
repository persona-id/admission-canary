// CronJobs: background work that runs on a schedule and exits.
local h = import 'helpers.libsonnet';
local cronJob = (import 'libs.libsonnet').k.batch.v1.cronJob;

{
  // Needs no sidecar opt-out: istio runs as a native sidecar here, so it stops when
  // the job's container does.
  //
  // Runs as the `app` ServiceAccount — the only identity the backing services'
  // AuthorizationPolicies accept — and takes the app's env, secrets and mounts.
  scheduled(cfg, job)::
    local name = h.normalize(job.name);
    local placement = h.workloadPlacement(cfg, job);
    local volumes = h.podVolumes(cfg);
    local jobLabels = h.labels(cfg) {
      'app.kubernetes.io/component': 'scheduled-job',
      'frontier.withpersona.com/workload': name,
    };
    local source = h.sourceAnnotations(cfg);
    local podAnnotations = h.sourceAnnotations(cfg, h.get(job, 'annotations', {}));
    local optional(field, fn) = if h.get(job, field, null) != null then fn(job[field]) else {};

    assert h.get(job, 'schedule', '') != '' : 'scheduled job "%s" needs a schedule' % name;

    cronJob.new(name, job.schedule, [h.workloadContainer(cfg, 'job', job)])
    + (if source != {} then cronJob.metadata.withAnnotations(source) else {})
    + cronJob.metadata.withLabels(jobLabels)
    + (if source != {} then cronJob.spec.jobTemplate.metadata.withAnnotations(source) else {})
    + cronJob.spec.jobTemplate.metadata.withLabels(jobLabels)
    + (if podAnnotations != {} then cronJob.spec.jobTemplate.spec.template.metadata.withAnnotations(podAnnotations) else {})
    + cronJob.spec.jobTemplate.spec.template.metadata.withLabels(h.workloadLabels(cfg, job, 'scheduled-job', name))
    + (if placement.nodeSelector != {} then cronJob.spec.jobTemplate.spec.template.spec.withNodeSelector(placement.nodeSelector) else {})
    + (if cfg.mysql.enabled then { spec+: { jobTemplate+: { spec+: { template+: { spec+: { initContainers: [h.mysqlProxyContainer(cfg, nativeSidecar=true)] } } } } } } else {})
    // Each attempt is its own pod, so a failed run keeps its logs.
    + cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('Never')
    + cronJob.spec.jobTemplate.spec.template.spec.withServiceAccountName('app')
    + (if placement.tolerations != [] then cronJob.spec.jobTemplate.spec.template.spec.withTolerations(placement.tolerations) else {})
    + (if volumes != [] then cronJob.spec.jobTemplate.spec.template.spec.withVolumes(volumes) else {})
    + optional('activeDeadlineSeconds', cronJob.spec.jobTemplate.spec.withActiveDeadlineSeconds)
    + cronJob.spec.jobTemplate.spec.withBackoffLimit(h.get(job, 'backoffLimit', 3))
    // History limits cap how many finished Jobs are kept; this caps how old.
    + optional('ttlSecondsAfterFinished', cronJob.spec.jobTemplate.spec.withTtlSecondsAfterFinished)
    // Forbid skips a run rather than stacking a second copy on top of one still working.
    + cronJob.spec.withConcurrencyPolicy(h.get(job, 'concurrencyPolicy', 'Forbid'))
    + cronJob.spec.withFailedJobsHistoryLimit(h.get(job, 'failedJobsHistoryLimit', 1))
    + optional('startingDeadlineSeconds', cronJob.spec.withStartingDeadlineSeconds)
    + cronJob.spec.withSuccessfulJobsHistoryLimit(h.get(job, 'successfulJobsHistoryLimit', 3))
    + cronJob.spec.withSuspend(h.get(job, 'suspend', false))
    + optional('timeZone', cronJob.spec.withTimeZone),
}
