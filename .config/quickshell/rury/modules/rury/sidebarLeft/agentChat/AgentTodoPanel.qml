pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/** The agent's checklist (todo_write), pinned above the input while there is one. Collapses to a progress line. */
Rectangle {
    id: root
    property var todos: Agent.todos
    property bool expanded: true
    readonly property int doneCount: todos.filter(t => t.status === "completed").length
    readonly property var current: todos.find(t => t.status === "in_progress") ?? null

    visible: todos.length > 0
    implicitHeight: visible ? col.implicitHeight + 12 : 0
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6; leftMargin: 10; rightMargin: 8 }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol { text: "checklist"; iconSize: 16; color: Appearance.colors.colPrimary }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
                text: root.expanded || !root.current ? `Tasks ${root.doneCount}/${root.todos.length}`
                    : `${root.doneCount}/${root.todos.length} · ${root.current.content}`
            }
            Rectangle { // progress
                implicitWidth: 48
                implicitHeight: 4
                radius: 2
                color: Appearance.colors.colLayer3
                Rectangle {
                    width: parent.width * (root.todos.length ? root.doneCount / root.todos.length : 0)
                    height: parent.height
                    radius: 2
                    color: Appearance.colors.colPrimary
                    Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
            }
            MaterialSymbol {
                text: root.expanded ? "expand_more" : "expand_less"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }
        }

        Repeater {
            model: root.expanded ? root.todos : []
            delegate: RowLayout {
                id: todoRow
                required property var modelData
                readonly property string st: modelData.status
                Layout.fillWidth: true
                spacing: 8
                Item {
                    implicitWidth: 16
                    implicitHeight: 16
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: todoRow.st !== "in_progress"
                        text: todoRow.st === "completed" ? "check_circle" : "radio_button_unchecked"
                        fill: todoRow.st === "completed" ? 1 : 0
                        iconSize: 16
                        color: todoRow.st === "completed" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    MaterialLoadingIndicator {
                        anchors.centerIn: parent
                        visible: todoRow.st === "in_progress"
                        loading: visible && Agent.running
                        implicitSize: 18
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: todoRow.modelData.content
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.strikeout: todoRow.st === "completed"
                    color: todoRow.st === "completed" ? Appearance.colors.colSubtext
                        : todoRow.st === "in_progress" ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer2
                    font.weight: todoRow.st === "in_progress" ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    MouseArea {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 28
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }
}
