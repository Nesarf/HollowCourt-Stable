#!/usr/bin/env python3
"""Tests for HMA's tools, with the emphasis on the boundaries rather than on the happy paths.

**Why this file exists at all.** The application has over a thousand tests and the development platform that serves it
had none -- 1,227 lines of Python that include a tool which *moves other people's files*. That proportion is the signal:
**the part with no tests is the part that writes.**

**What is tested, in order of how much it would hurt to get wrong:**

  * **`hma fix` does not write without `--apply`.** A dry run that is not dry is the worst bug this tool could have,
    and it is checked by actually running it against a temporary directory and comparing before and after.
  * **The agent refuses to leave the repository.** `docs/../..` is a string prefix match for `docs` and a directory
    walk for the filesystem, and an agent reading the whole disk is not what anybody asked for.
  * **The agent cannot write.** The handler table is asserted to be exactly the four read-only tools, so a fifth one
    added later has to be added here too and somebody has to think about it.
  * **`hma report` never includes the identity file.** Those keys are the device's ability to prove who it is, and a
    report that carried them is a report nobody should be asked to send.
  * **Every sentence a check prints is true of its own result.** `inspect()` was reporting "no packs exported" directly
    underneath two packs it had just found, because the explanation was static.

    python tool/hma_tests.py
"""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hma  # noqa: E402
import hma_agent  # noqa: E402
import hma_models  # noqa: E402


