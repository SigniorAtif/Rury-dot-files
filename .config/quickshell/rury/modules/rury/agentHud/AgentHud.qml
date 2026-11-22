pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.rury.sidebarLeft.agentChat
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Side panel next to the agent desk viewer (special:agent, Super+Shift+/): what the agent is doing,
 * its checklist, its last few actions, any approval it waits on, and Stop / Take over / Hide.
 */
Scope {
    id: root

    readonly property var monitor: HyprlandData.monitors.find(m => m.specialWorkspace?.name === "special:agent") ?? null
    readonly property bool shown: monitor !== null && Config.options.agent.enable
    onShownChanged: {
        Agent.hudVisible = shown;
        if (shown) Agent.ensure();
    }

    // the last few tool calls, newest last
    readonly property var recent: {
        const out = [];
        const ids = Agent.itemIds;
        for (let i = ids.length - 1; i >= 0 && out.length < 7; i--) {
            const it = Agent.itemById[ids[i]];
            if (it?.type === "tool") out.unshift(it);
        }
        return out;
    }

    Loader {
        active: root.shown
        sourceComponent: PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.monitor?.name) ?? null
            color: "transparent"
            WlrLayershell.namespace: "quickshell:agentHud"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: Agent.pending.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors { top: true; bottom: true; right: true }
            margins {
                top: Appearance.sizes.barHeight + 8
                bottom: 16
                right: 16
            }
            implicitWidth: 344 + Appearance.sizes.elevationMargin * 2
            mask: Region { item: card }

            StyledRectangularShadow { target: card }

            Rectangle {
                id: card
                anchors {
                    right: parent.right
                    rightMargin: Appearance.sizes.elevationMargin
                    verticalCenter: parent.verticalCenter
                }
                width: 344
                height: Math.min(parent.height - Appearance.sizes.elevationMargin * 2, col.implicitHeight + 24)
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border ?? Appearance.colors.colOutlineVariant
                clip: true

                Flickable {
                    anchors { fill: parent; margins: 12 }
                    contentHeight: col.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: col
                        width: parent.width
                        spacing: 10

                        // ---- who / what ----
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            MaterialShapeWrappedMaterialSymbol {
                                text: "smart_toy"
                                iconSize: 22
                                padding: 8
                                shape: MaterialShape.Shape.Cookie7Sided
                                color: Agent.running ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                                colSymbol: Agent.running ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                RotationAnimation on rotation {
                                    running: Agent.running && Agent.status !== "waiting"
                                    loops: Animation.Infinite
                                    from: 0; to: 360
                                    duration: 9000
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: "SigniorAtif Agent"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Agent.session?.title || (Agent.running ? "Working" : "Idle, give it a task in the sidebar")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            Rectangle { // mode
                                implicitWidth: modeText.implicitWidth + 14
                                implicitHeight: 22
                                radius: Appearance.rounding.full
                                color: Agent.mode === "auto" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                                StyledText {
                                    id: modeText
                                    anchors.centerIn: parent
                                    text: Agent.modeInfo[Agent.mode]?.label ?? Agent.mode
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Agent.mode === "auto" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }

                        AgentStatusLine {
                            Layout.fillWidth: true
                            visible: Agent.running
                        }

                        Rectangle { // what it just did on the desk
                            visible: Agent.deskLastAction.length > 0
                            Layout.fillWidth: true
                            implicitHeight: nowRow.implicitHeight + 12
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                            RowLayout {
                                id: nowRow
                                anchors { fill: parent; margins: 6; leftMargin: 10 }
                                spacing: 8
                                MaterialSymbol { text: "mouse"; iconSize: 16; color: Appearance.colors.colPrimary }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: Agent.deskLastAction
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        Repeater {
                            model: Agent.pending
                            delegate: AgentPendingCard {
                                required property var modelData
                                Layout.fillWidth: true
                                pending: modelData
                            }
                        }

                        AgentTodoPanel {
                            Layout.fillWidth: true
                        }

                        // ---- recent actions ----
                        StyledText {
                            visible: root.recent.length > 0
                            text: "Recent"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        Repeater {
                            model: root.recent
                            delegate: RowLayout {
                                id: act
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                readonly property string st: modelData?.status ?? ""
                                Item {
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: act.st !== "running"
                                        text: act.st === "ok" ? "check" : act.st === "cancelled" ? "stop" : act.st === "" ? "more_horiz" : "close"
                                        iconSize: 16
                                        color: act.st === "ok" || act.st === "" ? Appearance.colors.colSubtext : Appearance.colors.colError
                                    }
                                    MaterialLoadingIndicator {
                                        anchors.centerIn: parent
                                        visible: act.st === "running"
                                        loading: visible
                                        implicitSize: 18
                                    }
                                }
                                StyledText {
                                    text: (act.modelData?.name ?? "").replace(/^mcp__\w+?__/, "").replace(/^desk_/, "").replace(/_/g, " ")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: act.modelData?.summary ?? ""
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        // ---- controls ----
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 6
                            HudButton {
                                visible: Agent.running
                                symbol: "stop"
                                label: "Stop"
                                danger: true
                                onClicked: Agent.stop()
                            }
                            HudButton {
                                symbol: Agent.deskControl ? "visibility" : "back_hand"
                                label: Agent.deskControl ? "View only" : "Take over"
                                tip: Agent.deskControl ? "Give the desk back to the agent" : "Use the desk with your own mouse and keyboard (stops the agent's run). Ctrl+Alt+M in the viewer opens its menu."
                                onClicked: {
                                    if (!Agent.deskControl && Agent.running) Agent.stop();
                                    Agent.deskView(!Agent.deskControl);
                                }
                            }
                            Item { Layout.fillWidth: true }
                            HudButton {
                                symbol: "close_fullscreen"
                                label: "Hide"
                                tip: "Super+Shift+/"
                                onClicked: Agent.deskView()
                            }
                        }
                    }
                }
            }
        }
    }

    component HudButton: RippleButton {
        id: hb
        property string symbol
        property string label
        property string tip
        property bool danger: false
        implicitHeight: 32
        implicitWidth: hbRow.implicitWidth + 18
        buttonRadius: Appearance.rounding.full
        colBackground: danger ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
        colBackgroundHover: danger ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2Hover
        contentItem: RowLayout {
            id: hbRow
            spacing: 5
            MaterialSymbol {
                text: hb.symbol
                iconSize: 17
                fill: 1
                color: hb.danger ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: hb.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: hb.danger ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
        }
        StyledToolTip { text: hb.tip; extraVisibleCondition: hb.tip.length > 0 }
    }
}
