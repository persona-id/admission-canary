"""bin/npm-ci: proxy or public registry, token sources, and the refusal of a half-set proxy.

A fake npm on PATH records the arguments and environment it was given."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NPM_CI = ROOT / "bin/npm-ci"
FAKE_NPM = """#!/bin/sh
{
  echo "args=$*"
  echo "registry=${npm_config_registry:-}"
  echo "token_in_env=${PPP_TOKEN:-}"
  if [ -n "${NPM_CONFIG_USERCONFIG:-}" ]; then
    echo "mode=$(stat -c %a "$NPM_CONFIG_USERCONFIG")"
    echo "config=$(cat "$NPM_CONFIG_USERCONFIG")"
  else
    echo "mode="
    echo "config="
  fi
} > "$FAKE_NPM_LOG"
"""


class NpmCiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        npm = self.bin / "npm"
        npm.write_text(FAKE_NPM)
        npm.chmod(0o755)
        self.log = Path(self.tmp.name) / "npm.log"

    def run_npm_ci(self, *args, **env):
        base = {k: v for k, v in os.environ.items() if not k.startswith(("PPP_", "NPM_", "npm_"))}
        base.update(PATH=f"{self.bin}:{base['PATH']}", FAKE_NPM_LOG=str(self.log), TMPDIR=self.tmp.name, **env)
        return subprocess.run(["sh", str(NPM_CI), *args], env=base, capture_output=True, text=True)

    def recorded(self):
        return dict(line.split("=", 1) for line in self.log.read_text().splitlines())

    def test_no_credentials_uses_the_public_registry(self):
        result = self.run_npm_ci("--ignore-scripts")
        self.assertEqual(result.returncode, 0, result.stderr)
        seen = self.recorded()
        self.assertEqual(seen["args"], "ci --ignore-scripts")
        self.assertEqual(seen["registry"], "")
        self.assertEqual(seen["config"], "")

    def test_token_and_registry_use_the_proxy(self):
        result = self.run_npm_ci("--ignore-scripts", PPP_TOKEN="s3cret", NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(result.returncode, 0, result.stderr)
        seen = self.recorded()
        self.assertEqual(seen["args"], "ci --ignore-scripts")
        self.assertEqual(seen["registry"], "https://proxy.example/npm/")
        # The key is the registry without its scheme, and the token is npm's to expand.
        self.assertEqual(seen["config"], "//proxy.example/npm/:_authToken=${PPP_TOKEN}")
        self.assertEqual(seen["mode"], "600")
        self.assertEqual(seen["token_in_env"], "s3cret")
        self.assertNotIn("s3cret", result.stderr)

    def test_the_proxy_path_always_ignores_scripts(self):
        proxy = dict(PPP_TOKEN="t", NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        for args, want in (
            ((), "ci --ignore-scripts"),
            (("--omit=dev",), "ci --omit=dev --ignore-scripts"),
            (("--ignore-scripts=false", "--loglevel=http"), "ci --loglevel=http --ignore-scripts"),
            (("--no-ignore-scripts",), "ci --ignore-scripts"),
            (("--ignore-scripts", "--omit=dev"), "ci --omit=dev --ignore-scripts"),
        ):
            with self.subTest(args=args):
                result = self.run_npm_ci(*args, **proxy)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.recorded()["args"], want)

    def test_without_the_proxy_the_arguments_are_untouched(self):
        result = self.run_npm_ci("--omit=dev")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()["args"], "ci --omit=dev")

    def test_registry_without_a_trailing_slash_gets_one(self):
        self.run_npm_ci(PPP_TOKEN="t", NPM_PROXY_REGISTRY="https://proxy.example/npm")
        seen = self.recorded()
        self.assertEqual(seen["registry"], "https://proxy.example/npm/")
        self.assertEqual(seen["config"], "//proxy.example/npm/:_authToken=${PPP_TOKEN}")

    def test_token_from_a_file(self):
        secret = Path(self.tmp.name) / "ppp_token"
        secret.write_text("from-file")
        result = self.run_npm_ci(PPP_TOKEN_FILE=str(secret), NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()["token_in_env"], "from-file")

    def test_the_environment_token_wins_over_the_file(self):
        secret = Path(self.tmp.name) / "ppp_token"
        secret.write_text("from-file")
        self.run_npm_ci(PPP_TOKEN="from-env", PPP_TOKEN_FILE=str(secret), NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(self.recorded()["token_in_env"], "from-env")

    def test_an_empty_token_file_is_no_token(self):
        secret = Path(self.tmp.name) / "ppp_token"
        secret.write_text("")
        result = self.run_npm_ci(PPP_TOKEN_FILE=str(secret))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()["registry"], "")

    def test_a_token_without_a_registry_is_refused(self):
        result = self.run_npm_ci(PPP_TOKEN="t")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.log.exists(), "npm must not run")
        self.assertIn("refusing", result.stderr)

    def test_required_with_no_credentials_is_refused(self):
        result = self.run_npm_ci("--ignore-scripts", PPP_REQUIRED="1")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.log.exists(), "npm must not run")
        self.assertIn("PPP_REQUIRED", result.stderr)

    def test_required_with_only_one_credential_is_refused(self):
        for env in ({"PPP_TOKEN": "t"}, {"NPM_PROXY_REGISTRY": "https://proxy.example/npm/"}):
            with self.subTest(env=env):
                result = self.run_npm_ci(PPP_REQUIRED="1", **env)
                self.assertEqual(result.returncode, 1)
                self.assertFalse(self.log.exists(), "npm must not run")
                # The half-set check also exits 1, so the message tells the two guards apart.
                self.assertIn("PPP_REQUIRED", result.stderr)

    def test_required_with_an_empty_token_file_is_refused(self):
        secret = Path(self.tmp.name) / "ppp_token"
        secret.write_text("")
        result = self.run_npm_ci(PPP_REQUIRED="1", PPP_TOKEN_FILE=str(secret), NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(result.returncode, 1)
        self.assertIn("PPP_REQUIRED", result.stderr)

    def test_required_with_both_credentials_uses_the_proxy(self):
        result = self.run_npm_ci(PPP_REQUIRED="1", PPP_TOKEN="t", NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()["registry"], "https://proxy.example/npm/")
        self.assertIn("installing through the package proxy", result.stderr)

    def test_an_empty_required_is_not_required(self):
        result = self.run_npm_ci(PPP_REQUIRED="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()["registry"], "")

    def test_a_registry_without_a_token_is_refused(self):
        result = self.run_npm_ci(NPM_PROXY_REGISTRY="https://proxy.example/npm/")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.log.exists(), "npm must not run")


if __name__ == "__main__":
    unittest.main()
