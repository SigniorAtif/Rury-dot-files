pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.rury.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts

/** One transcript entry: picks the right look for user / assistant / tool / notice / summary items. */
Item {
    id: root
    required property var item
    readonly property string type: item?.type ?? ""

    implicitHeight: loader.item?.implicitHeight ?? 0
    visible: implicitHeight > 0

    Loader {
        id: loader
        width: parent.width
        sourceComponent: root.type === "user" ? userComp : root.type === "assistant" ? assistantComp
            : root.type === "tool" ? toolComp : root.type === "notice" ? noticeComp
            : root.type === "summary" ? summaryComp : null
    }

    Component {
        id: toolComp
        AgentToolCard {
            item: root.item
            width: loader.width
        }
    }

    Component {
        id: userComp
        Item {
            implicitHeight: bubble.implicitHeight
            Rectangle {
                id: bubble
                anchors.right: parent.right
                width: Math.min(parent.width * 0.86, userCol.implicitWidth + 24)
                implicitHeight: userCol.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer
                ColumnLayout {
                    id: userCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; leftMargin: 12; rightMargin: 12 }
                    spacing: 6
                    Flow {
                        visible: (root.item?.images ?? []).length > 0
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.item?.images ?? []
                            delegate: Image {
                                required property string modelData
                                width: 96
                                height: 64
                                fillMode: Image.PreserveAspectCrop
                                source: "file://" + modelData
                                asynchronous: true
                                sourceSize.width: 192
                            }
                        }
                    }
                    TextEdit {
                        Layout.fillWidth: true
                        Layout.maximumWidth: root.width * 0.86 - 24
                        readOnly: true
                        selectByMouse: true
                        text: root.item?.text ?? ""
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colPrimaryContainer
                    }
                }
            }
        }
    }

    Component {
        id: assistantComp
        ColumnLayout {
            id: asst
            spacing: 6
            readonly property string text: root.item?.text ?? ""
            readonly property string thinking: root.item?.thinking ?? ""
            readonly property bool streaming: root.item?.streaming ?? false
            readonly property var blocks: StringUtils.splitMarkdownBlocks(asst.text)
            // what MessageTextBlock/MessageCodeBlock expect from a message
            QtObject {
                id: md
                property bool done: !asst.streaming
                property bool thinking: false
                property bool functionPending: false
                property string content: asst.text
            }
            implicitHeight: (text.length > 0 || thinking.length > 0 || (streaming && (root.item?.calls ?? []).length === 0))
                ? childrenRect.height : 0

            Rectangle { // thinking, collapsed to one line
                visible: asst.thinking.length > 0
                Layout.fillWidth: true
                implicitHeight: thinkCol.implicitHeight + 10
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                property bool open: false
                ColumnLayout {
                    id: thinkCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5; leftMargin: 10; rightMargin: 10 }
                    RowLayout {
                        spacing: 6
                        MaterialSymbol { text: "neurology"; iconSize: 16; color: Appearance.colors.colSubtext }
                        StyledText {
                            Layout.fillWidth: true
                            text: asst.streaming && asst.text.length === 0 ? "Thinking…" : "Thought"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        MaterialSymbol {
                            text: thinkCol.parent.open ? "expand_less" : "expand_more"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        visible: thinkCol.parent.open
                        Layout.fillWidth: true
                        text: asst.thinking
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.open = !parent.open
                }
            }

            Repeater {
                model: asst.blocks
                delegate: Loader {
                    id: blockLoader
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData.type === "code" ? codeBlock : textBlock
                    Component {
                        id: textBlock
                        MessageTextBlock {
                            segmentContent: blockLoader.modelData.content
                            messageData: md
                            done: md.done
                            enableMouseSelection: true
                            forceDisableChunkSplitting: true
                        }
                    }
                    Component {
                        id: codeBlock
                        MessageCodeBlock {
                            segmentContent: blockLoader.modelData.content
                            segmentLang: blockLoader.modelData.lang ?? "txt"
                            messageData: md
                            enableMouseSelection: true
                        }
                    }
                }
            }

            Row { // waiting for the first token
                visible: asst.streaming && asst.text.length === 0 && asst.thinking.length === 0
                spacing: 5
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: 7
                        height: 7
                        radius: 4
                        color: Appearance.colors.colSubtext
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { from: 0.25; to: 1; duration: 380 }
                            NumberAnimation { from: 1; to: 0.25; duration: 380 }
                            PauseAnimation { duration: (2 - index) * 160 }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: noticeComp
        Item {
            implicitHeight: pill.implicitHeight
            readonly property string level: root.item?.level ?? "info"
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, noticeRow.implicitWidth + 20)
                implicitHeight: noticeRow.implicitHeight + 10
                radius: Appearance.rounding.full
                color: parent.level === "error" ? Appearance.colors.colErrorContainer
                    : parent.level === "warn" ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
                RowLayout {
                    id: noticeRow
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, pill.parent.width - 20)
                    spacing: 6
                    MaterialSymbol {
                        text: pill.parent.level === "error" ? "error" : pill.parent.level === "warn" ? "warning" : "info"
                        iconSize: 15
                        color: pill.parent.level === "error" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.item?.text ?? ""
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: pill.parent.level === "error" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    Component {
        id: summaryComp
        Rectangle {
            implicitHeight: sumCol.implicitHeight + 12
            radius: Appearance.rounding.small
            color: "transparent"
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            property bool open: false
            ColumnLayout {
                id: sumCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6; leftMargin: 10; rightMargin: 10 }
                RowLayout {
                    MaterialSymbol { text: "compress"; iconSize: 16; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Earlier conversation compacted"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    visible: sumCol.parent.open
                    Layout.fillWidth: true
                    text: root.item?.text ?? ""
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.open = !parent.open
            }
        }
    }
}
