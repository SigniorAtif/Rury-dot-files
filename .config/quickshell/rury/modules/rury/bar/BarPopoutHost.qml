pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

// One panel hanging off the bar that morphs (position + size) between the
// hovered bar popups, with concave "flares" so it reads as part of the bar.
PanelWindow {
    id: root

    property var popup: null
    function syncPopup() {
        const c = BarPopoutState.current;
        let next = null;
        if (c && c.shared && c.hoverTarget) {
            const win = c.hoverTarget.QsWindow?.window;
            if (win && win.screen === root.screen) next = c;
        }
        if (next !== root.popup) root.popup = next;
    }
    Connections {
        target: BarPopoutState
        function onCurrentChanged() { root.syncPopup(); }
    }
    readonly property bool open: popup !== null && GlobalStates.barOpen && !GlobalStates.screenLocked

    readonly property bool floating: Config.options.bar.cornerStyle === 1
    readonly property real barBottom: floating ? Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight
    readonly property real flare: floating ? Appearance.rounding.normal : Appearance.rounding.screenRounding
    readonly property real radius: Appearance.rounding.large
    readonly property real shadowPad: Appearance.sizes.elevationMargin * 2
    readonly property real edgeMargin: (floating ? Appearance.sizes.hyprlandGapsOut : 0) + flare

    // Where the panel wants to be
    property real targetCenterX: width / 2
    readonly property real targetW: popup ? popup.page.implicitWidth : panel.lastW
    readonly property real targetH: popup ? popup.page.implicitHeight : 0
    // Center clamped with the *target* width so edge clamping never lags behind
    readonly property real targetCx: Math.max(edgeMargin + targetW / 2,
        Math.min(width - edgeMargin - targetW / 2, targetCenterX))

    // Set imperatively so animation params switch before the targets move
    property bool shown: false
    property bool closing: false
    onOpenChanged: {
        closing = !open;
        shown = open;
    }

    function updateTargetX() {
        if (!popup) return;
        const t = popup.hoverTarget;
        const p = t.mapToItem(null, t.width / 2, 0);
        root.targetCenterX = p.x;
    }
    onPopupChanged: {
        updateTargetX();
        if (popup) {
            const pg = popup.page;
            if (pg.parent !== contentHolder) {
                pg.parent = contentHolder;
                pg.anchors.horizontalCenter = contentHolder.horizontalCenter;
                pg.anchors.top = contentHolder.top;
            }
        }
    }
    Timer { // Bar items shift around (e.g. media title width); follow them
        running: root.open
        interval: 200
        repeat: true
        onTriggered: root.updateTargetX()
    }

    visible: open || panel.height > 0.5
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:popout"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
        top: true
        left: true
        right: true
    }
    // Only as tall as the biggest popout needs: the whole surface is redrawn
    // every animated frame, so a smaller window is much cheaper.
    implicitHeight: Math.min(screen?.height ?? 1080, barBottom + 560)

    mask: Region {
        item: hitbox
    }

    Item {
        id: hitbox
        x: panel.x - root.flare
        y: root.barBottom
        width: panel.width + root.flare * 2
        height: root.open ? panel.height : 0
    }

    Item { // Logical panel geometry, animated
        id: panel
        property real lastW: 200
        readonly property bool expanded: height > 1

        // Center, width and height share one curve so a swap moves and
        // resizes in a single motion. x is derived, never animated on its own.
        property real cx: root.targetCx
        width: Math.max(root.shown ? root.targetW : lastW * 0.5, 1)
        height: root.shown ? Math.max(root.targetH, 0) : 0
        x: cx - width / 2
        y: root.barBottom
        onWidthChanged: if (root.popup && root.shown) lastW = root.targetW

        component MorphAnim: NumberAnimation {
            duration: root.closing ? 340 : 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: !root.closing ? Appearance.animationCurves.expressiveDefaultSpatial
                : Appearance.animationCurves.emphasized
        }
        Behavior on cx {
            enabled: panel.expanded
            MorphAnim {}
        }
        Behavior on width {
            MorphAnim {}
        }
        Behavior on height {
            MorphAnim {}
        }
    }

    Item { // Clips everything above the bar edge so it merges with the bar
        id: clipper
        x: panel.x - root.flare - root.shadowPad
        y: root.barBottom - 1
        width: panel.width + (root.flare + root.shadowPad) * 2
        height: panel.height + root.shadowPad + 1
        clip: true

        readonly property real ox: root.flare + root.shadowPad
        readonly property real visH: Math.max(0, panel.height)
        readonly property real flareSize: Math.min(root.flare, visH)

        StyledRectangularShadow {
            target: bg
            visible: clipper.visH > 2
        }

        Rectangle {
            id: bg
            x: clipper.ox
            y: -root.radius
            width: panel.width
            height: clipper.visH + root.radius + 1
            radius: Math.min(root.radius, height / 2)
            color: Appearance.colors.colLayer0

            HoverHandler {
                onHoveredChanged: BarPopoutState.popoutHovered = hovered
            }

            Item {
                id: contentHolder
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: clipper.visH
                clip: true
            }
        }

        RoundCorner { // left flare
            x: clipper.ox - implicitSize
            y: 0
            implicitSize: clipper.flareSize
            visible: implicitSize > 0.5
            color: Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopRight
        }
        RoundCorner { // right flare
            x: clipper.ox + panel.width
            y: 0
            implicitSize: clipper.flareSize
            visible: implicitSize > 0.5
            color: Appearance.colors.colLayer0
            corner: RoundCorner.CornerEnum.TopLeft
        }
    }
}