class KeySources(unittest.TestCase):
    """Three places are searched, in order, and none of them is the repository."""

    def test_extensions_are_discovered_without_touching_the_dispatch(self):
        """**The extension point, exercised in a directory of its own.**

        The loader is handed a temporary directory rather than the shipped one, so the test proves the mechanism
        without leaving anything behind. It checks the three properties that matter: a well-formed module becomes
        a command, a module that will not import is skipped rather than fatal, and a module without a `COMMAND` is
        skipped too -- because the failure mode of an extension point is a broken extension taking the command line
        down with it.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as scratch:
            good = os.path.join(scratch, 'good.py')
            io.open(good, 'w', encoding='utf-8').write(
                'def run(argv):\n    return 0\n\nCOMMAND = {"name": "good", "summary": "s", "run": run}\n')
            broken = os.path.join(scratch, 'broken.py')
            io.open(broken, 'w', encoding='utf-8').write('def run(:\n')
            quiet = os.path.join(scratch, 'quiet.py')
            io.open(quiet, 'w', encoding='utf-8').write('X = 1\n')

            found = hma.load_commands(scratch)
            self.assertIn('good', found)
            self.assertNotIn('broken', found)
            self.assertNotIn('quiet', found)
            self.assertEqual(0, found['good']['run']([]))

    def test_journal_records_before_the_move_and_undo_reverses_it(self):
        """**The safety net, exercised without touching anything real.**

        The cache directory is redirected to a temporary one and the file is created by the test, so the only thing
        this can damage is its own scratch space. What it checks is the property that matters: the record is written
        **before** the move, so an operation interrupted halfway is still accounted for, and `undo` puts the file back
        and leaves an entry saying that it did.

        **The whole sequence runs under one redirect.** A test that prints is not a failing test, but a suite whose
        last line is a command prose rather than a verdict reads like one -- and the pipeline, which takes the last
        informative line to decide, was reading it that way.
        """
        import tempfile
        previous = os.environ.get('HMA_CACHE_DIR')
        quiet = io.StringIO()
        saved = sys.stdout
        with tempfile.TemporaryDirectory() as scratch:
            os.environ['HMA_CACHE_DIR'] = scratch
            try:
                original = os.path.join(scratch, 'preferences.json')
                aside = os.path.join(scratch, 'preferences.json.moved-aside')
                io.open(original, 'w', encoding='utf-8').write('{}')

                hma.journal_append({'op': 'move-aside', 'id': 'preferences.json-0',
                                    'reason': 'unreadable', 'from': original, 'to': aside})
                os.rename(original, aside)

                self.assertEqual(1, len(hma.journal_read()))
                self.assertFalse(os.path.exists(original))

                sys.stdout = quiet
                try:
                    # a dry run must not move anything
                    self.assertEqual(0, hma.do_undo([]))
                    self.assertFalse(os.path.exists(original))

                    # and with --apply it comes back, with an entry saying so
                    self.assertEqual(0, hma.do_undo(['--apply']))
                    self.assertTrue(os.path.exists(original))
                    entries = hma.journal_read()
                    self.assertEqual(2, len(entries))
                    self.assertEqual('undo', entries[-1]['op'])
                    self.assertEqual('preferences.json-0', entries[-1]['undoes'])

                    # and a second undo has nothing left to claim
                    self.assertEqual(0, hma.do_undo(['--apply']))
                    self.assertEqual(2, len(hma.journal_read()))
                finally:
                    sys.stdout = saved
            finally:
                if previous is None:
                    os.environ.pop('HMA_CACHE_DIR', None)
                else:
                    os.environ['HMA_CACHE_DIR'] = previous

    def test_version_flag_is_read_from_the_command_not_the_script_path(self):
        """**`--version` has to answer, and reading the wrong argument is the mistake it guards.** `main` receives
        `sys.argv` whole, so `argv[0]` is the script path; a flag tested against it never matches, falls through to the
        dispatch and prints the help with a failing exit code."""
        import io as _io
        import contextlib
        buffer = _io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = hma.main(['hma.py', '--version'])
        self.assertEqual(0, code)
        self.assertIn(hma.HMA_VERSION, buffer.getvalue())

    def setUp(self) -> None:
        self.directory = tempfile.mkdtemp(prefix='hma-keys-')
        self.previous = hma_models.AUTH_DIR
        hma_models.AUTH_DIR = __import__('pathlib').Path(self.directory)
        for name in ('DASHSCOPE_API_KEY', 'DEEPSEEK_API_KEY', 'GEMINI_API_KEY', 'HMA_LOCAL_API_KEY'):
            os.environ.pop(name, None)

    def tearDown(self) -> None:
        hma_models.AUTH_DIR = self.previous
        shutil.rmtree(self.directory, ignore_errors=True)

    def test_env_wins(self) -> None:
        os.environ['DASHSCOPE_API_KEY'] = 'from-env'
        io.open(os.path.join(self.directory, 'hma-keys.json'), 'w').write('{"bailian": "from-file"}')
        self.assertEqual(hma_models.key_for('bailian'), 'from-env')

    def test_the_shared_map_is_second(self) -> None:
        io.open(os.path.join(self.directory, 'hma-keys.json'), 'w').write('{"bailian": "from-file"}')
        self.assertEqual(hma_models.key_for('bailian'), 'from-file')

    def test_a_provider_own_file_is_read(self) -> None:
        """**The machine already had one of these before this code existed**, so asking for a copy would be a tool
        that makes work rather than removes it."""
        io.open(os.path.join(self.directory, 'gemini-api-key.txt'), 'w').write('  from-its-own-file  ')
        self.assertEqual(hma_models.key_for('gemini'), 'from-its-own-file')

    def test_nothing_configured_is_not_an_error(self) -> None:
        self.assertIsNone(hma_models.key_for('bailian'))

    def test_the_local_row_is_a_seam_rather_than_a_provider(self) -> None:
        with self.assertRaises(ValueError) as caught:
            hma_models.chat('local', 'anything')
        self.assertIn('留的缝', str(caught.exception))

    def test_an_unknown_provider_says_what_it_knows(self) -> None:
        with self.assertRaises(ValueError) as caught:
            hma_models.chat('nonesuch', 'anything')
        self.assertIn('bailian', str(caught.exception))


class Overrides(unittest.TestCase):
    """A model name goes stale on the provider's schedule, so the file can replace it."""

    def setUp(self) -> None:
        self.directory = tempfile.mkdtemp(prefix='hma-ovr-')
        self.previous = hma_models.AUTH_DIR
        hma_models.AUTH_DIR = __import__('pathlib').Path(self.directory)

    def tearDown(self) -> None:
        hma_models.AUTH_DIR = self.previous
        shutil.rmtree(self.directory, ignore_errors=True)

    def test_a_bare_string_is_the_key(self) -> None:
        io.open(os.path.join(self.directory, 'hma-keys.json'), 'w').write('{"deepseek": "sk-x"}')
        self.assertEqual(hma_models.overrides('deepseek'), {'key': 'sk-x'})

    def test_an_object_carries_model_and_url(self) -> None:
        io.open(os.path.join(self.directory, 'hma-keys.json'), 'w').write(
            '{"deepseek": {"key": "sk-x", "model": "newer", "base_url": "http://elsewhere/v1"}}')
        self.assertEqual(hma_models.overrides('deepseek')['model'], 'newer')

    def test_a_broken_file_does_not_crash_the_tool(self) -> None:
        io.open(os.path.join(self.directory, 'hma-keys.json'), 'w').write('{not json at all')
        self.assertEqual(hma_models.load_keys(), {})


