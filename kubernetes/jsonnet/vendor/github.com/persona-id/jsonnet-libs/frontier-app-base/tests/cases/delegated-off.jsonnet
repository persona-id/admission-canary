// Without the opt-in nothing changes: the forge.jsonnet config with an explicit
// empty delegatedCallers renders exactly what it renders by default, so this
// golden file equals forge.json.
local frontier = import '../../main.libsonnet';

local config = {
  appName: 'demo',
  namespace: 'demo-prod',
  permissions: { owner: 'owner' },
  releaseName: 'rel',
  image: { repository: 'r', tag: 't' },
  routes: [
    { paths: ['/mcp/*'], humans: 'none', principals: ['forge/oracle', 'forge/oracle', 'forge/other-app'] },
    { paths: ['/admin/*'], humans: 'okta', groups: ['Role-Security'], emails: ['a@withpersona.com'] },
    { paths: ['/*'], humans: 'anyone', principals: ['forge/oracle'] },
  ],
};
local default = frontier.toList(frontier.new(config));
local empty = frontier.toList(frontier.new(config { delegatedCallers: [] }));

assert default == empty : 'delegatedCallers: [] must render exactly like the default';
empty
