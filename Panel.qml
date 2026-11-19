import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
  id: root
  moduleName: "io.github.timrudorf.ssh"
  ipcTarget: "io.github.timrudorf.ssh"
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Commons.Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int refreshCursor: -1
  readonly property int closeAllCursor: -2
  readonly property bool canCloseAll: !ssh.busy && ssh.openCount > 0
  property int cursorIndex: 0
  property bool confirmingCloseAll: false
  property bool confirmSelected: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: {
    confirmingCloseAll = false;
    if (opened) {
      cursorIndex = 0;
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus(); });
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  Service {
    id: ssh
    expanded: root.opened
    polling: root.settings.polling !== false
  }

  function act(host) {
    if (!host || ssh.busy || confirmingCloseAll || (host.state !== "open" && host.state !== "closed")) return;
    ssh.perform(host.state === "open" ? "close" : "open", host.host);
  }

  function showCloseAll() {
    if (!canCloseAll) return;
    cursorIndex = closeAllCursor;
    confirmSelected = false;
    confirmingCloseAll = true;
  }

  function finishCloseAll(confirm) {
    confirmingCloseAll = false;
    if (confirm && canCloseAll) ssh.perform("close-all", "");
  }

  function refresh() {
    if (!confirmingCloseAll) ssh.refresh();
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰣀"
    labelText: !ssh.loaded ? "?" : Commons.I18n.formatNumber(ssh.openCount)
    slotSize: Style.space(48)
    dimmed: ssh.loaded && ssh.openCount === 0
    tooltipText: Model.plainTooltip(strings.t("title"))
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(650))

    content: PanelKeyCatcher {
      implicitHeight: header.implicitHeight + (hostList.implicitHeight > 0 ? layout.spacing + hostList.implicitHeight : 0)
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (root.confirmingCloseAll) {
          if (dx) root.confirmSelected = dx > 0 && root.canCloseAll;
          return;
        }
        if (root.cursorIndex < 0) {
          if (dx) root.cursorIndex = dx < 0 && root.canCloseAll ? root.closeAllCursor : root.refreshCursor;
          if (dy <= 0 || !ssh.hosts.length) return;
          root.cursorIndex = 0;
        } else {
          if ((!root.cursorIndex && dy < 0) || !ssh.hosts.length) {
            root.cursorIndex = root.refreshCursor;
            return;
          }
          root.cursorIndex = Math.max(0, Math.min(ssh.hosts.length - 1, root.cursorIndex + dy));
        }
        var item = rows.itemAt(root.cursorIndex);
        if (item) {
          var top = item.mapToItem(hostList, 0, 0).y;
          var bottom = top + item.height;
          if (top < flick.contentY) flick.contentY = top;
          else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.min(top, bottom - flick.height);
        }
      }
      onActivateRequested: {
        if (root.confirmingCloseAll) root.finishCloseAll(root.confirmSelected);
        else if (root.cursorIndex === root.closeAllCursor) root.showCloseAll();
        else if (root.cursorIndex === root.refreshCursor || !ssh.hosts.length) root.refresh();
        else root.act(ssh.hosts[root.cursorIndex]);
      }
      onCloseRequested: {
        if (root.confirmingCloseAll) root.finishCloseAll(false);
        else root.close();
      }
      onTabRequested: function(direction) {
        if (root.confirmingCloseAll) root.confirmSelected = !root.confirmSelected && root.canCloseAll;
        else root.switchPanel(direction);
      }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh(); }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: Style.space(6)

        Column {
          id: header
          Layout.fillWidth: true
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            PlainText {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              text: strings.t("title")
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
            }
            HeaderButton {
              text: strings.t(ssh.busy && ssh.pendingAction === "close-all" ? "closingAll" : "closeAll")
              hasCursor: !root.confirmingCloseAll && root.cursorIndex === root.closeAllCursor && enabled
              enabled: root.canCloseAll && !root.confirmingCloseAll
              onHovered: function(hovered) { if (hovered && enabled) root.cursorIndex = root.closeAllCursor; }
              onClicked: root.showCloseAll()
            }
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: Model.plainTooltip(strings.t("refresh"))
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: !root.confirmingCloseAll && root.cursorIndex === root.refreshCursor
              enabled: !ssh.busy && !ssh.refreshing && !root.confirmingCloseAll
              Accessible.role: Accessible.Button
              Accessible.name: strings.t("refresh")
              onHovered: function(hovered) { if (hovered && enabled) root.cursorIndex = root.refreshCursor; }
              onClicked: root.refresh()
            }
          }

          RowLayout {
            width: parent.width
            visible: root.confirmingCloseAll
            spacing: Style.space(6)

            PlainText {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              text: ssh.openCount > 0
                ? strings.tn("closePrompt", ssh.openCount).arg(Commons.I18n.formatNumber(ssh.openCount))
                : strings.t("nothingToClose")
              wrapMode: Text.Wrap
            }
            HeaderButton {
              text: strings.t("cancel")
              hasCursor: !root.confirmSelected || !root.canCloseAll
              onHovered: function(hovered) { if (hovered) root.confirmSelected = false; }
              onClicked: root.finishCloseAll(false)
            }
            HeaderButton {
              text: strings.t("close")
              foreground: Commons.Color.urgent
              enabled: root.canCloseAll
              hasCursor: root.confirmSelected && enabled
              onHovered: function(hovered) { if (hovered && enabled) root.confirmSelected = true; }
              onClicked: root.finishCloseAll(true)
            }
          }

          FeedbackText {
            width: parent.width
            visible: ssh.error !== ""
            text: strings.t("pollError")
            details: ssh.error
          }
          FeedbackText {
            width: parent.width
            visible: ssh.actionError !== ""
            text: strings.t("bulkError")
            details: ssh.actionError
          }

          PanelSeparator { foreground: root.foreground }
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: hostList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

          Column {
            id: hostList
            width: Math.max(0, flick.width - Style.space(8))
            spacing: Style.space(2)

            Repeater {
              id: rows
              model: ssh.hosts
              delegate: CursorSurface {
                id: hostRow
                required property var modelData
                required property int index
                readonly property bool isOpen: modelData.state === "open"
                readonly property bool switchable: isOpen || modelData.state === "closed"
                readonly property bool pending: ssh.busy && ssh.pendingHost === modelData.host
                readonly property string failure: ssh.hostActionErrors[modelData.host] || ""
                width: hostList.width
                implicitHeight: hostContent.implicitHeight + Style.space(6)
                hasCursor: !root.confirmingCloseAll && root.cursorIndex === index
                foreground: root.foreground

                HoverHandler {
                  onHoveredChanged: if (hovered && !root.confirmingCloseAll) root.cursorIndex = hostRow.index
                }

                ColumnLayout {
                  id: hostContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  spacing: Style.space(2)

                  RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: Style.space(34)
                    spacing: Style.space(8)

                    PlainText {
                      Layout.fillWidth: true
                      Layout.minimumWidth: 0
                      Layout.maximumWidth: implicitWidth
                      text: hostRow.modelData.host
                      font.bold: true
                      elide: Text.ElideRight

                      HoverHandler { id: aliasHover }
                      DetailsTip {
                        visible: aliasHover.hovered
                        text: (hostRow.modelData.aliases.length > 1 ? hostRow.modelData.aliases.join(" / ") : hostRow.modelData.host)
                          + "\n" + strings.t(hostRow.modelData.policy === "master-only" ? "masterOnly"
                            : hostRow.modelData.policy === "direct" ? "direct" : "mixed")
                      }
                    }
                    PlainText {
                      visible: hostRow.isOpen && hostRow.modelData.sessions !== null
                      text: visible
                        ? strings.tn("sessions", hostRow.modelData.sessions).arg(Commons.I18n.formatNumber(hostRow.modelData.sessions))
                        : ""
                      color: root.dim
                      font.pixelSize: Style.font.caption
                    }
                    Item {
                      Layout.fillWidth: true
                      Layout.preferredWidth: 0
                    }
                    PlainText {
                      visible: hostRow.pending
                      text: strings.t(ssh.verifyingAction ? "checking" : ssh.pendingAction === "open" ? "opening" : "closing")
                      color: root.dim
                      font.pixelSize: Style.font.caption
                    }
                    ToggleSwitch {
                      id: hostSwitch
                      visible: hostRow.switchable
                      checked: hostRow.isOpen
                      foreground: checked ? Commons.Color.accent : root.foreground
                      busy: ssh.busy || root.confirmingCloseAll
                      trackHeight: Style.space(20)
                      onToggled: root.act(hostRow.modelData)
                      Accessible.role: Accessible.CheckBox
                      Accessible.name: strings.t("masterFor").arg(hostRow.modelData.host)
                      Accessible.checkable: true
                      Accessible.checked: checked
                      Accessible.description: checked ? strings.t("closedHint") : strings.t("openMaster")
                      Accessible.onPressAction: root.act(hostRow.modelData)

                      DetailsTip {
                        visible: hostSwitch.visible && hostSwitch.containsMouse
                        text: hostRow.pending && !ssh.verifyingAction && ssh.pendingAction === "open"
                          ? strings.t("openingHint")
                          : hostSwitch.checked ? strings.t("closedHint") : strings.t("openMaster")
                      }
                    }
                    PlainText {
                      visible: !hostRow.switchable
                      text: strings.t(hostRow.modelData.state === "unknown" ? "unknownState" : "unavailableState")
                      color: root.dim
                      font.pixelSize: Style.font.caption
                      rightPadding: Style.space(6)
                      Accessible.description: hostRow.modelData.error

                      HoverHandler { id: statusHover }
                      DetailsTip {
                        visible: statusHover.hovered && hostRow.modelData.error !== ""
                        text: hostRow.modelData.error
                      }
                    }
                  }
                  FeedbackText {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Style.space(4)
                    visible: hostRow.failure !== ""
                    text: strings.t("actionError")
                    details: hostRow.failure
                  }
                }
              }
            }
            PlainText {
              visible: !ssh.hosts.length && (ssh.loaded || !ssh.error)
              width: parent.width
              text: strings.t(ssh.loaded ? "empty" : "loading")
              wrapMode: Text.Wrap
              color: root.dim
            }
          }
        }
      }
    }
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component HeaderButton: Button {
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(5)
    opacity: enabled ? 1 : 0.5
    Accessible.role: Accessible.Button
    Accessible.name: text
  }

  component DetailsTip: PanelToolTip {
    fontFamily: root.fontFamily
    width: Math.min(implicitWidth, Style.space(320))
  }

  component FeedbackText: PlainText {
    id: feedback
    property string details: ""
    color: Commons.Color.urgent
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
    Accessible.description: details

    HoverHandler { id: feedbackHover }
    DetailsTip {
      visible: feedbackHover.hovered && feedback.details !== ""
      text: feedback.details
    }
  }
}
