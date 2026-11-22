pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Client for the SigniorAtif agent daemon (~/.config/quickshell/rury/agent, a Python process behind
 * $XDG_RUNTIME_DIR/rury/agent.sock). JSON lines both ways; see rury_agent/daemon.py for the protocol.
 * The daemon is started on demand (`wanted`), so the shell never pays for it until the Agent tab is used.
 */
Singleton {
    id: root

    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/rury/agent.sock`
    readonly property string launcher: `${Quickshell.env("HOME")}/.config/quickshell/rury/agent/agent`
    readonly property var modes: ["chat", "plan", "ask", "auto"]
    readonly property var modeInfo: ({
        "chat": { "icon": "forum", "label": "Chat", "hint": "Just talk. No tools." },
        "plan": { "icon": "map", "label": "Plan", "hint": "Looks around, proposes a plan, changes nothing until you approve." },
        "ask": { "icon": "front_hand", "label": "Ask", "hint": "Reads freely. Every change waits for your OK." },
        "auto": { "icon": "bolt", "label": "Auto", "hint": "Works on its own. Risky steps still ask." }
    })

    property bool wanted: false            // set by the UI the first time it is shown
    property bool hudVisible: false
    // sidebar or HUD on screen: approvals show there; otherwise they also go out as notifications
    readonly property bool uiOpen: GlobalStates.sidebarLeftOpen || hudVisible
    readonly property bool connected: socket.connected
    property bool starting: false

    // daemon-wide state
    property var models: []
    property var sessions: []
    property var automations: []
    property string modelState: "off"      // off | starting | on (the local llama-server)
    property string loadedModel: ""
    property bool deskRunning: false
    property bool deskControl: false      // the viewer passes Atif's mouse/keyboard through
    property string deskLastAction: ""
    property string defaultMode: "ask"

    // the session on screen
    property string sid: ""
    property var session: ({})
    property string draftMode: defaultMode
    property string draftModel: ""
    readonly property string mode: session?.mode ?? draftMode
    readonly property string modelId: session?.model ?? (draftModel || (models.find(m => m.default)?.id ?? ""))
    readonly property var model: models.find(m => m.id === modelId) ?? null
    readonly property bool think: (session?.think ?? 0) === 1
    property list<int> itemIds: []
    property var itemById: ({})
    property string status: "idle"         // idle | loading | thinking | tool | waiting | working
    property string statusDetail: ""
    property real statusSince: 0
    property var todos: []
    property var pending: []               // approval / question / plan cards waiting for an answer
    property var usage: ({})
    property int queued: 0
    readonly property bool running: status !== "idle"

    signal transcriptReset()
    signal itemAppended(int iid)
    signal requestFocus()

    property int _rid: 0
    property var _callbacks: ({})

    Component {
        id: itemComponent
        QtObject {
            property int iid
            property string type
            property string text: ""
            property string thinking: ""
            property var calls: []
            property string name: ""
            property string summary: ""
            property string status: ""
            property string output: ""
            property var args: ({})
            property var meta: ({})
            property var images: []
            property string level: ""
            property string kind: ""
            property var usage: ({})
            property bool streaming: false
        }
    }

    // ---- connection ----
    Socket {
        id: socket
        path: root.socketPath
        connected: false
        parser: SplitParser {
            onRead: line => root._onLine(line)
        }
        onConnectedChanged: {
            if (connected) {
                root.starting = false;
                root.call("ui", { "open": root.uiOpen });
                root.call("hello", {}, data => root._onHello(data));
            }
        }
        onError: retry.restart()
    }

    Timer {
        id: retry
        interval: 1200
        repeat: true
        running: root.wanted && !socket.connected
        triggeredOnStart: true
        property int attempts: 0
        onTriggered: {
            attempts += 1;
            if (attempts === 1 || attempts % 8 === 0) root._startDaemon();
            socket.connected = false;
            socket.connected = true;
        }
    }

    Process {
        id: starter
        command: ["bash", "-c", `systemctl --user start rury-agent.service 2>/dev/null || (setsid -f '${root.launcher}' daemon >/dev/null 2>&1 &)`]
    }

    function _startDaemon() {
        if (starter.running) return;
        root.starting = true;
        starter.running = true;
    }

    onUiOpenChanged: if (connected) call("ui", { "open": uiOpen })
    onWantedChanged: if (wanted) retry.attempts = 0

    function call(cmd, args, cb) {
        if (!socket.connected) return false;
        root._rid += 1;
        const msg = Object.assign({ "cmd": cmd, "rid": root._rid }, args ?? {});
        if (cb) root._callbacks[root._rid] = cb;
        socket.write(JSON.stringify(msg) + "\n");
        socket.flush();
        return true;
    }

    // ---- events ----
    function _onLine(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        const kind = ev.ev;
        if (kind === "reply") {
            const cb = root._callbacks[ev.rid];
            delete root._callbacks[ev.rid];
            if (!ev.ok) console.warn("[Agent]", ev.error);
            if (cb) cb(ev.ok ? ev.data : null, ev.ok ? "" : ev.error);
            return;
        }
        if (kind === "model_state") { root.modelState = ev.state; root.loadedModel = ev.model; return; }
        if (kind === "desk") {
            root.deskLastAction = ev.last_action ?? "";
            root.deskRunning = ev.running ?? true;
            if (!root.deskRunning) root.deskControl = false;
            return;
        }
        if (kind === "models") { root.models = ev.models; return; }
        if (kind === "automations") { root.automations = ev.automations; return; }
        if (kind === "session") { root._mergeSessionRow(ev.session); }
        if (kind === "done") root.refreshSessions();
        if (ev.sid !== root.sid) return;   // the rest is about one session's transcript

        switch (kind) {
        case "session":
            root.session = ev.session;
            break;
        case "status":
            root.status = ev.state;
            root.statusDetail = ev.detail ?? "";
            if (ev.state !== "idle" && root.statusSince === 0) root.statusSince = Date.now() / 1000;
            if (ev.state === "idle") root.statusSince = 0;
            break;
        case "item":
            root._addItem(ev.item);
            break;
        case "item_update":
            root._updateItem(ev.item);
            break;
        case "delta": {
            const it = root.itemById[ev.item_id];
            if (!it) break;
            if (ev.kind === "text") it.text += ev.text; else it.thinking += ev.text;
            break;
        }
        case "approval":
        case "question":
        case "plan":
            root.pending = [...root.pending.filter(p => p.rid !== ev.rid), Object.assign({ "kind": kind }, ev)];
            root.requestFocus();
            break;
        case "resolved":
            root.pending = root.pending.filter(p => p.rid !== ev.rid);
            break;
        case "todo":
            root.todos = ev.todos;
            break;
        case "usage":
            root.usage = ev;
            break;
        case "queued":
            root.queued = ev.count;
            break;
        case "done":
            root.queued = 0;
            break;
        }
    }

    function _onHello(data) {
        if (!data) return;
        root.models = data.models;
        root.sessions = data.sessions;
        root.automations = data.automations;
        root.modelState = data.model_state;
        root.loadedModel = data.loaded_model;
        root.deskRunning = data.desk;
        root.defaultMode = data.default_mode;
        if (root.sid && data.sessions.some(s => s.id === root.sid)) {
            root.loadSession(root.sid);
        } else {
            if (root.sid) root.newSession();   // it was archived while we were away
            // pick up where Atif left off if the last chat is recent
            const recent = data.sessions.find(s => s.kind === "chat");
            if (recent && (Date.now() / 1000 - recent.updated) < 3 * 3600) root.loadSession(recent.id);
        }
    }

    function _mergeSessionRow(s) {
        if (!s) return;
        const rows = root.sessions.filter(r => r.id !== s.id);
        root.sessions = [s, ...rows];
    }

    function _makeItem(d) {
        const it = itemComponent.createObject(root, {
            "iid": d.id, "type": d.type, "text": d.text ?? "", "thinking": d.thinking ?? "",
            "calls": d.calls ?? [], "name": d.name ?? "", "summary": d.summary ?? "", "status": d.status ?? "",
            "output": d.output ?? "", "args": d.args ?? {}, "meta": d.meta ?? {}, "images": d.images ?? [],
            "level": d.level ?? "", "kind": d.kind ?? "", "usage": d.usage ?? {},
            "streaming": d.type === "assistant" && !(d.usage && d.usage.completion !== undefined)
        });
        return it;
    }

    function _addItem(d) {
        if (root.itemById[d.id]) return;
        const it = root._makeItem(d);
        root.itemById[d.id] = it;
        root.itemIds = [...root.itemIds, d.id];
        root.itemAppended(d.id);
    }

    function _updateItem(d) {
        const it = root.itemById[d.id];
        if (!it) { root._addItem(d); return; }
        for (const key of ["text", "thinking", "calls", "summary", "status", "output", "args", "meta", "images", "usage"]) {
            if (d[key] !== undefined) it[key] = d[key];
        }
        if (d.type === "assistant") it.streaming = false;
    }

    function _clearTranscript() {
        for (const id of root.itemIds) root.itemById[id]?.destroy();
        root.itemById = {};
        root.itemIds = [];
        root.todos = [];
        root.pending = [];
        root.usage = {};
        root.queued = 0;
        root.status = "idle";
        root.statusSince = 0;
        root.transcriptReset();
    }

    // ---- actions ----
    function ensure() {
        root.wanted = true;
    }

    function send(text, images) {
        const t = (text ?? "").trim();
        if (t.length === 0 && !(images?.length > 0)) return;
        if (!root.connected) { root.ensure(); return; }
        const args = { "text": t, "images": images ?? [] };
        if (root.sid) {
            args.sid = root.sid;
            root.call("send", args);
        } else {
            args.mode = root.draftMode;
            if (root.draftModel) args.model = root.draftModel;
            root.call("send", args, data => {
                if (data?.sid && !root.sid) root.loadSession(data.sid);
            });
        }
    }

    function stop() { if (root.sid) root.call("stop", { "sid": root.sid }); }

    function answer(rid, ans) {
        root.call("answer", { "sid": root.sid, "rid_answer": rid, "answer": ans });
        root.pending = root.pending.filter(p => p.rid !== rid);
    }

    function setMode(m) {
        if (root.sid) root.call("set", { "sid": root.sid, "mode": m }, data => { if (data) root.session = data; });
        else root.draftMode = m;
    }

    function cycleMode() {
        const i = root.modes.indexOf(root.mode);
        root.setMode(root.modes[(i + 1) % root.modes.length]);
    }

    function setModel(id) {
        if (root.sid) root.call("set", { "sid": root.sid, "model": id }, data => { if (data) root.session = data; });
        else root.draftModel = id;
    }

    function setThink(on) {
        if (root.sid) root.call("set", { "sid": root.sid, "think": on }, data => { if (data) root.session = data; });
    }

    function newSession() {
        root.draftMode = root.mode;
        root.draftModel = root.modelId;
        root.sid = "";
        root.session = {};
        root._clearTranscript();
    }

    function loadSession(id) {
        root.call("load", { "sid": id }, data => {
            if (!data) return;
            root._clearTranscript();
            root.sid = id;
            root.session = data.session;
            root.status = data.session.status ?? "idle";
            root.todos = data.session.todos ?? [];
            root.pending = (data.session.pending ?? []);
            for (const d of data.items) root._addItem(d);
            for (const id2 of root.itemIds) root.itemById[id2].streaming = false;
            root.transcriptReset();
        });
    }

    function archiveSession(id) {
        root.call("archive", { "sid": id }, () => {
            root.refreshSessions();
            if (id === root.sid) root.newSession();
        });
    }

    function refreshSessions() { root.call("sessions", { "limit": 50 }, data => { if (data) root.sessions = data; }); }
    function refreshModels() { root.call("models", {}, data => { if (data) root.models = data; }); }
    function compact() { if (root.sid) root.call("compact", { "sid": root.sid }); }
    function deskView(control) {
        const args = { "action": "view" };
        if (control !== undefined) args.control = control;
        const ok = root.call("desk", args, d => {
            if (!d) return;
            root.deskRunning = d.running;
            root.deskControl = d.control;
        });
        if (!ok) Quickshell.execDetached([root.launcher, "desk", "view"]);
    }
    function deskStop() { root.call("desk", { "action": "stop" }, () => root.deskRunning = false); }
    function stopModel() { root.call("model_stop", {}); }
    function automationSet(id, fields) { root.call("automation_set", Object.assign({ "id": id }, fields)); }
    function automationDelete(id) { root.call("automation_delete", { "id": id }); }
    function automationRun(id) { root.call("automation_run", { "id": id }); }

    IpcHandler {
        target: "agent"
        function send(text: string): void { root.ensure(); root.send(text, []); }
        function stop(): void { root.stop(); }
        function view(): void { root.deskView(); }
        function newSession(): void { root.newSession(); }
        function status(): string { return `${root.connected ? "connected" : "disconnected"} ${root.status} ${root.mode} ${root.modelId}`; }
    }
}