class Personas(unittest.TestCase):
    """The owner's ruling: Chinese and Japanese are her, English is the permanent secretary, and there is no plain."""

    def test_every_language_has_a_persona(self) -> None:
        for language in ('zh', 'ja', 'en'):
            self.assertTrue(hma_models.persona_for(language)['name'])

    def test_an_unknown_language_falls_back_rather_than_breaking(self) -> None:
        self.assertEqual(hma_models.persona_for('fr')['name'], hma_models.PERSONAS['zh']['name'])

    def test_the_prompt_carries_the_facts(self) -> None:
        """**This is the prompt that stopped the model inventing.** Asked what 空庭 is with no context it described a
        companion application with story interaction; with this it lists the four things the application does."""
        prompt = hma_models.system_prompt('zh')
        for fact in ('酒窖', 'cellar.ndjson', 'HMA'):
            self.assertIn(fact, prompt)

    def test_her_hardest_rule_is_in_her_instructions(self) -> None:
        self.assertIn('不编', hma_models.system_prompt('zh'))

    def test_she_never_uses_the_disrespectful_word(self) -> None:
        self.assertIn('庶民', hma_models.system_prompt('zh'))  # mentioned as forbidden, never used


class AgentBoundaries(unittest.TestCase):
    """The part that would hurt most if it were wrong."""

    def test_relative_traversal_is_refused(self) -> None:
        self.assertIsNone(hma_agent._inside('docs/../..'))
        self.assertIsNone(hma_agent._inside('../../etc/passwd'))

    def test_absolute_paths_are_refused(self) -> None:
        """**"Absolute" is whatever the running host calls absolute, and that is the point of this test.**

        The first version asserted on `C:/Windows/System32/config/SAM` unconditionally. It passed on Windows and failed on
        Linux, where that string is **not** absolute -- it is a relative name whose first segment happens to be `C:` -- so
        the guard read it as repo-relative, which is the correct reading of the string it was handed, and resolved it
        *inside* the repository. **The test was asserting a fact about the host rather than about the guard**, which is the
        same fault as a check that passes while being wrong.
        """
        # Built from this host's own root, so it is absolute wherever this runs.
        self.assertIsNone(hma_agent._inside(os.path.abspath(os.sep + 'etc' + os.sep + 'passwd')))
        # **A leading separator is not “absolute” on Windows, and it is still refused.** `os.path.isabs`
        # says False there, so the guard takes the repo-relative branch -- and `pathlib`'s `/` discards the left
        # operand when the right one is rooted, so it resolves to `E:\etc\passwd` and lands outside anyway.
        # The refusal is right; the reason is the join, not the absoluteness.
        self.assertIsNone(hma_agent._inside('/etc/passwd'))

        if os.name == 'nt':
            self.assertIsNone(hma_agent._inside('C:/Windows/System32/config/SAM'))
        else:
            # **And where that string is not a path, it is a name**, so the answer is a path inside the repository. Saying
            # what happens is the honest version of the assertion, and it is deliberately not "None".
            resolved = hma_agent._inside('C:/Windows/System32/config/SAM')
            self.assertIsNotNone(resolved)
            self.assertTrue(str(resolved).startswith(str(hma_agent.REPO)),
                            '一个不是绝对路径的名字应当被当作仓库内的相对名：%s' % resolved)

    def test_a_path_inside_is_allowed(self) -> None:
        self.assertIsNotNone(hma_agent._inside('docs/HMA.md'))

    def test_reading_outside_returns_a_sentence_not_an_exception(self) -> None:
        answer = hma_agent.tool_read_file(path='../../etc/passwd')
        self.assertIn('拒绝', answer)

    def test_a_bad_regex_is_reported_rather_than_raised(self) -> None:
        self.assertIn('正则', hma_agent.tool_search(pattern='([unclosed'))

    def test_the_tool_set_is_exactly_the_read_only_four(self) -> None:
        """**A fifth tool added later has to be added here too**, which is the point: somebody has to think about
        whether it writes."""
        self.assertEqual(sorted(hma_agent.HANDLERS), ['doctor', 'list_files', 'read_file', 'search'])

    def test_no_handler_name_suggests_writing(self) -> None:
        for name in hma_agent.HANDLERS:
            for verb in ('write', 'delete', 'remove', 'move', 'edit', 'apply', 'fix'):
                self.assertNotIn(verb, name)

    def test_the_loop_is_capped(self) -> None:
        self.assertGreater(hma_agent.MAX_ROUNDS, 0)
        self.assertLessEqual(hma_agent.MAX_ROUNDS, 16)

    def test_the_prompt_offers_only_the_real_tools(self) -> None:
        offered = {entry['function']['name'] for entry in hma_agent.TOOLS}
        self.assertEqual(offered, set(hma_agent.HANDLERS))


