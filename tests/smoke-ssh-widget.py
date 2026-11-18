#!/usr/bin/env python3
"""Instantiate the native widget and its hidden lazy panel, without real SSH."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="ssh qml-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui", "services", "plugins"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
    plugin = root / "Widget"
    plugin.mkdir()
    for name in ("Panel.qml", "Service.qml", "Model.js"):
        shutil.copyfile(ROOT / name, plugin / name)
    shutil.copytree(ROOT / "i18n", plugin / "i18n")
    helper = plugin / "bin/ssh-master"
    helper.parent.mkdir(parents=True)
    example = {
        "version": 1,
        "hosts": [
            {"host": "test-server", "aliases": ["test-server", "test-alias"], "state": "open",
             "policy": "master-only", "sessions": 2, "destination": "user@localhost:22", "error": ""},
            {"host": "direct-server", "aliases": ["direct-server"], "state": "closed",
             "policy": "direct", "sessions": None, "destination": "user@localhost:22",
             "error": '<img src="https://example.invalid/tracker">'},
        ],
        "errors": [],
    }
    helper.write_text("#!/usr/bin/env python3\nprint(" + repr(json.dumps(example)) + ")\n")
    helper.chmod(0o700)
    (root / "shell.qml").write_text(f"""
import QtQuick
import Quickshell
import "./Widget" as Ssh
ShellRoot {{
  Ssh.Panel {{
    id: widget
    settings: ({{polling: false}})
  }}
  Ssh.Service {{
    id: service
    polling: false
  }}
  Timer {{
    interval: 300
    running: true
    onTriggered: {{
      for (var i = 0; i < widget.data.length; i++) {{
        var child = widget.data[i];
        if (typeof child.ensureContent === "function") child.ensureContent();
      }}
    }}
  }}
  Timer {{
    interval: 1200
    running: true
    onTriggered: {{
      var loaded = false;
      for (var i = 0; i < widget.data.length; i++) {{
        var child = widget.data[i];
        if (typeof child.ensureContent === "function" && child.loadedContent !== null) loaded = true;
      }}
      console.log(loaded && service.loaded && service.openCount === 1
        ? "SSH_WIDGET_SMOKE_OK" : "SSH_WIDGET_SMOKE_FAILED");
      Qt.quit();
    }}
  }}
}}
""")
    result = subprocess.run(
        ["quickshell", "-p", str(root), "--no-color"],
        env=dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / ".config"), QT_QPA_PLATFORM="wayland"),
        capture_output=True, text=True, timeout=10,
    )
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or "SSH_WIDGET_SMOKE_OK" not in output or any(
        marker in output for marker in (
            "Failed to load configuration", "ReferenceError:", "TypeError:",
            "Cannot assign", "is not a type", "Binding loop",
        )
    ):
        raise SystemExit(1)
