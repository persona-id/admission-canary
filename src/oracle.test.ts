// Mirrors persona-frontier-ui src/client/components/frontierLinks.test.ts, so a
// drift from the Frontier UI's prompt fails here.
import { describe, expect, it } from 'vitest';
import {
  ORACLE_CHANGE_MAX_LENGTH,
  githubRepoSlug,
  isInternal,
  normalizeOracleChange,
  oracleBuildPrompt,
  oracleChatUrl,
} from './oracle.js';

const promptOf = (url: string | null) => {
  const u = new URL(url!);
  expect(u.origin + u.pathname).toBe('https://oracle.withpersona.ai/');
  return u.searchParams.get('prompt')!;
};

describe('oracleChatUrl', () => {
  it('opens a new Oracle chat seeded with the build prompt for the repo', () => {
    const url = oracleChatUrl('https://github.com/persona-id/my-app');
    expect(url).toBe(
      `https://oracle.withpersona.ai/?prompt=${encodeURIComponent(oracleBuildPrompt('persona-id/my-app'))}`
    );
    const prompt = promptOf(url);
    expect(prompt).toContain('https://github.com/persona-id/my-app');
    expect(prompt).toContain('\n\nChange:\n<describe what you want built>\n\n');
    expect(prompt).toContain('Do not ask me to check in');
  });

  it('keeps the Frontier UI prompt text verbatim', () => {
    expect(promptOf(oracleChatUrl('https://github.com/persona-id/my-app', 'x')).split('\n')).toEqual([
      'Dispatch an Oracle Editor session on persona-id/my-app (https://github.com/persona-id/my-app) to make the change below, and open a PR.',
      '',
      'Change:',
      'x',
      '',
      'Then monitor the session and PR yourself. Do not ask me to check in. Fix failures and re-dispatch as needed until:',
      '- both required status checks, build and test, are green, and',
      '- all agentic review is passing (the Oracle review / change-safety workflow and any AI reviewer comments) with no unresolved findings.',
      '',
      'Only then report back with the PR link and the final state of each check.',
    ]);
  });

  it('keeps every line break of a multi-line description, encoded as %0A', () => {
    const change = 'Add a settings page.\r\nIt needs a dark mode toggle.\r\n\r\n\r\n- persist it\n- default to system';
    const url = oracleChatUrl('https://github.com/persona-id/my-app', change)!;
    expect(url).not.toContain('%0D');
    expect(url).toContain('Add%20a%20settings%20page.%0AIt%20needs');
    expect(promptOf(url)).toContain(
      '\n\nChange:\nAdd a settings page.\nIt needs a dark mode toggle.\n\n\n- persist it\n- default to system\n\nThen monitor'
    );
  });

  it('caps the description at ORACLE_CHANGE_MAX_LENGTH characters', () => {
    expect(ORACLE_CHANGE_MAX_LENGTH).toBe(2000);
    const long = 'a'.repeat(ORACLE_CHANGE_MAX_LENGTH) + 'OVERFLOW';
    const prompt = promptOf(oracleChatUrl('https://github.com/persona-id/my-app', long));
    expect(prompt).toContain(`Change:\n${'a'.repeat(ORACLE_CHANGE_MAX_LENGTH)}\n\n`);
    expect(prompt).not.toContain('OVERFLOW');
  });

  it('keeps the placeholder when the description is blank', () => {
    expect(promptOf(oracleChatUrl('https://github.com/persona-id/my-app', ' \r\n  '))).toContain(
      'Change:\n<describe what you want built>\n'
    );
  });

  it('returns null for a non-GitHub URL', () => {
    expect(oracleChatUrl('https://gitlab.com/persona-id/my-app')).toBeNull();
    expect(oracleChatUrl('')).toBeNull();
  });

  it('has no em-dashes in the prompt', () => {
    expect(oracleBuildPrompt('persona-id/my-app')).not.toMatch(/\u2014/);
  });
});

describe('normalizeOracleChange', () => {
  it('converts CRLF, trims the ends and keeps inner breaks', () => {
    expect(normalizeOracleChange('\r\n  one\r\ntwo\rthree\n\n  \n')).toBe('one\ntwo\nthree');
  });

  it('drops an emoji that straddles the cap rather than splitting its surrogate pair', () => {
    const change = `${'a'.repeat(ORACLE_CHANGE_MAX_LENGTH - 1)}\u{1F600}`;
    const out = normalizeOracleChange(change);
    expect(out).toBe('a'.repeat(ORACLE_CHANGE_MAX_LENGTH - 1));
    expect(() => encodeURIComponent(out)).not.toThrow();
    expect(() => oracleChatUrl('https://github.com/persona-id/my-app', change)).not.toThrow();
  });

  it('keeps an emoji that ends exactly at the cap', () => {
    const change = `${'a'.repeat(ORACLE_CHANGE_MAX_LENGTH - 2)}\u{1F600}tail`;
    const out = normalizeOracleChange(change);
    expect(out).toBe(`${'a'.repeat(ORACLE_CHANGE_MAX_LENGTH - 2)}\u{1F600}`);
    expect(out).toHaveLength(ORACLE_CHANGE_MAX_LENGTH);
    expect(() => encodeURIComponent(out)).not.toThrow();
  });
});

describe('githubRepoSlug', () => {
  it('extracts owner/name or null', () => {
    expect(githubRepoSlug('https://github.com/persona-id/my-app.git')).toBe('persona-id/my-app');
    expect(githubRepoSlug('https://github.com/persona-id/my-app/')).toBe('persona-id/my-app');
    expect(githubRepoSlug('https://gitlab.com/persona-id/my-app')).toBeNull();
  });
});

describe('isInternal', () => {
  it('is true for private and none', () => {
    expect(isInternal('private')).toBe(true);
    expect(isInternal('none')).toBe(true);
  });

  it('is false for public and anything unrecognised', () => {
    expect(isInternal('public')).toBe(false);
    expect(isInternal('')).toBe(false);
    expect(isInternal('Private')).toBe(false);
  });
});
