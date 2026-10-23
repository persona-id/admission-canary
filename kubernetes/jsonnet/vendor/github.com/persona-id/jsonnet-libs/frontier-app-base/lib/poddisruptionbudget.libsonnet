// PodDisruptionBudgets: one app pod evicted at a time.
local h = import 'helpers.libsonnet';
local k = (import 'libs.libsonnet').k;

local podDisruptionBudget = k.policy.v1.podDisruptionBudget;

{
  // One pod at a time, never a fixed count to keep: during a rollout or a
  // scale-down a fixed count can exceed the pods that exist and block drains.
  app(cfg)::
    podDisruptionBudget.new('app')
    + podDisruptionBudget.metadata.withLabels(h.labels(cfg))
    + podDisruptionBudget.spec.withMaxUnavailable(1)
    // Every revision's pods carry this, so the budget follows rollouts.
    + podDisruptionBudget.spec.selector.withMatchLabels({ 'serving.knative.dev/service': 'app' }),
}
