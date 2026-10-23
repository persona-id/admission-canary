"""Source helper contracts; no cluster, Docker or third-party packages needed."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/source-provenance"


class SourceProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        (self.repo / "app.txt").write_text("initial\n")
        (self.repo / ".gitignore").write_text("ignored\n")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")

    def git(self, *args):
        env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            env.pop(key, None)
        return subprocess.check_output(["git", *args], cwd=self.repo, env=env, text=True).strip()

    def helper(self, mode, check=True):
        return subprocess.run(["sh", str(HELPER), mode], cwd=self.repo,
                              text=True, capture_output=True, check=check)

    def test_repository_urls_are_canonical_and_credential_free(self):
        for url in ("https://github.com/persona-id/example.git", "git@github.com:persona-id/example.git",
                    "ssh://git@github.com/persona-id/example.git", "https://token@github.com/persona-id/example.git"):
            with self.subTest(url=url):
                self.git("config", "remote.origin.url", url)
                self.assertEqual(self.helper("repository").stdout.strip(), "https://github.com/persona-id/example")

    def test_rewrite_does_not_publish_token(self):
        self.git("config", "remote.origin.url", "https://github.com/persona-id/example.git")
        self.git("config", "url.https://secret@github.com/.insteadOf", "https://github.com/")
        self.assertEqual(self.helper("repository").stdout.strip(), "https://github.com/persona-id/example")

    def test_unsafe_or_unsupported_origins_warn_and_record_empty(self):
        for url in ("https://evil.example/persona-id/example", "https://github.com/persona-id/example?token=secret",
                    "https://github.com/persona-id/example/extra", "https://github.com@evil.example/persona-id/example"):
            with self.subTest(url=url):
                self.git("config", "remote.origin.url", url)
                result = self.helper("repository")
                self.assertEqual(result.stdout.strip(), "")
                self.assertIn("source-provenance:", result.stderr)
                self.assertNotIn(url, result.stderr)

    def test_missing_origin_warns_and_records_empty(self):
        result = self.helper("repository")
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("no origin remote", result.stderr)


    def test_outside_git_checkout_warns_and_records_empty(self):
        with tempfile.TemporaryDirectory() as plain:
            for mode in ("repository", "revision", "dirty"):
                with self.subTest(mode=mode):
                    env = {**os.environ, "GIT_CEILING_DIRECTORIES": str(Path(plain).parent)}
                    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
                        env.pop(key, None)
                    result = subprocess.run(["sh", str(HELPER), mode], cwd=plain, env=env,
                                            text=True, capture_output=True, check=True)
                    self.assertEqual(result.stdout.strip(), "")
                    self.assertIn("source-provenance:", result.stderr)

    def test_unknown_mode_still_fails(self):
        self.assertNotEqual(self.helper("bogus", check=False).returncode, 0)

    def test_clean_dirty_and_ignored_files(self):
        self.assertEqual(self.helper("dirty").stdout.strip(), "false")
        (self.repo / "ignored").write_text("ignored\n")
        self.assertEqual(self.helper("dirty").stdout.strip(), "false")
        (self.repo / "untracked").write_text("new\n")
        self.assertEqual(self.helper("dirty").stdout.strip(), "true")
        (self.repo / "untracked").unlink()
        (self.repo / "app.txt").write_text("modified\n")
        self.assertEqual(self.helper("dirty").stdout.strip(), "true")
        self.git("add", "app.txt")
        self.assertEqual(self.helper("dirty").stdout.strip(), "true")

    def test_checked_out_head_not_workflow_sha_and_refreshes(self):
        initial = self.git("rev-parse", "HEAD")
        self.assertEqual(self.helper("revision").stdout.strip(), initial)
        self.git("commit", "--allow-empty", "-qm", "next")
        self.assertEqual(self.helper("revision").stdout.strip(), self.git("rev-parse", "HEAD"))
        self.git("checkout", "--detach", "-q", initial)
        self.assertEqual(self.helper("revision").stdout.strip(), initial)


if __name__ == "__main__":
    unittest.main()
