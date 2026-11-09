#!/usr/bin/env bash
# Best-effort check that a job holding `id-token: write` does not run dependency code on the host.
#
# A job with id-token: write has ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN in
# every step's environment, so any code it runs (a test, a build, a package's lifecycle script) can
# mint a new OIDC assertion and trade it at the package proxy, whatever the job did with the token it
# already had. Only the install job holds id-token here. It installs with lifecycle scripts off and
# runs nothing else from the repository's packages; the jobs that run them have no id-token.
#
# What it checks, in a job that holds id-token (its own `permissions:` wins; without one the
# workflow's applies):
#   - run lines: flags a command word from a list of package managers, runtimes, test runners and
#     build tools (npm, yarn, node, python, make, bash, ...), `docker run|exec|compose`, and any
#     `./path` or `.sh` word; the install with lifecycle scripts off and prose in an echo pass;
#   - uses: flags any action outside a short allowlist (checkout, setup-node, upload-artifact, the
#     proxy auth, docker build actions, ./.github/actions/build-image) and any reusable workflow.
# It is a tripwire for accidents, not a sandbox: a same-repo author can edit it, and a command it
# does not know can still run code. It fails closed: a workflow it cannot read is an error.
#
# Deliberate exception: `docker build` is not flagged. An image job keeps id-token because the package
# installs run inside the build, whose RUN steps do not get the runner's environment (so no
# ACTIONS_ID_TOKEN_REQUEST_*); the proxy token reaches only the install RUN, as a secret mount, with
# lifecycle scripts off. A malicious Dockerfile edit by a committer can still read that mount.
#
# Allow-list: .github/scripts/check-workflow-permissions.allow (override with ALLOW_FILE), one exact
# `workflow-file:job-id` per line, `#` comments. No wildcards: the line is compared as a whole string.
# It exempts a job that holds id-token for its own purpose, which someone should review. Empty by
# default.
#
# Usage: check-workflow-permissions.sh [workflows-dir]   (needs yq v4 and jq, on ubuntu-latest)
set -euo pipefail

