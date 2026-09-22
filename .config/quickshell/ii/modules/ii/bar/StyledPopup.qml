import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Bar popup. On a horizontal bar its content is shown inside the shared
// BarPopoutHost panel, which is attached to the bar and morphs between popups.
// Otherwise (vertical bar, or `shared: false`) it falls back to its own window.
Item {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0
    property bool active: hoverTarget ? hoverTarget.containsMouse : false
    property bool shared: !Config.options.bar.vertical
    property real padding: 10

    readonly property bool shownInShared: shared && BarPopoutState.current === root

    visible: false
    width: 0
    height: 0

    onActiveChanged: {
        if (!shared) return;
        if (active) BarPopoutState.show(root);
        else BarPopoutState.requestHide(root);
    }
    Component.onDestruction: {
        if (BarPopoutState.current === root) BarPopoutState.current = null;
        if (BarPopoutState.pinned === root) BarPopoutState.pinned = null;
    }

    // Holds the content; reparented into the shared host or the fallback window.
    property Item page: Item {
        id: page
        implicitWidth: root.contentItem ? root.contentItem.implicitWidth + root.padding * 2 : 0
        implicitHeight: root.contentItem ? root.contentItem.implicitHeight + root.padding * 2 : 0
        width: implicitWidth
        height: implicitHeight
        children: root.contentItem ? [root.contentItem] : []

        // Shared-mode fade/zoom when popups swap
        opacity: (!root.shared || root.shownInShared) ? 1 : 0
        scale: (!root.shared || root.shownInShared) ? 1 : 0.92
        visible: opacity > 0
        transformOrigin: Item.Top
        Behavior on opacity {
            enabled: root.shared
            NumberAnimation {
                duration: root.shownInShared ? 260 : 140
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        Behavior on scale {
            enabled: root.shared
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    LazyLoader {
        active: !root.shared && root.active

        component: PanelWindow {
            id: popupWindow
            color: "transparent"

            anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
            anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
            anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
            anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

            mask: Region {
                item: popupBackground
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                left: {
                    if (!Config.options.bar.vertical) return root.QsWindow?.mapFromItem(
                        root.hoverTarget,
                        (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                    ).x;
                    return Appearance.sizes.verticalBarWidth
                }
                top: {
                    if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                    return root.QsWindow?.mapFromItem(
                        root.hoverTarget,
                        (root.hoverTarget.height - popupBackground.implicitHeight) / 2, 0
                    ).y;
                }
                right: Appearance.sizes.verticalBarWidth
                bottom: Appearance.sizes.barHeight
            }
            WlrLayershell.namespace: "quickshell:popup"
            WlrLayershell.layer: WlrLayer.Overlay

            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors {
                    fill: parent
                    leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                    rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                    topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                    bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
                }
                implicitWidth: root.page.implicitWidth
                implicitHeight: root.page.implicitHeight
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                children: [root.page]

                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
