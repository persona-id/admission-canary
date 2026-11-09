"""check-workflow-permissions.sh: a job with id-token must not run dependency code."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".github/scripts/check-workflow-permissions.sh"


class CheckWorkflowPermissionsTests(unittest.TestCase):
    def setUp(self):
        # Skipping in CI would drop the id-token check with a green result, so CI fails instead.
        if not (shutil.which("yq") and shutil.which("jq")):
            if os.environ.get("CI"):
                self.fail("yq and jq are required in CI")
            self.skipTest("needs yq and jq")

    def run_guard(self, workflow, allow=None):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "w.yaml").write_text(workflow)
            allow_file = os.devnull
            if allow is not None:
                allow_file = str(Path(tmp) / "allow")
                Path(allow_file).write_text(allow)
            env = {**os.environ, "ALLOW_FILE": allow_file}
            return subprocess.run(["bash", str(SCRIPT), tmp], capture_output=True, text=True, env=env)

    def test_the_repository_workflows_pass(self):
        result = subprocess.run(["bash", str(SCRIPT), str(ROOT / ".github/workflows")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_an_install_without_scripts_passes(self):
        result = self.run_guard(
            "jobs:\n  install:\n    permissions:\n      id-token: write\n    steps:\n"
            "      - run: bin/npm-ci --ignore-scripts --loglevel=http\n"
            "      - run: echo \"npm test runs elsewhere\"\n"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_an_install_with_scripts_fails(self):
        result = self.run_guard("jobs:\n  install:\n    permissions:\n      id-token: write\n    steps:\n      - run: npm ci\n")
        self.assertEqual(result.returncode, 1)

    def test_tests_in_a_job_with_id_token_fail(self):
        result = self.run_guard(
            "jobs:\n  test:\n    permissions:\n      contents: read\n      id-token: write\n    steps:\n"
            "      - run: |\n          set -e\n          npm test\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("job 'test'", result.stdout)

    def test_workflow_level_id_token_reaches_jobs_without_permissions(self):
        result = self.run_guard("permissions:\n  id-token: write\njobs:\n  test:\n    steps:\n      - run: npx tsc --noEmit\n")
        self.assertEqual(result.returncode, 1)

    def test_a_job_without_id_token_may_run_anything(self):
        result = self.run_guard(
            "jobs:\n  test:\n    permissions:\n      contents: read\n    steps:\n      - run: npm test\n      - uses: ./.github/actions/setup\n"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_local_action_in_a_job_with_id_token_fails(self):
        result = self.run_guard(
            "jobs:\n  image:\n    permissions:\n      id-token: write\n    steps:\n      - uses: ./.github/actions/build-image\n      - uses: ./.github/actions/other\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("./.github/actions/other", result.stdout)

    def job_with_run(self, command):
        return "jobs:\n  j:\n    permissions:\n      id-token: write\n    steps:\n      - run: " + command + "\n"

    def test_ignore_scripts_false_is_not_safe(self):
        for command in ("npm ci --ignore-scripts=false", "bin/npm-ci --ignore-scripts --ignore-scripts=false", "npm ci --no-ignore-scripts"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 1)

    def test_a_command_after_the_install_is_not_safe(self):
        for command in ("npm ci --ignore-scripts $(npm test)", "npm ci --ignore-scripts `node x.js`", "npm ci --ignore-scripts && npm test", "npm ci --ignore-scripts > out"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 1)

    def test_other_ways_to_run_code_are_flagged(self):
        for command in ("make test", "bash scripts/test.sh", "./scripts/x", "python3 -m pytest", "uv run pytest", "docker run --rm img", "sh -c 'echo hi'"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 1)

    def test_a_path_in_command_position_is_flagged(self):
        for command in ("./.github/scripts/helper", ".github/scripts/helper", "bin/foo", "scripts/foo --x", "FOO=1 bin/tool", "echo hi && tools/run", "true | scripts/x"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 1)

    def test_a_path_as_an_argument_or_in_quotes_passes(self):
        for command in ('tar -czf "$RUNNER_TEMP/out.tgz" node_modules', "printf '%s' \"https://registry.npmjs.org/x\" | head -n 1"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 0)

    def test_an_action_must_be_pinned_to_a_sha(self):
        job = "jobs:\n  j:\n    permissions:\n      id-token: write\n    steps:\n      - uses: "
        for ref, code in (("actions/checkout@v7.0.1", 1), ("actions/checkout@main", 1), ("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", 0)):
            with self.subTest(ref=ref):
                self.assertEqual(self.run_guard(job + ref + "\n").returncode, code)

    def test_prose_and_build_commands_pass(self):
        for command in ('echo "npm test runs elsewhere"', "docker build -t img .", "tar -czf out.tgz node_modules", "corepack enable"):
            with self.subTest(command=command):
                self.assertEqual(self.run_guard(self.job_with_run(command)).returncode, 0)

    def test_an_action_off_the_allowlist_fails(self):
        result = self.run_guard("jobs:\n  j:\n    permissions:\n      id-token: write\n    steps:\n      - uses: someone/else@v1\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("someone/else@v1", result.stdout)

    def test_a_reusable_workflow_call_fails(self):
        result = self.run_guard("jobs:\n  j:\n    permissions:\n      id-token: write\n    uses: org/repo/.github/workflows/w.yml@main\n")
        self.assertEqual(result.returncode, 1)

    def test_an_unreadable_workflow_fails_closed(self):
        self.assertEqual(self.run_guard("jobs: [unclosed\n").returncode, 1)

    def test_an_oddly_shaped_workflow_fails_closed(self):
        self.assertEqual(self.run_guard("jobs: just a string\n").returncode, 1)

    def test_an_allow_listed_job_is_not_checked(self):
        result = self.run_guard(self.job_with_run("npm test").replace("  j:", "  j:"), allow="# why\nw.yaml:j  # owner reviews\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("allow-list", result.stdout)

    def test_the_allow_list_covers_only_the_named_job(self):
        workflow = (
            "jobs:\n  j:\n    permissions:\n      id-token: write\n    steps:\n      - run: npm test\n"
            "  k:\n    permissions:\n      id-token: write\n    steps:\n      - run: npm test\n"
        )
        result = self.run_guard(workflow, allow="w.yaml:j\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("job 'k'", result.stdout)
        self.assertNotIn("job 'j'", result.stdout.replace("job 'j' is on the allow-list", ""))

    def test_entries_are_exact_matches_only(self):
        for allow in ("other.yaml:j\n", "w.yaml:jj\n", "w.yaml:*\n", "*:j\n", "*\n", "w.yaml:j*\n", "w.yaml\n"):
            with self.subTest(allow=allow):
                self.assertEqual(self.run_guard(self.job_with_run("npm test"), allow=allow).returncode, 1)

    def test_an_empty_allow_list_allows_nothing(self):
        self.assertEqual(self.run_guard(self.job_with_run("npm test"), allow="# nothing\n\n").returncode, 1)


if __name__ == "__main__":
    unittest.main()
