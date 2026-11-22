pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One tool call: a compact line (icon, name, what it touched, status) that opens up to show the output,
 * a coloured diff for file edits, and screenshots.
 */
Rectangle {
    id: root
    required property var item           // the Agent item QtObject (type "tool")
    property bool expanded: false

    readonly property string toolName: item?.name ?? ""
    readonly property bool isMcp: toolName.startsWith("mcp__")
    readonly property string status: item?.status ?? ""
    readonly property bool running: status === "running"
    readonly property bool failed: status === "error" || status === "denied" || status === "blocked"
    readonly property string diff: item?.meta?.diff ?? ""
    readonly property var images: item?.images ?? []
    readonly property bool expandable: (item?.output ?? "").length > 0 || diff.length > 0 || images.length > 0

    readonly property var labels: ({
        "bash": ["terminal", "Bash"], "read_file": ["description", "Read"], "write_file": ["edit_document", "Write"],
        "edit_file": ["edit", "Edit"], "glob": ["folder_open", "Find"], "grep": ["search", "Search"],
        "web_fetch": ["language", "Fetch"], "web_search": ["travel_explore", "Web search"],
        "desk_screenshot": ["screenshot_monitor", "Look"], "desk_zoom": ["zoom_in", "Zoom"],
        "desk_windows": ["select_window", "Windows"], "desk_click": ["mouse", "Click"],
        "desk_move": ["arrow_selector_tool", "Hover"], "desk_drag": ["drag_pan", "Drag"],
        "desk_scroll": ["swap_vert", "Scroll"], "desk_type": ["keyboard", "Type"], "desk_key": ["keyboard_command_key", "Keys"],
        "desk_launch": ["open_in_new", "Launch"], "desk_focus": ["filter_center_focus", "Focus"],
        "desk_close": ["close", "Close window"], "todo_write": ["checklist", "Plan"], "ask_user": ["help", "Question"],
        "exit_plan": ["map", "Plan ready"], "skill": ["auto_awesome", "Skill"], "tool_search": ["extension", "Load tools"],
        "remember": ["bookmark", "Remember"], "schedule": ["schedule", "Schedule"], "notify": ["notifications", "Notify"]
    })
    readonly property string icon: isMcp ? "extension" : (labels[toolName]?.[0] ?? "build")
    readonly property string label: {
        if (isMcp) {
            const parts = toolName.split("__");
            return `${parts[1]} · ${(parts[2] ?? "").replace(/^browser_/, "").replace(/_/g, " ")}`;
        }
        return labels[toolName]?.[1] ?? toolName;
    }

    implicitHeight: column.implicitHeight + 12
    radius: Appearance.rounding.small
    color: failed ? Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.08)
                  : Appearance.colors.colLayer2
    border.width: running ? 1 : 0
    border.color: Appearance.colors.colPrimary

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 6
        }
        spacing: 6

        RowLayout { // the summary line
            Layout.fillWidth: true
            spacing: 8

            Item {
                implicitWidth: 22
                implicitHeight: 22
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.running
                    text: root.icon
                    iconSize: 18
                    color: root.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                }
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.running
                    loading: root.running
                    implicitSize: 22
                }
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: root.item?.summary ?? ""
                elide: Text.ElideMiddle
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                visible: !root.running
                text: root.status === "ok" ? "check" : root.status === "denied" ? "block"
                    : root.status === "blocked" ? "do_not_disturb_on" : root.status === "cancelled" ? "stop" : "error"
                iconSize: 16
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                visible: root.expandable
                text: root.expanded ? "expand_less" : "expand_more"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }

        // why it didn't run, shown without expanding
        StyledText {
            visible: root.failed && !root.expanded && (root.item?.output ?? "").length > 0
            Layout.fillWidth: true
            text: (root.item?.output ?? "").split("\n")[0]
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        Flow { // screenshots stay visible even when collapsed
            visible: root.images.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.images
                delegate: Rectangle {
                    required property string modelData
                    width: Math.min(column.width, 320)
                    height: width * 0.625
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer3
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: "file://" + parent.modelData
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        sourceSize.width: 640
                    }
                }
            }
        }

        Loader { // diff for file edits
            active: root.expanded && root.diff.length > 0
            visible: active
            Layout.fillWidth: true
            sourceComponent: Rectangle {
                implicitHeight: diffCol.implicitHeight + 10
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1
                Column {
                    id: diffCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
                    Repeater {
                        model: root.diff.split("\n").slice(2, 200)
                        delegate: Rectangle {
                            required property string modelData
                            width: diffCol.width
                            implicitHeight: lineText.implicitHeight
                            color: modelData.startsWith("+") ? Qt.rgba(0.3, 0.75, 0.4, 0.16)
                                 : modelData.startsWith("-") ? Qt.rgba(0.9, 0.3, 0.3, 0.16) : "transparent"
                            StyledText {
                                id: lineText
                                width: parent.width
                                text: parent.modelData
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAnywhere
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                color: parent.modelData.startsWith("@@") ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        Loader { // raw output
            active: root.expanded && root.diff.length === 0 && (root.item?.output ?? "").length > 0
            visible: active
            Layout.fillWidth: true
            sourceComponent: Rectangle {
                implicitHeight: Math.min(outText.implicitHeight + 12, 320)
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1
                clip: true
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 6
                    contentHeight: outText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: outText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        text: root.item?.output ?? ""
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest + 1
                        color: Appearance.colors.colOnLayer1
                        selectionColor: Appearance.colors.colPrimaryContainer
                    }
                }
            }
        }
    }

    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 34
        enabled: root.expandable
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expanded = !root.expanded
    }
}
