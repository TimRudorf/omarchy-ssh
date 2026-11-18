import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/ssh-master"
loader = importlib.machinery.SourceFileLoader("ssh_master", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
master = importlib.util.module_from_spec(spec)
loader.exec_module(master)


class UnitTests(unittest.TestCase):
    def test_host_validation(self):
        for name in ("build-server", "test-server", "host.example"):
            self.assertEqual(master.validate_host(name), name)
        for name in ("-oProxyCommand=evil", "$(touch bad)", "host;evil", "<img src=x>", "../host"):
            with self.assertRaises(master.MasterError):
                master.validate_host(name)

    def test_count_sessions_not_control_clients_or_forwards(self):
        raw = """The following connections are open:
  #1 /tmp/socket (t16 [mux-control] nr0 nm0 i0/0)
  #2 client-session (t4 [session:command] r0 nm0 i0/0)
  #3 client-session (t4 [session] r1 nm0 i0/0)
  #4 direct-tcpip (t4 [direct-tcpip] r2 nm0 i0/0)
"""
        self.assertEqual(master.session_count(raw), 2)
        self.assertEqual(master.session_count("The following connections are open:\r\n"), 0)
        self.assertIsNone(master.session_count("A future incompatible format"))

    def test_discovery_includes_aliases_but_not_patterns(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "extra").write_text("Host included alias\nHost *.example !excluded\n")
            (root / "config").write_text(f"Include {root}/extra\nHost=first\nHost second third\n")
            self.assertEqual(master.discover_hosts(root / "config"), ["included", "alias", "first", "second", "third"])

    def test_group_by_socket_not_alias(self):
        def info(host, config):
            return dict(host=host, aliases=[host], socket="one" if host != "root" else "two",
                        destination="x", policy="master-only")
        with patch.object(master, "discover_hosts", return_value=["build-server", "test-server", "root"]), \
             patch.object(master, "host_info", side_effect=info):
            groups, errors = master.grouped_hosts()
        self.assertEqual(groups[0]["aliases"], ["build-server", "test-server"])
        self.assertEqual(len(groups), 2)
        self.assertEqual(errors, [])

@unittest.skipUnless(shutil.which("sshd") and shutil.which("ssh-keygen"), "OpenSSH server required")
class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="ssh-widget-")
        cls.root = Path(cls.temp.name)
        cls.processes = []
        cls.mounts = []
        cls.env_patch = patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(cls.root)})
        cls.env_patch.start()
        for name in ("host_key", "client_key"):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(cls.root / name)], check=True)
        user = pwd.getpwuid(os.getuid()).pw_name
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            cls.port = sock.getsockname()[1]
        server = cls.root / "sshd_config"
        server.write_text(f"""ListenAddress 127.0.0.1
Port {cls.port}
HostKey {cls.root}/host_key
PidFile {cls.root}/sshd.pid
AuthorizedKeysFile {cls.root}/client_key.pub
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
AllowUsers {user}
Subsystem sftp internal-sftp
LogLevel VERBOSE
""")
        cls.log = (cls.root / "sshd.log").open("w+")
        cls.server = subprocess.Popen(["/usr/bin/sshd", "-D", "-e", "-f", str(server)],
                                      stdout=cls.log, stderr=cls.log)
        for _ in range(100):
            if cls.server.poll() is not None:
                cls.log.seek(0)
                message = cls.log.read()
                cls.log.close()
                cls.env_patch.stop()
                cls.temp.cleanup()
                raise RuntimeError(f"Local test sshd failed: {message}")
            try:
                with socket.create_connection(("127.0.0.1", cls.port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.03)
        cls.config = cls.root / "config"
        cls.direct_config = cls.root / "config-no-policy"
        baseline = f"""Host locked alias
    HostName 127.0.0.1
Host direct
    HostName 127.0.0.1
    ProxyCommand none
Host *
    Port {cls.port}
    User {user}
    IdentityFile {cls.root}/client_key
    IdentitiesOnly yes
    IdentityAgent none
    StrictHostKeyChecking no
    UserKnownHostsFile {cls.root}/known_hosts
    ControlPath {cls.root}/%C
    ControlMaster no
    BatchMode yes
"""
        cls.direct_config.write_text(baseline)
        cls.config.write_text(baseline + f"Host *\n    Include {ROOT / 'ssh/master-only.conf'}\n")

    @classmethod
    def tearDownClass(cls):
        for mount in cls.mounts:
            subprocess.run(["fusermount3", "-u", str(mount)], capture_output=True)
        for process in cls.processes:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)
        subprocess.run(["ssh", "-F", str(cls.config), "-O", "exit", "locked"], capture_output=True)
        cls.server.terminate()
        cls.server.wait(timeout=5)
        cls.log.close()
        cls.env_patch.stop()
        cls.temp.cleanup()

    def ssh(self, *args):
        return subprocess.run(["ssh", "-F", str(self.config), *args], capture_output=True, text=True, timeout=8)

    def test_full_lifecycle_and_transfer_policy(self):
        info = master.host_info("locked", self.config)
        self.assertEqual(info["policy"], "master-only")
        self.assertEqual(master.host_info("direct", self.config)["policy"], "direct")
        self.assertEqual(master.host_info("locked", self.direct_config)["policy"], "direct")
        direct = subprocess.run(["ssh", "-F", str(self.direct_config), "locked", "printf no-policy"],
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(direct.stdout, "no-policy", direct.stderr)
        denied = self.ssh("locked", "true")
        self.assertNotEqual(denied.returncode, 0)
        self.assertNotEqual(self.ssh("-O", "check", "locked").returncode, 0)
        self.assertEqual(self.ssh("direct", "printf direct-ok").stdout, "direct-ok")
        with socket.socket(socket.AF_UNIX) as stale:
            stale.bind(info["socket"])
        self.assertEqual(master.status(info, self.config)["state"], "closed")
        self.assertTrue(Path(info["socket"]).exists(), "Status must not remove stale sockets")
        self.assertIn("opened", master.open_master(info, self.config))
        self.assertEqual(master.status(info, self.config, False)["state"], "open")
        self.assertEqual(self.ssh("-O", "check", "locked").returncode, 0)
        self.assertEqual(self.ssh("locked", "printf master-ok").stdout, "master-ok")
        groups, errors = master.grouped_hosts(self.config)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["policy"], "mixed")
        self.assertFalse(errors)

        session = subprocess.Popen(["ssh", "-F", str(self.config), "locked", "echo ready; read line; echo done"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(session)
        self.assertEqual(session.stdout.readline().strip(), "ready")
        state = master.status(info, self.config)
        self.assertEqual(state["state"], "open")
        self.assertEqual(state["sessions"], 1)

        sample = self.root / "sample"
        sample.write_text("transfer test")
        target = self.root / "transferred"
        result = subprocess.run(["scp", "-F", str(self.config), str(sample), f"locked:{target}"],
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), "transfer test")
        if shutil.which("rsync"):
            target.unlink()
            result = subprocess.run(["rsync", "-e", f"ssh -F {self.config}", str(sample), f"locked:{target}"],
                                    capture_output=True, text=True, timeout=8)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(target.read_text(), "transfer test")

        mounted = None
        if shutil.which("sshfs") and shutil.which("fusermount3") and os.access("/dev/fuse", os.R_OK | os.W_OK):
            mounted = self.root / "mounted"
            mounted.mkdir()
            mount = subprocess.run(
                ["sshfs", "-F", str(self.config), f"locked:{self.root}", str(mounted)],
                capture_output=True, text=True, timeout=8,
            )
            self.assertEqual(mount.returncode, 0, mount.stderr)
            self.mounts.append(mounted)
            self.assertEqual((mounted / "sample").read_text(), "transfer test")
            self.assertEqual(master.status(info, self.config)["sessions"], 2)

        master.close_master(info, self.config)
        self.assertIsNone(session.poll())
        self.assertEqual(master.status(info, self.config)["state"], "closed")
        self.assertNotEqual(self.ssh("alias", "true").returncode, 0)
        target.unlink()
        result = subprocess.run(["scp", "-F", str(self.config), str(sample), f"locked:{target}"],
                                capture_output=True, text=True, timeout=8)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(target.exists())
        if mounted:
            (mounted / "after-close").write_text("existing SSHFS survives")
            self.assertEqual((self.root / "after-close").read_text(), "existing SSHFS survives")
            rejected = self.root / "rejected-mount"
            rejected.mkdir()
            mount = subprocess.run(
                ["sshfs", "-F", str(self.config), f"locked:{self.root}", str(rejected)],
                capture_output=True, text=True, timeout=8,
            )
            self.assertNotEqual(mount.returncode, 0)
            self.assertFalse(os.path.ismount(rejected))
            subprocess.run(["fusermount3", "-u", str(mounted)], check=True)
            self.mounts.remove(mounted)
        if shutil.which("rsync"):
            result = subprocess.run(["rsync", "-e", f"ssh -F {self.config}", str(sample), f"locked:{target}"],
                                    capture_output=True, text=True, timeout=8)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(target.exists())

        master.open_master(info, self.config)
        self.assertEqual(master.status(info, self.config)["sessions"], 0)
        self.assertIsNone(session.poll())
        out, err = session.communicate("finish\n", timeout=8)
        self.assertEqual(session.returncode, 0, err)
        self.assertIn("done", out)
        self.assertEqual(master.status(info, self.config)["state"], "open")
        close_all = subprocess.run([str(HELPER), "-F", str(self.config), "close-all"],
                                   capture_output=True, text=True, timeout=8)
        self.assertEqual(close_all.returncode, 0, close_all.stderr)
        self.assertEqual(self.ssh("direct", "printf still-direct").stdout, "still-direct")
        snapshot = subprocess.run([str(HELPER), "-F", str(self.config), "status", "--json"],
                                  capture_output=True, text=True, timeout=8)
        self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
        self.assertEqual(json.loads(snapshot.stdout)["hosts"][0]["state"], "closed")


if __name__ == "__main__":
    unittest.main()
