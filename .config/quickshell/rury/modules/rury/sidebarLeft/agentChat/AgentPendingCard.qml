pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.rury.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Something the agent is waiting on: a permission (approval), a question, or a plan to approve.
 * Number keys pick the numbered choices; the note field turns a "no" into guidance.
 */
Rectangle {
    id: root
    required property var pending
    readonly property string kind: pending?.kind ?? ""
    readonly property bool risky: pending?.risky ?? false
    readonly property bool hasRule: (pending?.rule ?? "").length > 0

    // [label, icon, answer] in number-key order
    readonly property var choices: {
        if (kind === "approval") {
            return [
                ["Allow once", "check", { "decision": "allow" }],
                ...(hasRule ? [["Allow for this session", "done_all", { "decision": "session" }],
                               ["Always allow", "verified", { "decision": "save" }]] : []),
                ["Deny", "block", { "decision": "deny" }]
            ];
        }
        if (kind === "plan") {
            return [
                ["Approve, run on its own", "bolt", { "decision": "auto" }],
                ["Approve, ask before changes", "front_hand", { "decision": "ask" }],
                ["Keep planning", "edit_note", { "decision": "keep" }]
            ];
        }
        return (pending?.options ?? []).map(o => [o, "", { "answer": o }]);
    }

    function choose(i) {
        const c = root.choices[i];
        if (!c) return false;
        const ans = Object.assign({}, c[2]);
        const note = noteField.text.trim();
        if (note.length > 0) {
            if (root.kind === "question") ans.answer = `${ans.answer} (${note})`;
            else ans.note = note;
        }
        Agent.answer(root.pending.rid, ans);
        return true;
    }

    function submitNote() {
        const note = noteField.text.trim();
        if (root.kind === "question") {
            if (note.length > 0) Agent.answer(root.pending.rid, { "answer": note });
            return;
        }
        // a note on its own means "no, do this instead"
        Agent.answer(root.pending.rid, { "decision": root.kind === "plan" ? "keep" : "deny", "note": note });
    }

    function focusNote() { noteField.forceActiveFocus(); }

    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: risky ? Appearance.colors.colError : Appearance.colors.colPrimary

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12; rightMargin: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: root.kind === "plan" ? "map" : root.kind === "question" ? "help" : root.risky ? "warning" : "front_hand"
                iconSize: 20
                fill: 1
                color: root.risky ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.kind === "plan" ? "Plan ready for review"
                    : root.kind === "question" ? (root.pending?.question ?? "")
                    : (root.risky ? "Risky: " : "Allow ") + (root.pending?.tool ?? "") + (root.risky ? "" : "?")
            }
        }

        StyledText { // why it is asking
            visible: root.kind === "approval" && (root.pending?.reason ?? "").length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.pending?.reason ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.risky ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        Rectangle { // the exact command / target
            visible: root.kind === "approval" && (root.pending?.summary ?? "").length > 0
            Layout.fillWidth: true
            implicitHeight: Math.min(cmdText.implicitHeight + 12, 180)
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer1
            clip: true
            Flickable {
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: cmdText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: cmdText
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAnywhere
                    text: {
                        const a = root.pending?.args ?? {};
                        return a.command ?? (root.pending?.summary ?? "");
                    }
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    selectionColor: Appearance.colors.colPrimaryContainer
                }
            }
        }

        Rectangle { // the plan
            visible: root.kind === "plan"
            Layout.fillWidth: true
            implicitHeight: Math.min(planCol.implicitHeight + 12, 360)
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer1
            clip: true
            QtObject {
                id: planMd
                property bool done: true
                property bool thinking: false
                property bool functionPending: false
                property string content: root.pending?.plan ?? ""
            }
            Flickable {
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: planCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: planCol
                    width: parent.width
                    Repeater {
                        model: root.kind === "plan" ? StringUtils.splitMarkdownBlocks(root.pending?.plan ?? "") : []
                        delegate: Loader {
                            id: planBlock
                            required property var modelData
                            Layout.fillWidth: true
                            sourceComponent: modelData.type === "code" ? planCode : planText
                            Component {
                                id: planText
                                MessageTextBlock {
                                    segmentContent: planBlock.modelData.content
                                    messageData: planMd
                                    enableMouseSelection: true
                                    forceDisableChunkSplitting: true
                                }
                            }
                            Component {
                                id: planCode
                                MessageCodeBlock {
                                    segmentContent: planBlock.modelData.content
                                    segmentLang: planBlock.modelData.lang ?? "txt"
                                    messageData: planMd
                                    enableMouseSelection: true
                                }
                            }
                        }
                    }
                }
            }
        }

        Flow { // choices
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.choices
                delegate: RippleButton {
                    id: choiceBtn
                    required property var modelData
                    required property int index
                    readonly property bool primary: index === 0
                    readonly property bool negative: (modelData[2].decision ?? "") === "deny"
                    implicitHeight: 32
                    implicitWidth: choiceRow.implicitWidth + 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: primary ? (root.risky ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer)
                        : Appearance.colors.colLayer3
                    colBackgroundHover: primary ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer3Hover
                    onClicked: root.choose(index)
                    contentItem: RowLayout {
                        id: choiceRow
                        spacing: 6
                        Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: 5
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                            StyledText {
                                anchors.centerIn: parent
                                text: `${choiceBtn.index + 1}`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            visible: choiceBtn.modelData[1].length > 0
                            text: choiceBtn.modelData[1]
                            iconSize: 16
                            color: choiceBtn.negative ? Appearance.colors.colError
                                : choiceBtn.primary ? (root.risky ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer)
                                : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: choiceBtn.modelData[0]
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: choiceBtn.primary ? (root.risky ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer)
                                : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        Rectangle { // note / free answer
            Layout.fillWidth: true
            implicitHeight: noteField.implicitHeight
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            StyledTextArea {
                id: noteField
                anchors { left: parent.left; right: parent.right }
                wrapMode: TextArea.Wrap
                padding: 8
                font.pixelSize: Appearance.font.pixelSize.smaller
                placeholderText: root.kind === "question" ? "Type an answer, Enter to send"
                    : root.kind === "plan" ? "What to change (Enter keeps planning)"
                    : "Or tell it what to do instead (Enter denies with this note)"
                background: null
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                        if (noteField.text.trim().length > 0) root.submitNote();
                        event.accepted = true;
                    }
                }
            }
        }
    }
}