dir=${1:-.github/workflows}
shopt -s nullglob
files=("$dir"/*.yaml "$dir"/*.yml)

allow_file=${ALLOW_FILE:-$(dirname "$0")/check-workflow-permissions.allow}
allowed=()
if [ -f "$allow_file" ]; then
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry=${entry%%#*}
    entry=${entry#"${entry%%[![:space:]]*}"}
    entry=${entry%"${entry##*[![:space:]]}"}
    [ -n "$entry" ] && allowed+=("$entry")
  done < "$allow_file"
fi

# 0 when workflow-file:job is listed exactly (a plain string comparison, so no pattern matches).
is_allowed() {
  local entry
  for entry in "${allowed[@]+"${allowed[@]}"}"; do
    [ "$entry" = "$1" ] && return 0
  done
  return 1
}

# One row per step of each job that holds id-token: job, kind (run, uses or calls), text.
rows='
def holds(p): (p | type) as $t | ($t == "object" and p["id-token"] == "write") or p == "write-all";
. as $wf
| (.jobs // {}) | to_entries[]
| select(holds(.value.permissions // $wf.permissions))
| .key as $job
| if (.value.uses // null) != null then [$job, "calls", .value.uses] | join("\t")
  else
    (.value.steps // [])[]
    | ((.run // "") | tostring | split("\n") | map(select(test("^[[:space:]]*#") | not)) | .[] | [$job, "run", .]),
      (select((.uses // null) != null) | [$job, "uses", .uses])
    | join("\t")
  end
'

# Words that run code from the repository or its packages.
commands='^(npm|npm-ci|npx|yarn|pnpm|bun|bunx|node|tsx|tsc|vitest|jest|eslint|prettier|playwright|vite|next|make|bash|sh|zsh|dash|python|python3|pip|pip3|pytest|uv|uvx|poetry|ruby|bundle|bundler|rake|cargo|go|deno|java|mvn|gradle|dotnet|php|composer|perl)$'
separators='[;&|`<>]'
simple_install='^[[:space:]]*(bin/npm-ci|npm ci|yarn install)([[:space:]]+[A-Za-z0-9_./=:@%+-]+)*[[:space:]]*$'
guard_line='^[[:space:]]*bash \.github/scripts/check-workflow-permissions\.sh[[:space:]]*$'
# An action in a job with id-token must be pinned to a full commit sha: a mutable tag could be moved.
allowed_uses='^(actions/checkout|actions/setup-node|actions/upload-artifact|persona-id/package-proxy-auth|docker/setup-buildx-action|docker/login-action|docker/build-push-action)@[0-9a-f]{40}$|^\./\.github/actions/build-image$'

# 0 when the line is an install that cannot run lifecycle scripts: the flag as a whole word, and
# no later word turning scripts back on or changing the mode.
is_safe_install() {
  local line=$1 word safe=1
  local -a words
  [[ $line =~ $simple_install ]] || return 1
  read -ra words <<<"$line"
  for word in "${words[@]}"; do
    case $word in
      --ignore-scripts | --mode=skip-build) safe=0 ;;
      --ignore-scripts=* | --no-ignore-scripts | --mode=*) return 1 ;;
    esac
  done
  return $safe
}

# 0 when the line runs code that could use the OIDC credentials.
runs_dependency_code() {
  local line=$1 word prev= plain
  local -a words
  [[ $line =~ ^[[:space:]]*$ ]] && return 1
  if [[ $line =~ $guard_line ]] || is_safe_install "$line"; then return 1; fi
  # Prose: an echo or printf with no second command in it (an escaped backtick is just text).
  plain=${line//\\\`/}
  if [[ $line =~ ^[[:space:]]*(echo|printf)[[:space:]] && ! $plain =~ $separators && $line != *'$('* ]]; then
    return 1
  fi
  # A path in command position is a program from the repository (bin/tool, scripts/foo, .github/scripts/x),
  # with or without an extension. Quoted strings are dropped first, then the line is split into commands.
  local unquoted segment first
  unquoted=$(sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g' <<<"$line")
  while IFS= read -r segment; do
    segment=${segment#"${segment%%[![:space:]]*}"}
    while [[ $segment =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do segment=${segment#"${BASH_REMATCH[0]}"}; done
    first=${segment%%[[:space:]]*}
    if [[ $first == */* ]]; then return 0; fi
  done < <(sed 's/[;&|`()<>]/\n/g' <<<"$unquoted")
  read -ra words <<<"${line//[;&|()\`<>]/ }"
  for word in "${words[@]}"; do
    if [[ $prev == docker && $word =~ ^(run|exec|compose|create|start)$ ]]; then return 0; fi
    prev=$word
    # A repository script run by path: ./x, or anything ending in .sh.
    if [[ $word == ./* || $word == *.sh ]]; then return 0; fi
    word=${word##*/}
    if [[ $word =~ $commands ]]; then return 0; fi
  done
  return 1
}

failed=0
noticed=
for file in "${files[@]}"; do
  # Captured first: a failure inside a process substitution would be lost and the check would pass.
  if ! found=$(yq -o=json '.' "$file" | jq -r "$rows"); then
    echo "::error file=$file::could not parse this workflow, so it was not checked"
    failed=1
    continue
  fi
  while IFS=$'\t' read -r job kind text; do
    [ -n "$kind" ] || continue
    if is_allowed "$(basename "$file"):$job"; then
      case $noticed in *"|$file:$job|"*) ;; *)
        echo "::warning file=$file::job '$job' is on the allow-list ($(basename "$allow_file")) and was not checked"
        noticed="$noticed|$file:$job|" ;;
      esac
      continue
    fi
    case $kind in
      calls)
        echo "::error file=$file::job '$job' holds id-token: write and calls the reusable workflow $text, which this check cannot inspect"
        failed=1
        ;;
      uses)
        if [[ ! $text =~ $allowed_uses ]]; then
          echo "::error file=$file::job '$job' holds id-token: write and uses $text, which is not on the allowlist (checkout, setup-node, upload-artifact, package-proxy-auth, docker build actions, build-image)"
          failed=1
        fi
        ;;
      *)
        if runs_dependency_code "$text"; then
          echo "::error file=$file::job '$job' holds id-token: write and runs dependency code: $text"
          failed=1
        fi
        ;;
    esac
  done <<<"$found"
done

if [ "$failed" -ne 0 ]; then
  echo "A job with id-token: write must not run dependency code. Move the step to a job without id-token (see the install job in ci.yaml)." >&2
  exit 1
fi
echo "No job that holds id-token: write runs dependency code."
