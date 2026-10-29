"""End-to-end runner contract, using synthetic scripts in a disposable project.

Run: python3 scripts/tests/test_test_runner.py
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class RunnerContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.game = self.root / 'game'
        (self.game / 'tests/unit').mkdir(parents=True)
        (self.root / 'scripts').mkdir()
        shutil.copy(REPO / 'scripts/test.sh', self.root / 'scripts/test.sh')
        # Use the real pinned editor launcher, without duplicating its installation logic.
        (self.root / 'scripts/godot.sh').write_text(
            '#!/bin/bash\nexec bash ' + str(REPO / 'scripts/godot.sh') + ' "$@"\n')
        for name in ('test_runner.gd', 'test_runner.tscn', 'test_case.gd', 'script_error_guard.gd'):
            shutil.copy(REPO / 'game/tests' / name, self.game / 'tests' / name)
        (self.game / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="RunnerContract"\n')
        (self.game / 'settings.gd').write_text(
            'class_name GameSettings\nextends Node\nfunc reload_from(_path: String) -> void:\n\tpass\n')
        (self.game / 'paths.gd').write_text(
            'class_name AssetCachePaths\nextends RefCounted\nstatic func resolve_cache_root() -> String:\n\treturn ""\n')

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, source):
        (self.game / 'tests' / name).write_text(source)

    def run_suite(self, timeout='15'):
        env = dict(os.environ, TEST_TIMEOUT_S=timeout)
        env.pop('ISOLATE', None)
        return subprocess.run(['bash', str(self.root / 'scripts/test.sh')], env=env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)

    def check_failure(self, result, summary=None):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('TESTS_FAILED', result.stdout)
        self.assertNotIn('TESTS_PASSED', result.stdout)
        if summary:
            self.assertIn(summary, result.stdout)

    def test_inherited_failure_and_override_counted_once(self):
        self.write('base.gd', 'extends TestCase\nfunc test_failure() -> void:\n\tfail("inherited")\nfunc test_override() -> void:\n\tfail("must be overridden")\n')
        self.write('unit/test_child.gd', 'extends "res://tests/base.gd"\nfunc test_override() -> void:\n\tpass\n')
        self.check_failure(self.run_suite(), '2 tests, 1 failed, 0 skipped')

    def test_parse_error(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc test_bad( broken syntax\n')
        self.check_failure(self.run_suite(), '1 tests, 1 failed, 0 skipped')

    def test_runtime_error(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc test_bad() -> void:\n\tvar d: Dictionary = {}\n\tprint(d["missing"])\n')
        self.check_failure(self.run_suite(), '1 tests, 1 failed, 0 skipped')

    def test_initializer_error(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc _init() -> void:\n\tvar d: Dictionary = {}\n\tprint(d["missing"])\nfunc test_ok() -> void:\n\tpass\n')
        self.check_failure(self.run_suite(), '1 tests, 1 failed, 0 skipped')

    def test_killed_process(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc test_bad() -> void:\n\tOS.kill(OS.get_process_id())\n')
        self.check_failure(self.run_suite())

    def test_clean_early_exit(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc test_bad() -> void:\n\tOS.get_main_loop().quit(0)\n\twhile true:\n\t\tawait OS.get_main_loop().process_frame\n')
        self.check_failure(self.run_suite())

    def test_timeout(self):
        self.write('unit/test_bad.gd', 'extends TestCase\nfunc test_bad() -> void:\n\twhile true:\n\t\tpass\n')
        self.check_failure(self.run_suite('1'))

    def test_empty_file(self):
        self.write('unit/test_empty.gd', 'extends TestCase\n')
        self.check_failure(self.run_suite(), '1 tests, 1 failed, 0 skipped')

    def test_zero_exit_without_completion(self):
        self.fake_editor('exit 0')
        self.check_failure(self.run_suite())

    def test_false_success_with_fail_line(self):
        self.fake_editor("printf 'FAIL synthetic\\n1 tests, 0 failed, 0 skipped, 1 files (1 ms)\\nTESTS_PASSED\\n'")
        self.check_failure(self.run_suite())

    def test_false_success_with_script_error(self):
        self.fake_editor("printf 'SCRIPT ERROR: synthetic\\n1 tests, 0 failed, 0 skipped, 1 files (1 ms)\\nTESTS_PASSED\\n'")
        self.check_failure(self.run_suite())

    def fake_editor(self, command):
        (self.root / 'scripts/godot.sh').write_text(
            '#!/bin/bash\nfor arg in "$@"; do [[ "$arg" == --import ]] && exit 0; done\n' + command + '\n')

    def test_import_error_with_zero_exit(self):
        (self.root / 'scripts/godot.sh').write_text(
            '#!/bin/bash\nfor arg in "$@"; do if [[ "$arg" == --import ]]; then echo "SCRIPT ERROR: synthetic import"; exit 0; fi; done\nprintf "1 tests, 0 failed, 0 skipped, 1 files (1 ms)\\nTESTS_PASSED\\n"\n')
        self.check_failure(self.run_suite())

    def test_no_files(self):
        self.check_failure(self.run_suite(), '1 tests, 1 failed, 0 skipped')

    def test_wrong_base_does_not_abort_remaining_file(self):
        self.write('unit/test_bad.gd', 'extends RefCounted\nfunc test_bad() -> void:\n\tpass\n')
        self.write('unit/test_later.gd', 'extends TestCase\nfunc test_ok() -> void:\n\tpass\n')
        self.check_failure(self.run_suite(), '2 tests, 1 failed, 0 skipped')

    def test_passing(self):
        self.write('unit/test_ok.gd', 'extends TestCase\nfunc test_ok() -> void:\n\tassert_true(true)\n')
        result = self.run_suite()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('1 tests, 0 failed, 0 skipped', result.stdout)
        self.assertIn('TESTS_PASSED', result.stdout)


if __name__ == '__main__':
    unittest.main()
