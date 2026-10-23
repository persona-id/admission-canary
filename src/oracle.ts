// "Build in Oracle": the same button and prompt the Frontier UI shows on an
// app's page. Copied from persona-frontier-ui
// src/client/components/frontierLinks.ts; keep the prompt text identical so a
// chat started here behaves like one started from Frontier.

/**
 * Max length of the change description typed into the Build in Oracle form.
 * Keeps the encoded `?prompt=` URL well under common URL-length limits while
 * still leaving room for a detailed brief.
 */
export const ORACLE_CHANGE_MAX_LENGTH = 2000;

/** Placeholder used in the prompt when no description is given. */
export const ORACLE_CHANGE_PLACEHOLDER = '<describe what you want built>';

/**
 * Normalise a typed change description for the prompt: CRLF/CR to LF, drop
 * blank lines and whitespace at the very start and end, and cap it at
 * ORACLE_CHANGE_MAX_LENGTH UTF-16 code units. Line breaks inside are kept as
 * typed. The cap never splits a surrogate pair: a lone surrogate would make
 * encodeURIComponent throw, so an emoji straddling the cap is dropped whole.
 */
export function normalizeOracleChange(change: string): string {
  return change
    .replace(/\r\n?/g, '\n')
    .trim()
    .slice(0, ORACLE_CHANGE_MAX_LENGTH)
    .replace(/[\uD800-\uDBFF]$/, '')
    .trimEnd();
}

/**
 * Prompt seeded into a new Oracle chat: dispatch an Editor session on the repo
 * and monitor it to green. The description goes on its own lines under
 * `Change:`, with a blank line on either side, so Oracle's composer (which
 * reads the prompt as markdown) keeps it as a separate block with its own
 * line breaks rather than running it into the label.
 */
export function oracleBuildPrompt(slug: string, change = ''): string {
  const described = normalizeOracleChange(change);
  return [
    `Dispatch an Oracle Editor session on ${slug} (https://github.com/${slug}) to make the change below, and open a PR.`,
    '',
    'Change:',
    described || ORACLE_CHANGE_PLACEHOLDER,
    '',
    'Then monitor the session and PR yourself. Do not ask me to check in. Fix failures and re-dispatch as needed until:',
    '- both required status checks, build and test, are green, and',
    '- all agentic review is passing (the Oracle review / change-safety workflow and any AI reviewer comments) with no unresolved findings.',
    '',
    'Only then report back with the PR link and the final state of each check.',
  ].join('\n');
}

/** `owner/name` for a GitHub repo URL (ignoring a trailing `.git` or slash), or null. */
export function githubRepoSlug(repoUrl: string): string | null {
  return /github\.com\/([\w.-]+\/[\w.-]+?)(?:\.git)?\/?$/.exec(repoUrl)?.[1] ?? null;
}

/**
 * New Oracle chat seeded with the build prompt for the app's GitHub repo, or
 * null for a non-GitHub URL. The description is normalised and capped by
 * normalizeOracleChange; encodeURIComponent keeps its line breaks as %0A.
 */
export function oracleChatUrl(repoUrl: string, change = ''): string | null {
  const slug = githubRepoSlug(repoUrl);
  return slug ? `https://oracle.withpersona.ai/?prompt=${encodeURIComponent(oracleBuildPrompt(slug, change))}` : null;
}

/**
 * Whether the app is internal, and so shows the button. `private` is VPN only
 * and `none` is reachable only from other apps in the cluster; `public` is the
 * open internet, where an Oracle link means nothing to most visitors. Anything
 * else is treated as public, so a typo hides the button rather than showing it.
 */
export function isInternal(visibility: string): boolean {
  return visibility === 'private' || visibility === 'none';
}
