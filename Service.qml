import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  property bool expanded: false
  property bool polling: true
  property var hosts: []
  property string error: ""
  property string actionError: ""
  property bool loaded: false
  property string pendingHost: ""
  property string pendingAction: ""
  readonly property bool busy: action.running
  readonly property bool refreshing: poll.running
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/ssh-master").toString().replace(/^file:\/\//, ""))
  readonly property int openCount: hosts.filter(function(host) { return host.state === "open"; }).length

  function refresh() {
    if (poll.running) return;
    poll.command = [helper, "status", "--json"].concat(expanded ? [] : ["--no-sessions"]);
    poll.running = true;
  }

  function perform(command, host) {
    if (busy) return;
    actionError = "";
    pendingAction = command;
    pendingHost = host || "";
    action.command = [helper, command].concat(host ? [host] : []);
    action.running = true;
  }

  onExpandedChanged: refresh()
  Component.onCompleted: refresh()

  Timer {
    interval: root.expanded ? 3000 : 10000
    running: root.polling
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: poll
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var result = Model.parse(statusOut.text);
        root.hosts = result.hosts;
        root.error = result.errors.join("\n");
        root.loaded = true;
      } catch (error) {
        root.error = String(statusErr.text || error).slice(0, 2000);
        root.loaded = false;
        root.hosts = [];
      }
    }
  }

  Process {
    id: action
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionError = exitCode === 0 ? "" : String(actionErr.text || actionOut.text || "SSH operation failed").slice(0, 2000);
      root.pendingHost = "";
      root.pendingAction = "";
      root.refresh();
    }
  }
}
