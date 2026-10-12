import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

CLI = Path(__file__).resolve().parents[2] / 'iOSBuildManager/iOSBuildManager/Resources/iosbuild.py'
spec = importlib.util.spec_from_file_location('iosbuild', CLI)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class CLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def invoke(self, *args):
        return subprocess.run([sys.executable, str(CLI), '--support-dir', str(self.root),
                               '--no-launch', *args], capture_output=True, text=True)

    def test_concurrent_clients_publish_complete_unique_commands(self):
        def enqueue(i):
            return self.invoke('enqueue', '--project', '/tmp/Project with spaces.xcodeproj',
                               '--scheme', f'App{i}', '--output', '/tmp/output with spaces')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(enqueue, range(24)))
        self.assertTrue(all(r.returncode == 0 for r in results))
        ids = {json.loads(r.stdout)['id'] for r in results}
        files = list((self.root / 'Queue/inbox').glob('*.json'))
        self.assertEqual(len(ids), 24)
        self.assertEqual(len(files), 24)
        self.assertEqual({json.loads(p.read_text())['id'] for p in files}, ids)

    def test_idempotent_retry_and_conflict(self):
        request_id = str(uuid.uuid4())
        args = ['enqueue', '--project', '/tmp/P.xcodeproj', '--scheme', 'App', '--request-id', request_id]
        self.assertEqual(self.invoke(*args).returncode, 0)
        self.assertEqual(self.invoke(*args).returncode, 0)
        self.assertEqual(len(list((self.root / 'Queue/inbox').glob('*.json'))), 1)
        self.assertEqual(self.invoke(*args, '--output', '/tmp/other').returncode, 1)

    def test_status_missing_and_wait_timeout(self):
        self.assertEqual(self.invoke('status', str(uuid.uuid4())).returncode, 1)
        response = self.invoke('enqueue', '--project', '/tmp/P.xcodeproj', '--scheme', 'App')
        job_id = json.loads(response.stdout)['id']
        self.assertEqual(json.loads(self.invoke('status', job_id).stdout)['state'], 'submitted')
        result = self.invoke('wait', job_id, '--timeout', '0')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)['error'], 'timeout')

    def test_failed_wait_exit_status_and_corrupt_state(self):
        queue = self.root / 'Queue'
        queue.mkdir()
        job_id = str(uuid.uuid4()).upper()
        (queue / 'state.json').write_text(json.dumps({'version': 1, 'paused': False, 'jobs': [
            {'request': {'id': job_id}, 'state': 'failed', 'error': 'fixture'}]}))
        self.assertEqual(self.invoke('wait', job_id).returncode, 1)
        (queue / 'state.json').write_text('broken')
        self.assertEqual(self.invoke('queue').returncode, 1)


if __name__ == '__main__':
    unittest.main()
