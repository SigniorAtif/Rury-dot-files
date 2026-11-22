pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.rury.sidebarLeft.agentChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * The agent tab: a Claude-Code-style transcript (markdown, tool cards, approvals, plan review, todo list)
 * over the rury-agent daemon. Enter sends, Shift+Enter breaks the line, Shift+Tab cycles the mode,
 * Esc stops, 1-9 answer a waiting card, "/" for commands.
 */
Item {
    id: root
    property real padding: 4
    property var inputField: input
    property var attachments: []          // image paths for the next message
    property var suggestionList: []

    readonly property bool active: SwipeView.isCurrentItem && GlobalStates.sidebarLeftOpen
    onActiveChanged: if (active) Agent.ensure()
    Component.onCompleted: if (active) Agent.ensure()

    onFocusChanged: focus => { if (focus) input.forceActiveFocus(); }

    readonly property var modeColors: ({
        "chat": [Appearance.colors.colLayer3, Appearance.colors.colOnLayer2],
        "plan": [Appearance.colors.colTertiaryContainer, Appearance.colors.colOnTertiaryContainer],
        "ask": [Appearance.colors.colSecondaryContainer, Appearance.colors.colOnSecondaryContainer],
        "auto": [Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer]
    })

    readonly property var commands: [
        { "name": "new", "description": "Start a new session", "run": args => Agent.newSession() },
        { "name": "resume", "description": "Pick an earlier session", "run": args => sheet.open("sessions") },
        { "name": "mode", "description": "chat · plan · ask · auto (Shift+Tab cycles)", "run": args => {
            if (Agent.modes.includes(args[0])) Agent.setMode(args[0]); else Agent.cycleMode();
        } },
        { "name": "model", "description": "Switch model", "run": args => {
            const id = args.join(" ").trim();
            if (id && Agent.models.some(m => m.id === id)) Agent.setModel(id); else sheet.open("models");
        } },
        { "name": "think", "description": "Let the model think before it answers (slower, smarter)", "run": args => Agent.setThink(!Agent.think) },
        { "name": "compact", "description": "Summarise the conversation so far to free context", "run": args => Agent.compact() },
        { "name": "desk", "description": "Show the agent's desktop (add 'control' to drive it, 'stop' to shut it)", "run": args => {
            if (args[0] === "stop") Agent.deskStop(); else Agent.deskView(args[0] === "control" ? true : undefined);
        } },
        { "name": "stop", "description": "Stop the current run", "run": args => Agent.stop() },
        { "name": "skills", "description": "Skills the agent can load", "run": args => sheet.open("skills") },
        { "name": "mcp", "description": "MCP servers and their tools", "run": args => sheet.open("mcp") },
        { "name": "automations", "description": "Scheduled tasks", "run": args => sheet.open("automations") },
        { "name": "clear", "description": "Same as /new", "run": args => Agent.newSession() }
    ]

    function handleInput(text) {
        const t = text.trim();
        if (t.startsWith("/") && !t.startsWith("//")) {
            const parts = t.substring(1).split(/\s+/);
            const cmd = root.commands.find(c => c.name === parts[0]);
            if (cmd) {
                cmd.run(parts.slice(1));
                return true;
            }
        }
        if (t.length === 0 && root.attachments.length === 0) return false;
        Agent.send(t.startsWith("//") ? t.substring(1) : t, root.attachments);
        root.attachments = [];
        list.stick = true;
        return true;
    }

    function updateSuggestions() {
        const t = input.text;
        if (!t.startsWith("/")) { root.suggestionList = []; return; }
        const parts = t.substring(1).split(" ");
        if (parts.length === 1) {
            root.suggestionList = root.commands.filter(c => c.name.startsWith(parts[0]))
                .map(c => ({ "name": `/${c.name}`, "description": c.description }));
        } else if (parts[0] === "mode") {
            root.suggestionList = Agent.modes.filter(m => m.startsWith(parts[1]))
                .map(m => ({ "name": `/mode ${m}`, "displayName": Agent.modeInfo[m].label, "description": Agent.modeInfo[m].hint }));
        } else if (parts[0] === "model") {
            const q = parts.slice(1).join(" ");
            const hits = q.length ? Fuzzy.go(q, Agent.models.map(m => ({ "name": Fuzzy.prepare(`${m.id} ${m.name}`), "obj": m })), { "key": "name", "limit": 8 }).map(r => r.obj.obj)
                : Agent.models.slice(0, 8);
            root.suggestionList = hits.map(m => ({ "name": `/model ${m.id}`, "displayName": m.name, "description": `${m.kind} · ${Math.round(m.ctx / 1024)}k ctx${m.vision ? " · vision" : ""}` }));
        } else if (parts[0] === "desk") {
            root.suggestionList = ["control", "stop"].filter(a => a.startsWith(parts[1]))
                .map(a => ({ "name": `/desk ${a}`, "description": a === "control" ? "Watch and take over the mouse and keyboard" : "Shut the agent desktop down" }));
        } else {
            root.suggestionList = [];
        }
    }

    // ---- image paste (same trick as the old chat) ----
    Process {
        id: decodeImage
        property string dir: Directories.cliphistDecode
        property string path: ""
        function handle(entry) {
            path = `${dir}/agent-${parseInt(entry.match(/^(\d+)\t/)[1])}`;
            exec(["bash", "-c", `[ -f '${path}' ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${path}'`]);
        }
        onExited: (code, status) => { if (code === 0) root.attachments = [...root.attachments, path]; }
    }

    Connections {
        target: Agent
        function onTranscriptReset() { list.stick = true; Qt.callLater(list.positionViewAtEnd); }
        function onRequestFocus() { if (root.active) input.forceActiveFocus(); }
    }

    Keys.onPressed: event => {
        input.forceActiveFocus();
        if (event.key === Qt.Key_PageUp) {
            list.contentY = Math.max(list.originY, list.contentY - list.height / 2);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            list.contentY = Math.min(list.contentHeight + list.originY - list.height, list.contentY + list.height / 2);
            event.accepted = true;
        }
    }

    // ---- small parts ----
    component HeaderButton: RippleButton {
        id: hb
        property string symbol
        property string tip
        property bool lit: false
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: hb.lit ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: hb.lit ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
        contentItem: MaterialSymbol {
            text: hb.symbol
            iconSize: 18
            fill: hb.lit ? 1 : 0
            horizontalAlignment: Text.AlignHCenter
            color: hb.lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
        }
        StyledToolTip { text: hb.tip }
    }

    component Chip: RippleButton {
        id: chip
        property string symbol
        property string label
        property color bg: Appearance.colors.colLayer3
        property color fg: Appearance.colors.colOnLayer2
        property string tip
        implicitHeight: 28
        implicitWidth: chipRow.implicitWidth + 16
        buttonRadius: Appearance.rounding.full
        colBackground: bg
        colBackgroundHover: ColorUtils.mix(bg, fg, 0.88)
        contentItem: RowLayout {
            id: chipRow
            spacing: 4
            MaterialSymbol { visible: chip.symbol.length > 0; text: chip.symbol; iconSize: 15; color: chip.fg }
            StyledText {
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.fg
                elide: Text.ElideRight
                Layout.maximumWidth: 150
            }
        }
        StyledToolTip { text: chip.tip; extraVisibleCondition: chip.tip.length > 0 }
    }

    ColumnLayout {
        anchors { fill: parent; margins: root.padding }
        spacing: root.padding

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 2
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Agent.session?.title || "New task"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Agent.connected ? Appearance.colors.colSubtext : Appearance.colors.colError
                    text: !Agent.connected ? (Agent.starting ? "Starting the agent…" : "Agent offline, retrying…")
                        : Agent.deskRunning && Agent.deskLastAction.length > 0 ? `Desk: ${Agent.deskLastAction}`
                        : Agent.modelState === "starting" ? "Loading model…"
                        : (Agent.session?.cwd ?? "").replace(Quickshell.env("HOME"), "~")
                }
            }
            HeaderButton {
                symbol: "desktop_windows"
                tip: Agent.deskRunning ? "Agent desktop (Super+Shift+/)" : "Open the agent desktop (Super+Shift+/)"
                lit: Agent.deskRunning
                onClicked: Agent.deskView()
            }
            HeaderButton { symbol: "history"; tip: "Sessions"; onClicked: sheet.open("sessions") }
            HeaderButton { symbol: "tune"; tip: "Models, skills, MCP, automations"; onClicked: sheet.open("models") }
            HeaderButton { symbol: "add"; tip: "New session"; onClicked: Agent.newSession() }
        }

        // ---- transcript ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 10
                popin: false
                add: null
                leftMargin: 6
                rightMargin: 6
                topMargin: 4
                bottomMargin: 8
                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                // follow the output unless Atif scrolled up to read
                property bool stick: true
                onMovementStarted: stick = false
                onMovementEnded: stick = atYEnd
                onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)
                onCountChanged: if (stick) Qt.callLater(positionViewAtEnd)

                model: ScriptModel { values: Agent.itemIds }
                delegate: AgentItem {
                    required property int modelData
                    width: list.width - list.leftMargin - list.rightMargin
                    item: Agent.itemById[modelData] ?? null
                }
            }

            ColumnLayout { // empty state
                anchors.centerIn: parent
                width: parent.width - 24
                visible: Agent.itemIds.length === 0
                spacing: 14
                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "smart_toy"
                    iconSize: 40
                    padding: 16
                    shape: MaterialShape.Shape.Cookie7Sided
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "What should I do?"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: `${Agent.modeInfo[Agent.mode]?.hint ?? ""}\nI have my own desktop: Super+Shift+/ to watch.`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6
                    Repeater {
                        model: [
                            ["folder_managed", "What's taking up space in my home folder?"],
                            ["download", "Sort ~/Downloads into folders by file type"],
                            ["language", "Open example.com on your desk and tell me the heading"],
                            ["update", "Which of my installed packages have updates?"]
                        ]
                        delegate: Chip {
                            required property var modelData
                            symbol: modelData[0]
                            label: modelData[1]
                            bg: Appearance.colors.colLayer2
                            fg: Appearance.colors.colOnLayer2
                            onClicked: { input.text = modelData[1]; input.cursorPosition = input.text.length; input.forceActiveFocus(); }
                        }
                    }
                }
            }

            ScrollToBottomButton {
                z: 3
                target: list
                onClicked: { list.stick = true; list.positionViewAtEnd(); }
            }
        }

        // ---- waiting on Atif ----
        Repeater {
            id: pendingRepeater
            model: Agent.pending
            delegate: AgentPendingCard {
                required property var modelData
                Layout.fillWidth: true
                pending: modelData
            }
        }

        AgentTodoPanel {
            Layout.fillWidth: true
            visible: Agent.todos.length > 0 && Agent.todos.some(t => t.status !== "completed") || (Agent.running && Agent.todos.length > 0)
        }

        AgentStatusLine {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            visible: Agent.running || (Agent.usage?.ctx ?? 0) > 0
        }

        // ---- slash suggestions ----
        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }
        FlowButtonGroup {
            id: suggestions
            visible: root.suggestionList.length > 0 && input.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5
            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: sugBtn
                    required property var modelData
                    required property int index
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: sugBtn.modelData.displayName ?? sugBtn.modelData.name
                    }
                    onHoveredChanged: if (hovered) suggestions.selectedIndex = index
                    onClicked: suggestions.accept(index)
                }
            }
            function accept(i) {
                const s = root.suggestionList[i];
                if (!s) return;
                input.text = s.name + " ";
                input.cursorPosition = input.text.length;
                input.forceActiveFocus();
            }
        }

        // ---- input ----
        Rectangle {
            id: inputWrapper
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: inputCol.implicitHeight + 10
            border.width: input.activeFocus ? 1 : 0
            border.color: Appearance.colors.colOutlineVariant
            Behavior on implicitHeight { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

            ColumnLayout {
                id: inputCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
                spacing: 4

                Flow { // pasted images
                    visible: root.attachments.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 5
                    spacing: 6
                    Repeater {
                        model: root.attachments
                        delegate: Rectangle {
                            id: att
                            required property string modelData
                            required property int index
                            width: 64
                            height: 48
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer3
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: "file://" + att.modelData
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 128
                                asynchronous: true
                            }
                            RippleButton {
                                anchors { top: parent.top; right: parent.right; margins: 2 }
                                implicitWidth: 18
                                implicitHeight: 18
                                buttonRadius: 9
                                colBackground: Appearance.colors.colLayer1
                                onClicked: root.attachments = root.attachments.filter((_, i) => i !== att.index)
                                contentItem: MaterialSymbol { text: "close"; iconSize: 12; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 0.4, input.implicitHeight)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    StyledTextArea {
                        id: input
                        wrapMode: TextArea.Wrap
                        padding: 8
                        background: null
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Agent.running ? "Add to the task (it reads this at the next step)…"
                            : Agent.mode === "chat" ? "Ask anything…" : "Give me a task… \"/\" for commands"
                        onTextChanged: root.updateSuggestions()

                        Keys.onPressed: event => {
                            const noText = input.text.length === 0;
                            const firstCard = pendingRepeater.count > 0 ? pendingRepeater.itemAt(0) : null;
                            if (event.key === Qt.Key_Backtab) {
                                Agent.cycleMode();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab && suggestions.visible) {
                                suggestions.accept(suggestions.selectedIndex);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if (noText && firstCard && event.key >= Qt.Key_1 && event.key <= Qt.Key_9
                                       && event.modifiers === Qt.NoModifier) {
                                firstCard.choose(event.key - Qt.Key_1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    input.insert(input.cursorPosition, "\n");
                                } else if (suggestions.visible && root.suggestionList[suggestions.selectedIndex]
                                           && input.text.trim() !== root.suggestionList[suggestions.selectedIndex].name
                                           && !input.text.includes(" ")) {
                                    suggestions.accept(suggestions.selectedIndex);
                                } else if (root.handleInput(input.text)) {
                                    input.clear();
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (Agent.running) { Agent.stop(); event.accepted = true; }
                                else if (root.attachments.length > 0) { root.attachments = []; event.accepted = true; }
                                else if (sheet.shown) { sheet.close(); event.accepted = true; }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V
                                       && !(event.modifiers & Qt.ShiftModifier)) {
                                const entry = Cliphist.entries[0] ?? "";
                                const clean = StringUtils.cleanCliphistEntry(entry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry)) {
                                    decodeImage.handle(entry);
                                    event.accepted = true;
                                } else if (clean.startsWith("file://") && /\.(png|jpe?g|webp|gif)$/i.test(clean)) {
                                    root.attachments = [...root.attachments, decodeURIComponent(clean.replace("file://", ""))];
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                RowLayout { // mode, model, think, send
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    spacing: 4
                    Chip {
                        symbol: Agent.modeInfo[Agent.mode]?.icon ?? "help"
                        label: Agent.modeInfo[Agent.mode]?.label ?? Agent.mode
                        bg: root.modeColors[Agent.mode]?.[0] ?? Appearance.colors.colLayer3
                        fg: root.modeColors[Agent.mode]?.[1] ?? Appearance.colors.colOnLayer2
                        tip: `${Agent.modeInfo[Agent.mode]?.hint ?? ""}\nShift+Tab to switch. Risky steps always ask.`
                        onClicked: Agent.cycleMode()
                    }
                    Chip {
                        symbol: Agent.model?.kind === "llama.cpp" ? "memory" : "cloud"
                        label: Agent.model?.name ?? (Agent.modelId || "No model")
                        tip: Agent.modelState === "starting" ? "Loading…" : "Switch model"
                        onClicked: sheet.open("models")
                        Rectangle { // loaded dot
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            width: 6
                            height: 6
                            radius: 3
                            visible: Agent.modelState !== "off" && Agent.loadedModel === Agent.modelId
                            color: Agent.modelState === "on" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }
                    HeaderButton {
                        symbol: "neurology"
                        lit: Agent.think
                        enabled: Agent.sid.length > 0
                        tip: Agent.think ? "Thinking on: slower, more careful" : "Thinking off: faster (/think to toggle)"
                        onClicked: Agent.setThink(!Agent.think)
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        id: sendButton
                        readonly property bool canSend: input.text.trim().length > 0 || root.attachments.length > 0
                        readonly property bool stopMode: Agent.running && !canSend
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: canSend || stopMode
                        toggled: true
                        colBackgroundToggled: stopMode ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
                        onClicked: {
                            if (stopMode) Agent.stop();
                            else if (root.handleInput(input.text)) input.clear();
                        }
                        contentItem: MaterialSymbol {
                            text: sendButton.stopMode ? "stop" : (Agent.running ? "add_comment" : "arrow_upward")
                            iconSize: 20
                            fill: 1
                            horizontalAlignment: Text.AlignHCenter
                            color: sendButton.stopMode ? Appearance.colors.colOnErrorContainer : Appearance.m3colors.m3onPrimary
                        }
                        StyledToolTip { text: sendButton.stopMode ? "Stop (Esc)" : Agent.running ? "Queue for the next step" : "Send (Enter)" }
                    }
                }
            }
        }
    }

    AgentSheet {
        id: sheet
        anchors.fill: parent
        z: 10
        onInsertText: text => { input.text = text; input.cursorPosition = input.text.length; input.forceActiveFocus(); }
    }
}
