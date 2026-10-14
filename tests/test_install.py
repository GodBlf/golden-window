"""Isolated installer checks; never reload or launch the real Hammerspoon."""
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='golden-window-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config with spaces'
        self.config.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub('pgrep', 'exit 1')
        self.stub('open', 'exit 0')
        self.stub('uname', 'echo Darwin')
        self.home = self.root / 'home'
        (self.home / 'Applications/Hammerspoon.app').mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home),
                        GOLDEN_WINDOW_CONFIG_DIR=str(self.config),
                        PATH=str(self.bin) + ':/usr/bin:/bin:/usr/sbin:/sbin')
        self.env.pop('GOLDEN_WINDOW_LANG', None)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_install(self, language=None, answers=None):
        env = self.env.copy()
        if language is not None:
            env['GOLDEN_WINDOW_LANG'] = language
        command = ['/bin/bash', str(PROJECT / 'install.sh')]
        if answers is None:
            result = subprocess.run(command, env=env, input='', text=True,
                                    capture_output=True, timeout=15)
            return result.returncode, result.stdout + result.stderr
        master, slave = pty.openpty()
        process = subprocess.Popen(command, env=env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = b''
        sent = False
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        part = os.read(master, 65536)
                    except OSError:
                        break
                    if not part:
                        break
                    output += part
                    if not sent and b'Language /' in output:
                        os.write(master, answers.encode())
                        sent = True
                if process.poll() is not None:
                    # Drain remaining terminal output before closing.
                    while select.select([master], [], [], 0)[0]:
                        try:
                            output += os.read(master, 65536)
                        except OSError:
                            break
                    break
            return process.wait(timeout=2), output.decode()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)

    def language(self):
        return (self.config / '.golden-window-language').read_text()

    def snapshot(self):
        return {p.name: (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_ino)
                for p in self.config.iterdir() if p.is_file()}

    def test_noninteractive_first_install_and_idempotence(self):
        code, output = self.run_install()
        self.assertEqual(code, 0, output)
        self.assertEqual(self.language(), 'en\n')
        self.assertIn('Maximize and center', output)
        before = self.snapshot()
        backups = list((self.config / 'backups').iterdir())
        code, output = self.run_install()
        self.assertEqual(code, 0, output)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(backups, list((self.config / 'backups').iterdir()))
        self.assertIn('no files need rewriting', output)
        self.assertEqual((self.config / 'init.lua').read_text().count('goldenWindow = require'), 1)

    def test_switch_and_remember_language(self):
        self.assertEqual(self.run_install('en')[0], 0)
        before = self.snapshot()
        code, output = self.run_install('zh-CN')
        self.assertEqual(code, 0, output)
        self.assertEqual(self.language(), 'zh-CN\n')
        self.assertIn('最大尺寸并居中', output)
        for name in ('init.lua', 'golden-window.lua'):
            self.assertEqual(before[name], self.snapshot()[name])
        saved = list((self.config / 'backups').glob('*/.golden-window-language'))
        self.assertEqual([p.read_text() for p in saved], ['en\n'])
        self.assertEqual(self.run_install()[0], 0)
        self.assertEqual(self.language(), 'zh-CN\n')
        self.assertEqual(self.run_install('en')[0], 0)
        self.assertEqual(self.language(), 'en\n')

    def test_interactive_choices_defaults_and_retry(self):
        code, output = self.run_install(answers='invalid\n2\n')
        self.assertEqual(code, 0, output)
        self.assertIn('Please enter 1 or 2', output)
        self.assertEqual(self.language(), 'zh-CN\n')
        self.assertEqual(self.run_install(answers='\n')[0], 0)
        self.assertEqual(self.language(), 'zh-CN\n')
        self.assertEqual(self.run_install(answers='1\n')[0], 0)
        self.assertEqual(self.language(), 'en\n')

    def test_interactive_first_default(self):
        self.assertEqual(self.run_install(answers='\n')[0], 0)
        self.assertEqual(self.language(), 'en\n')

    def test_invalid_environment_language(self):
        for language in ('fr', '', 'en"; error("bad")'):
            code, output = self.run_install(language)
            self.assertNotEqual(code, 0)
            self.assertIn('GOLDEN_WINDOW_LANG', output)
            self.assertEqual(list(self.config.iterdir()), [])

    def test_invalid_saved_language_falls_back(self):
        (self.config / '.golden-window-language').write_text('fr\n')
        self.assertEqual(self.run_install()[0], 0)
        self.assertEqual(self.language(), 'en\n')

    def test_original_upgrade_and_backup(self):
        original = subprocess.check_output(['git', 'show', '4a42d89:golden-window.lua'], cwd=PROJECT)
        (self.config / 'golden-window.lua').write_bytes(original)
        (self.config / 'init.lua').write_text('-- unrelated\nrequire("hs.ipc")\ngoldenWindow = require("golden-window")\n')
        before = (self.config / 'init.lua').read_bytes()
        code, output = self.run_install('zh-CN')
        self.assertEqual(code, 0, output)
        self.assertEqual((self.config / 'golden-window.lua').read_bytes(), (PROJECT / 'golden-window.lua').read_bytes())
        self.assertEqual((self.config / 'init.lua').read_bytes(), before)
        self.assertEqual(next((self.config / 'backups').glob('*/golden-window.lua')).read_bytes(), original)

    def test_custom_module_does_not_save_language(self):
        (self.config / 'golden-window.lua').write_text('-- custom\n')
        (self.config / '.golden-window-language').write_text('en\n')
        before = self.snapshot()
        code, output = self.run_install('zh-CN')
        self.assertNotEqual(code, 0)
        self.assertIn('已有 golden-window.lua', output)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.config / '.golden-window-install.lock').exists())

    def test_symlink_protection(self):
        for name in ('init.lua', 'golden-window.lua', '.golden-window-language'):
            with self.subTest(name=name):
                target = self.root / 'target'
                target.write_text('untouched\n')
                link = self.config / name
                link.symlink_to(target)
                code, output = self.run_install('en')
                self.assertNotEqual(code, 0)
                self.assertIn('symbolic link', output)
                self.assertEqual(target.read_text(), 'untouched\n')
                self.assertTrue(link.is_symlink())
                link.unlink()

    def test_lock_protection(self):
        (self.config / '.golden-window-install.lock').mkdir()
        code, output = self.run_install('en')
        self.assertNotEqual(code, 0)
        self.assertIn('stale lock', output)
        self.assertFalse((self.config / '.golden-window-language').exists())

    def test_ambiguous_init_protection(self):
        (self.config / 'init.lua').write_text('custom = require("golden-window")\n')
        before = self.snapshot()
        self.assertNotEqual(self.run_install('en')[0], 0)
        self.assertEqual(before, self.snapshot())

    def test_ipc_language_verification(self):
        self.stub('pgrep', 'exit 0')
        self.stub('hs', 'printf "%s\\n" "$*" >> "$GOLDEN_WINDOW_CONFIG_DIR/ipc-calls"\nexit 0')
        code, output = self.run_install('zh-CN')
        self.assertEqual(code, 0, output)
        self.assertIn('配置已重载', output)
        calls = (self.config / 'ipc-calls').read_text()
        self.assertIn('hs.reload()', calls)
        self.assertIn('goldenWindow.language == "zh-CN"', calls)

    def test_failed_reload_guidance(self):
        self.stub('pgrep', 'exit 0')
        self.stub('hs', 'exit 1')
        code, output = self.run_install('en')
        self.assertEqual(code, 0, output)
        self.assertIn('Reload Config', output)
        self.assertEqual(self.language(), 'en\n')


if __name__ == '__main__':
    unittest.main()
