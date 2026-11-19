#!/usr/bin/env python3
"""Exercise the native widget and action verification, without real SSH."""

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
              "error": ""},
            {"host": "unknown-server", "aliases": ["unknown-server"], "state": "unknown",
              "policy": "mixed", "sessions": None, "destination": "user@localhost:22",
              "error": '<img src="https://example.invalid/tracker">'},
            {"host": "unavailable-server", "aliases": ["unavailable-server"], "state": "unavailable",
              "policy": "master-only", "sessions": None, "destination": "", "error": "No ControlPath"},
            {"host": "no-count", "aliases": ["no-count"], "state": "open",
              "policy": "master-only", "sessions": None, "destination": "", "error": "Session count unavailable."},
        ],
        "errors": [],
    }
    (helper.parent / "status.json").write_text(json.dumps(example))
    helper.write_text("""#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path

directory = Path(__file__).parent
status = directory / "status.json"
result = json.loads(status.read_text())
command, *args = sys.argv[1:]
if command == "status":
    time.sleep(0.25)
    if "--no-sessions" in args:
        for host in result["hosts"]:
            host["sessions"] = None
    print(json.dumps(result))
    sys.exit(0)
with (directory / "actions.log").open("a") as log:
    print(" ".join([command, *args]), file=log)
if command == "close" and not (directory / "failed-once").exists():
    (directory / "failed-once").touch()
    sys.exit("Simulated SSH error")
for host in result["hosts"]:
    if command == "close-all" and host["state"] == "open":
        host.update(state="closed", sessions=None)
    elif args and host["host"] == args[0]:
        host.update(state="open", sessions=0) if command == "open" else host.update(state="closed", sessions=None)
status.write_text(json.dumps(result))
""")
    helper.chmod(0o700)
    (root / "shell.qml").write_text("""
import QtQuick
import Quickshell
import "./Widget" as Ssh
ShellRoot {
  property var panel
  property var service
  property int phase: 0

  function find(item, predicate) {
    if (predicate(item)) return item;
    for (var i = 0; i < item.children.length; i++) {
      var result = find(item.children[i], predicate);
      if (result) return result;
    }
    return null;
  }

  function row(host) {
    return find(panel.loadedContent, item => item.modelData && item.modelData.host === host);
  }

  function hostSwitch(host) {
    return find(row(host), item => typeof item.toggled === "function");
  }

  function check(condition, message) {
    if (!condition) throw new Error(message);
  }

  Ssh.Panel {
    id: widget
    settings: ({polling: false})
  }
  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      try {
        if (!panel || !service) {
          for (var i = 0; i < widget.data.length; i++) {
            var child = widget.data[i];
            if (typeof child.ensureContent === "function") panel = child;
            if (typeof child.perform === "function") service = child;
          }
          panel.ensureContent();
          service.expanded = true;
          return;
        }
        if (!panel.loadedContent || !service.loaded || service.busy) return;
        var content = panel.loadedContent;
        if (phase === 0) {
          if (service.hosts[0].sessions === null) return;
          check(service.hosts[0].sessions === 2, "expanding after a collapsed poll fetches session counts");
          check(service.openCount === 2, "initial open count");
          check(hostSwitch("test-server").checked && !hostSwitch("direct-server").checked, "initial switch positions");
          check(!row("unknown-server").switchable && !row("unavailable-server").switchable, "uncertain states are not actionable");
          check(row("no-count").switchable && row("no-count").modelData.sessions === null, "unknown count does not block the switch");

          content.moveRequested(0, -1);
          content.moveRequested(-1, 0);
          content.activateRequested();
          check(widget.confirmingCloseAll && !service.busy, "bulk action needs confirmation");
          content.closeRequested();
          check(!widget.confirmingCloseAll && !service.busy, "Escape cancels confirmation");

          hostSwitch("test-server").toggled();
          check(service.busy && row("test-server").pending && hostSwitch("test-server").checked, "pending close preserves the checked state");
        } else if (phase === 1) {
          check(row("test-server").failure === "Simulated SSH error" && !service.actionError, "failure stays on its host");
          check(hostSwitch("test-server").checked, "failed close stays checked");
          hostSwitch("direct-server").toggled();
          check(service.busy && !hostSwitch("direct-server").checked, "pending open does not check the switch");
        } else if (phase === 2) {
          check(hostSwitch("direct-server").checked && row("direct-server").modelData.sessions === 0, "verified open with zero sessions");
          check(row("test-server").failure !== "", "other actions do not dismiss a host failure");
          service.refresh();
          hostSwitch("test-server").toggled();
          check(row("test-server").failure !== "", "retry keeps the error until it succeeds");
        } else if (phase === 3) {
          check(!hostSwitch("test-server").checked && row("test-server").failure === "", "successful retry clears the error");
          check(service.hosts[0].host === "test-server" && service.hosts[1].host === "direct-server", "rows keep their order");
          widget.showCloseAll();
          content.moveRequested(1, 0);
          content.activateRequested();
          check(service.busy && service.pendingAction === "close-all", "explicit bulk confirmation starts the action");
        } else {
          check(service.openCount === 0 && !widget.canCloseAll, "bulk close is verified and the header action is disabled");
          console.log("SSH_WIDGET_SMOKE_OK");
          Qt.quit();
        }
        phase++;
      } catch (error) {
        console.log("SSH_WIDGET_SMOKE_FAILED: " + error);
        Qt.quit();
      }
    }
  }
}
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
    actions = (helper.parent / "actions.log").read_text().splitlines()
    if actions != ["close test-server", "open direct-server", "close test-server", "close-all"]:
        raise SystemExit(f"Unexpected action sequence: {actions}")
