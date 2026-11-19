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
  property var hostActionErrors: ({})
  property bool loaded: false
  property string pendingHost: ""
  property string pendingAction: ""
  property bool verifyingAction: false
  property bool verificationPoll: false
  property bool pollIncludesSessions: false
  readonly property bool busy: pendingAction !== ""
  readonly property bool refreshing: poll.running
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/ssh-master").toString().replace(/^file:\/\//, ""))
  readonly property int openCount: hosts.filter(function(host) { return host.state === "open"; }).length

  function refresh() {
    if (busy || refreshing) return;
    startPoll(false);
  }

  function startPoll(verify) {
    verificationPoll = verify;
    pollIncludesSessions = expanded;
    poll.command = [helper, "status", "--json"].concat(pollIncludesSessions ? [] : ["--no-sessions"]);
    poll.running = true;
  }

  function verifyAction() {
    if (verifyingAction && !refreshing) startPoll(true);
  }

  function perform(command, host) {
    if (busy) return;
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
      // An already-running status check may have sampled the old state.
      if (root.busy && !root.verificationPoll) {
        Qt.callLater(root.verifyAction);
        return;
      }
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
      if (root.verificationPoll) {
        root.verificationPoll = false;
        root.verifyingAction = false;
        root.pendingAction = "";
        root.pendingHost = "";
      }
      if (root.expanded && !root.pollIncludesSessions) Qt.callLater(root.refresh);
    }
  }

  Process {
    id: action
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var error = exitCode === 0 ? "" : String(actionErr.text || actionOut.text).trim().slice(0, 2000) || "SSH operation failed";
      if (root.pendingHost) {
        var errors = Object.assign({}, root.hostActionErrors);
        if (error) errors[root.pendingHost] = error;
        else delete errors[root.pendingHost];
        root.hostActionErrors = errors;
      } else {
        root.actionError = error;
      }
      root.verifyingAction = true;
      Qt.callLater(root.verifyAction);
    }
  }
}