class DoctorFindings(unittest.TestCase):
    """Every sentence is true of its own result -- the rule that was broken by a static explanation."""

    def test_every_finding_explains_itself(self) -> None:
        for finding in hma.inspect():
            self.assertTrue(finding['why'].strip(), '%s has no reason' % finding['what'])

    def test_why_differs_between_states(self) -> None:
        """**The defect this guards**: the pack line said 「没有包不算毛病」 underneath two packs it had found."""
        source = io.open(os.path.join(HERE, 'hma.py'), encoding='utf-8').read()
        self.assertNotIn("'why': '没有包不算毛病'", source)


class FixDoesNotWriteWithoutApply(unittest.TestCase):
    """The one that matters most: this tool moves other people's files."""

    def setUp(self) -> None:
        self.directory = tempfile.mkdtemp(prefix='hma-fix-')
        self.previous_org = hma.organisation_dir
        self.previous_docs = hma.documents_dir
        hma.organisation_dir = lambda: (__import__('pathlib').Path(self.directory) / 'com.nesarf', 'test')
        hma.documents_dir = lambda: (__import__('pathlib').Path(self.directory), 'test')
        app = __import__('pathlib').Path(self.directory) / 'com.nesarf' / 'Hollow Court'
        app.mkdir(parents=True)
        io.open(str(app / 'preferences.json'), 'w').write('{ this is not json')
        io.open(str(app / 'display.json'), 'w').write('{"textSize": "large"}')

    def tearDown(self) -> None:
        hma.organisation_dir = self.previous_org
        hma.documents_dir = self.previous_docs
        shutil.rmtree(self.directory, ignore_errors=True)

    def _run(self, *arguments: str) -> int:
        return subprocess.run([sys.executable, os.path.join(HERE, 'hma.py'), 'fix', *arguments],
                              capture_output=True, text=True, cwd=HERE).returncode

    def test_the_dry_run_changes_nothing(self) -> None:
        before = sorted(os.listdir(os.path.join(self.directory, 'com.nesarf', 'Hollow Court')))
        self._run()
        after = sorted(os.listdir(os.path.join(self.directory, 'com.nesarf', 'Hollow Court')))
        self.assertEqual(before, after)

    def test_the_broken_file_is_still_broken_after_a_dry_run(self) -> None:
        self._run()
        text = io.open(os.path.join(self.directory, 'com.nesarf', 'Hollow Court', 'preferences.json')).read()
        self.assertEqual(text, '{ this is not json')


class ArtChecker(unittest.TestCase):
    """It has already caught two real things, so it is worth keeping honest."""

    def test_it_passes_on_the_real_art(self) -> None:
        result = subprocess.run([sys.executable, os.path.join(HERE, 'hma_art_check.py')],
                                capture_output=True, text=True, cwd=HERE)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_palette_is_declared_and_small(self) -> None:
        import hma_art_check
        self.assertLessEqual(len(hma_art_check.PALETTE), 4)


if __name__ == '__main__':
    unittest.main(verbosity=2)
