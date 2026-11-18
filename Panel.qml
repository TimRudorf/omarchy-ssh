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
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int cursorIndex: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: if (opened) {
    cursorIndex = 0;
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus(); });
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  Service {
    id: ssh
    expanded: root.opened
    polling: root.settings.polling !== false
  }

  function act(host) {
    if (!host || ssh.busy || (host.state !== "open" && host.state !== "closed")) return;
    ssh.perform(host.state === "open" ? "close" : "open", host.host);
  }

  function stateText(host) {
    if (host.state === "open")
      return strings.t("openState") + " · " + (host.sessions === null ? strings.t("unknownCount")
        : strings.tn("sessions", host.sessions).arg(Commons.I18n.formatNumber(host.sessions)));
    if (host.state === "closed") return strings.t("closedState");
    return strings.t(host.state === "unknown" ? "unknownState" : "unavailableState");
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(650))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.cursorIndex = Math.max(0, Math.min(ssh.hosts.length - 1, root.cursorIndex + dy));
        var item = rows.itemAt(root.cursorIndex);
        if (item) {
          var top = item.mapToItem(column, 0, 0).y;
          flick.contentY = Math.max(0, Math.min(top - Style.space(80), flick.contentHeight - flick.height));
        }
      }
      onActivateRequested: root.act(ssh.hosts[root.cursorIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction); }
      onTextKey: function(text) { if (text === "r" || text === "R") ssh.refresh(); }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          RowLayout {
            width: parent.width
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(3)
              PlainText {
                text: strings.t("title")
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              PlainText {
                text: ssh.loaded ? strings.tn("summary", ssh.openCount).arg(Commons.I18n.formatNumber(ssh.openCount)) : strings.t("loading")
                color: root.dim
              }
            }
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: Model.plainTooltip(strings.t("refresh"))
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              enabled: !ssh.refreshing
              onClicked: ssh.refresh()
            }
          }

          PlainText {
            width: parent.width
            visible: ssh.busy || ssh.actionError !== "" || ssh.error !== ""
            wrapMode: Text.WordWrap
            color: ssh.actionError !== "" || ssh.error !== "" ? Commons.Color.urgent : root.foreground
            text: ssh.busy ? strings.t(ssh.pendingAction === "open" ? "opening" : "working")
              : ssh.actionError !== "" ? strings.t("actionError") + "\n" + ssh.actionError
              : strings.t("pollError") + "\n" + ssh.error
          }

          PanelSeparator { foreground: root.foreground }

          Repeater {
            id: rows
            model: ssh.hosts
            delegate: CursorSurface {
              id: hostRow
              required property var modelData
              required property int index
              width: column.width
              implicitHeight: hostContent.implicitHeight + Style.space(20)
              hasCursor: root.cursorIndex === index
              foreground: root.foreground

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.cursorIndex = hostRow.index
              }

              RowLayout {
                id: hostContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(12)

                Rectangle {
                  implicitWidth: Style.space(6)
                  implicitHeight: implicitWidth
                  radius: implicitWidth / 2
                  color: hostRow.modelData.state === "open" ? Commons.Color.accent : root.dim
                  opacity: hostRow.modelData.state === "closed" ? 0.4 : 1
                  Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(3)
                  PlainText {
                    Layout.fillWidth: true
                    text: hostRow.modelData.aliases.join(" / ")
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  PlainText {
                    Layout.fillWidth: true
                    text: root.stateText(hostRow.modelData)
                    color: hostRow.modelData.state === "open" ? root.foreground : root.dim
                  }
                  PlainText {
                    Layout.fillWidth: true
                    text: strings.t(hostRow.modelData.policy === "master-only" ? "masterOnly" : hostRow.modelData.policy === "direct" ? "direct" : "mixed")
                    color: root.dim
                    font.pixelSize: Style.font.caption
                  }
                  PlainText {
                    Layout.fillWidth: true
                    visible: hostRow.modelData.error !== ""
                    text: hostRow.modelData.error
                    color: Commons.Color.urgent
                    wrapMode: Text.WordWrap
                    font.pixelSize: Style.font.caption
                  }
                }
                Button {
                  text: strings.t(hostRow.modelData.state === "open" ? "close" : "open")
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  focusable: true
                  bordered: true
                  enabled: !ssh.busy && (hostRow.modelData.state === "open" || hostRow.modelData.state === "closed")
                  onClicked: root.act(hostRow.modelData)
                }
              }
            }
          }

          PlainText {
            visible: ssh.loaded && ssh.hosts.length === 0
            width: parent.width
            text: strings.t("empty")
            wrapMode: Text.WordWrap
            color: root.dim
          }

          Button {
            width: parent.width
            text: strings.t("closeAll")
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            focusable: true
            enabled: !ssh.busy && ssh.openCount > 0
            onClicked: ssh.perform("close-all", "")
          }
          PlainText {
            width: parent.width
            text: strings.t("closedHint") + "\n\n" + strings.t("countHint")
            color: root.dim
            wrapMode: Text.WordWrap
            font.pixelSize: Style.font.caption
          }
          PlainText {
            width: parent.width
            text: strings.t(ssh.polling ? "pollingOn" : "pollingOff")
            color: root.dim
            wrapMode: Text.WordWrap
            font.pixelSize: Style.font.caption
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
}
