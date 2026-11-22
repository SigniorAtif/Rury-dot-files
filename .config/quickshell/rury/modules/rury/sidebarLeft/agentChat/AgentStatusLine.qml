pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/** "Thinking… 14s · 9 tok/s" with a stop button while a run is going; the context meter otherwise. */
RowLayout {
    id: root
    spacing: 8

    property real now: Date.now() / 1000
    Timer {
        running: Agent.running
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    readonly property int elapsed: Agent.statusSince > 0 ? Math.max(0, Math.round(now - Agent.statusSince)) : 0
    readonly property string label: {
        switch (Agent.status) {
        case "loading": return Agent.statusDetail.length > 0 ? `${Agent.statusDetail}…` : "Loading model…";
        case "thinking": return "Thinking…";
        case "tool": return Agent.statusDetail.split(" ")[0].replace(/^mcp__\w+__/, "").replace(/_/g, " ") + "…";
        case "waiting": return Agent.statusDetail === "plan" ? "Waiting for you to review the plan"
            : Agent.statusDetail === "question" ? "Waiting for your answer" : "Waiting for your OK";
        case "compacting": return "Compacting…";
        default: return "Working…";
        }
    }
    readonly property real ctxFrac: (Agent.usage?.ctx ?? 0) > 0 ? Math.min(1, (Agent.usage.prompt_tokens ?? 0) / Agent.usage.ctx) : 0

    MaterialLoadingIndicator {
        visible: Agent.running && Agent.status !== "waiting"
        loading: visible
        implicitSize: 20
    }
    MaterialSymbol {
        visible: Agent.status === "waiting"
        text: "pending"
        iconSize: 18
        color: Appearance.colors.colPrimary
    }
    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: {
            if (!Agent.running) {
                if ((Agent.usage?.ctx ?? 0) === 0) return "";
                return `${Math.round(root.ctxFrac * 100)}% of context used`;
            }
            let s = `${root.label} ${root.elapsed}s`;
            if ((Agent.usage?.tps ?? 0) > 0 && Agent.status !== "waiting") s += ` · ${Agent.usage.tps} tok/s`;
            if (Agent.queued > 0) s += ` · ${Agent.queued} queued`;
            return s;
        }
    }
    Rectangle { // context meter
        visible: (Agent.usage?.ctx ?? 0) > 0
        implicitWidth: 36
        implicitHeight: 4
        radius: 2
        color: Appearance.colors.colLayer3
        Rectangle {
            width: parent.width * root.ctxFrac
            height: parent.height
            radius: 2
            color: root.ctxFrac > 0.7 ? Appearance.colors.colError : Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: `Context: ${Agent.usage?.prompt_tokens ?? 0} / ${Agent.usage?.ctx ?? 0} tokens. /compact to summarise.`
        }
    }
    RippleButton {
        visible: Agent.running
        implicitHeight: 26
        implicitWidth: stopRow.implicitWidth + 16
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        onClicked: Agent.stop()
        contentItem: RowLayout {
            id: stopRow
            spacing: 4
            MaterialSymbol { text: "stop"; iconSize: 16; fill: 1; color: Appearance.colors.colOnLayer2 }
            StyledText { text: "Stop · Esc"; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
        }
    }
}
