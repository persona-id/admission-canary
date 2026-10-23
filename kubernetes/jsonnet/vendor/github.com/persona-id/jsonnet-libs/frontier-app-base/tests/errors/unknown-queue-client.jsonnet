// expect: is not one of sidekiq, bullmq and asynq
local frontier = import '../../main.libsonnet';

frontier.toList(frontier.new({ appName: 'demo', namespace: 'demo-dev', permissions: { owner: 'owner' } } + { jobQueue: { enabled: true, client: 'celery' } }))
