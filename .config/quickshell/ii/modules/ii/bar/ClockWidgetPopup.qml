import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    padding: 12

    readonly property var pendingTodos: Todo.list.filter(item => !item.done)

    component Reveal: OpenReveal {
        open: root.shownInShared
        fromY: 10
        fromScale: 0.97
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 10

        ColumnLayout { // Time, date, uptime, todos
            id: infoColumn
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 210
            spacing: 10
            property Reveal reveal: Reveal { target: infoColumn }

            ColumnLayout {
                spacing: -2
                StyledText {
                    text: DateTime.time
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Qt.locale().toString(DateTime.clock.date, "dddd, d MMMM")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                }
            }

            Rectangle { // Uptime chip
                implicitWidth: uptimeRow.implicitWidth + 20
                implicitHeight: uptimeRow.implicitHeight + 10
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                RowLayout {
                    id: uptimeRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "timelapse"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Up %1").arg(DateTime.uptime)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            Rectangle { // Todos card
                Layout.fillWidth: true
                implicitHeight: todoColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: todoColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 10
                    }
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: "checklist"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("To Do")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            visible: root.pendingTodos.length > 0
                            text: root.pendingTodos.length
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        visible: root.pendingTodos.length === 0
                        text: Translation.tr("Nothing pending. Nice.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: root.pendingTodos.slice(0, 4)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.content
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    StyledText {
                        visible: root.pendingTodos.length > 4
                        text: Translation.tr("+ %1 more").arg(root.pendingTodos.length - 4)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Rectangle { // Calendar card
            id: calendarCard
            Layout.alignment: Qt.AlignTop
            implicitWidth: calendar.width + 16
            implicitHeight: calendar.implicitHeight + 6
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            property Reveal reveal: Reveal { target: calendarCard; delay: 60 }

            CalendarWidget {
                id: calendar
                anchors.centerIn: parent
                anchors.topMargin: 0
            }
        }
    }
}
