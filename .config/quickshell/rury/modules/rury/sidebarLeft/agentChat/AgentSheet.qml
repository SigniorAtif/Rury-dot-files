pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Slide-up sheet over the agent chat: past sessions, models, skills, MCP servers, automations.
 * `page` picks what it shows; empty string = closed.
 */
Item {
    id: root
    property string page: ""
    readonly property bool shown: page.length > 0
    signal insertText(string text)

    readonly property var pages: [
        { "id": "sessions", "icon": "history", "label": "Sessions" },
        { "id": "models", "icon": "memory", "label": "Models" },
        { "id": "skills", "icon": "auto_awesome", "label": "Skills" },
        { "id": "mcp", "icon": "extension", "label": "MCP" },
        { "id": "automations", "icon": "schedule", "label": "Automations" }
    ]

    property var skills: []
    property var mcp: []

    function open(p) {
        root.page = p;
        if (p === "sessions") Agent.refreshSessions();
        if (p === "models") Agent.refreshModels();
        if (p === "skills") Agent.call("skills", {}, d => { if (d) root.skills = d; });
        if (p === "mcp") Agent.call("mcp", {}, d => { if (d) root.mcp = d; });
        if (p === "automations") Agent.call("automations", {}, d => { if (d) Agent.automations = d; });
    }
    function close() { root.page = ""; }

    function ago(t) {
        const s = Date.now() / 1000 - t;
        if (s < 60) return "now";
        if (s < 3600) return `${Math.floor(s / 60)}m`;
        if (s < 86400) return `${Math.floor(s / 3600)}h`;
        if (s < 86400 * 7) return `${Math.floor(s / 86400)}d`;
        return new Date(t * 1000).toLocaleDateString(Qt.locale(), "d MMM");
    }
    function until(t) {
        if (!t) return "";
        const s = t - Date.now() / 1000;
        if (s < 60) return "due now";
        if (s < 3600) return `in ${Math.round(s / 60)}m`;
        if (s < 86400) return `in ${Math.round(s / 3600)}h`;
        return new Date(t * 1000).toLocaleString(Qt.locale(), "ddd d MMM, HH:mm");
    }

    visible: scrim.opacity > 0

    Rectangle { // scrim
        id: scrim
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: root.shown ? 1 : 0
        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        MouseArea {
            anchors.fill: parent
            enabled: root.shown
            onClicked: root.close()
        }
    }

    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right }
        height: Math.min(parent.height * 0.82, Math.max(260, sheetCol.implicitHeight + 16))
        y: root.shown ? parent.height - height : parent.height + 8
        Behavior on y { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        MouseArea { anchors.fill: parent } // eat clicks

        ColumnLayout {
            id: sheetCol
            anchors { fill: parent; margins: 8 }
            spacing: 8

            RowLayout { // page chips + close
                Layout.fillWidth: true
                spacing: 4
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: chipRow.implicitHeight
                    contentWidth: chipRow.implicitWidth
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: chipRow
                        spacing: 4
                        Repeater {
                            model: root.pages
                            delegate: RippleButton {
                                id: chip
                                required property var modelData
                                readonly property bool active: root.page === modelData.id
                                implicitHeight: 30
                                implicitWidth: chipContent.implicitWidth + 18
                                buttonRadius: Appearance.rounding.full
                                toggled: active
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                onClicked: root.open(modelData.id)
                                contentItem: RowLayout {
                                    id: chipContent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: chip.modelData.icon
                                        iconSize: 15
                                        color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: chip.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                }
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.close()
                    contentItem: MaterialSymbol { text: "close"; iconSize: 18; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colSubtext }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.shown
                sourceComponent: root.page === "sessions" ? sessionsPage : root.page === "models" ? modelsPage
                    : root.page === "skills" ? skillsPage : root.page === "mcp" ? mcpPage : automationsPage
            }
        }
    }

    // ---- shared row look ----
    component SheetRow: RippleButton {
        id: row
        property string symbol
        property string title
        property string subtitle
        property string trailing
        property bool current: false
        property bool dim: false
        default property alias extra: extraRow.data
        implicitHeight: rowLayout.implicitHeight + 14
        buttonRadius: Appearance.rounding.small
        colBackground: current ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
        contentItem: RowLayout {
            id: rowLayout
            spacing: 10
            MaterialSymbol {
                visible: row.symbol.length > 0
                text: row.symbol
                iconSize: 18
                color: row.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: row.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: row.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    opacity: row.dim ? 0.6 : 1
                }
                StyledText {
                    visible: row.subtitle.length > 0
                    Layout.fillWidth: true
                    text: row.subtitle
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                visible: row.trailing.length > 0
                text: row.trailing
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            RowLayout { id: extraRow; spacing: 2 }
        }
    }

    component SmallIconButton: RippleButton {
        id: sib
        property string symbol
        property string tip
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            text: sib.symbol
            iconSize: 17
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
        }
        StyledToolTip { text: sib.tip; extraVisibleCondition: sib.tip.length > 0 }
    }

    component Empty: StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    // ---- pages ----
    Component {
        id: sessionsPage
        StyledListView {
            clip: true
            spacing: 2
            popin: false
            model: Agent.sessions
            delegate: SheetRow {
                id: srow
                required property var modelData
                width: ListView.view.width
                symbol: modelData.kind === "automation" ? "schedule" : (Agent.modeInfo[modelData.mode]?.icon ?? "chat")
                title: modelData.title || "Untitled"
                subtitle: modelData.kind === "automation" ? "Automation run" : ""
                trailing: root.ago(modelData.updated)
                current: modelData.id === Agent.sid
                onClicked: { Agent.loadSession(modelData.id); root.close(); }
                SmallIconButton {
                    symbol: "archive"
                    tip: "Archive"
                    onClicked: Agent.archiveSession(srow.modelData.id)
                }
            }
            Empty {
                anchors.centerIn: parent
                width: parent.width
                visible: Agent.sessions.length === 0
                text: "No sessions yet"
            }
        }
    }

    Component {
        id: modelsPage
        ColumnLayout {
            spacing: 6
            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                popin: false
                model: Agent.models
                delegate: SheetRow {
                    required property var modelData
                    width: ListView.view.width
                    readonly property bool loaded: Agent.loadedModel === modelData.id && Agent.modelState !== "off"
                    symbol: modelData.kind === "llama.cpp" ? "memory" : modelData.base_url?.includes("127.0.0.1") || modelData.base_url?.includes("localhost") ? "dns" : "cloud"
                    title: modelData.name + (modelData.default ? "  · default" : "")
                    subtitle: [modelData.kind === "llama.cpp" ? "local GGUF" : modelData.source || modelData.kind,
                               `${Math.round(modelData.ctx / 1024)}k ctx`, modelData.vision ? "sees images" : "",
                               loaded ? (Agent.modelState === "starting" ? "loading…" : "loaded") : ""].filter(x => x).join(" · ")
                    current: modelData.id === Agent.modelId
                    onClicked: { Agent.setModel(modelData.id); root.close(); }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Add models in ~/.config/rury/agent/models.toml. GGUFs in /mnt/d/rury/models, Ollama and LM Studio show up on their own."
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                SmallIconButton { symbol: "refresh"; tip: "Rescan"; onClicked: Agent.refreshModels() }
                SmallIconButton {
                    visible: Agent.modelState !== "off"
                    symbol: "power_settings_new"
                    tip: "Unload the local model (frees GPU memory)"
                    onClicked: Agent.stopModel()
                }
            }
        }
    }

    Component {
        id: skillsPage
        StyledListView {
            clip: true
            spacing: 2
            popin: false
            model: root.skills
            delegate: SheetRow {
                required property var modelData
                width: ListView.view.width
                symbol: "auto_awesome"
                title: modelData.name
                subtitle: modelData.description
                onClicked: { root.insertText(`Use the ${modelData.name} skill: `); root.close(); }
            }
            Empty {
                anchors.centerIn: parent
                width: parent.width
                visible: root.skills.length === 0
                text: "No skills. Add folders with a SKILL.md to ~/.config/rury/agent/skills"
            }
        }
    }

    Component {
        id: mcpPage
        ColumnLayout {
            spacing: 6
            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                popin: false
                model: root.mcp
                delegate: SheetRow {
                    required property var modelData
                    width: ListView.view.width
                    symbol: modelData.state === "on" ? "check_circle" : modelData.state === "error" ? "error" : "radio_button_unchecked"
                    title: modelData.name + (modelData.desk ? "  · on desk" : "")
                    subtitle: modelData.error || `${modelData.tools} tools · ${modelData.state === "on" ? "running" : "starts when used"} · ${modelData.command}`
                    onClicked: {}
                }
                Empty {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: root.mcp.length === 0
                    text: "No MCP servers. Add them to ~/.config/rury/agent/mcp.json (same format as Claude Code)."
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Tools load on demand: the agent sees their names and pulls one in with tool_search."
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                SmallIconButton {
                    symbol: "refresh"
                    tip: "Reload mcp.json"
                    onClicked: Agent.call("mcp", { "reload": true }, d => { if (d) root.mcp = d; })
                }
            }
        }
    }

    Component {
        id: automationsPage
        StyledListView {
            clip: true
            spacing: 2
            popin: false
            model: Agent.automations
            delegate: SheetRow {
                id: arow
                required property var modelData
                width: ListView.view.width
                symbol: "schedule"
                dim: !modelData.enabled
                title: modelData.name || modelData.prompt
                subtitle: `${modelData.schedule} · ${modelData.mode}` + (modelData.enabled && modelData.next_run ? ` · next ${root.until(modelData.next_run)}` : "")
                    + (modelData.last_run ? ` · last ${root.ago(modelData.last_run)} ago` : "")
                onClicked: if (modelData.last_session) { Agent.loadSession(modelData.last_session); root.close(); }
                SmallIconButton { symbol: "play_arrow"; tip: "Run now"; onClicked: Agent.automationRun(arow.modelData.id) }
                SmallIconButton { symbol: "delete"; tip: "Delete"; onClicked: Agent.automationDelete(arow.modelData.id) }
                StyledSwitch {
                    checked: !!arow.modelData.enabled
                    onToggled: Agent.automationSet(arow.modelData.id, { "enabled": checked ? 1 : 0 })
                }
            }
            Empty {
                anchors.centerIn: parent
                width: parent.width
                visible: Agent.automations.length === 0
                text: "No automations. Ask the agent: \"every morning at 9, …\""
            }
        }
    }
}
