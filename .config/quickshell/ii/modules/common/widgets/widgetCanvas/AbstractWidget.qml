import QtQuick
import Quickshell
import qs.modules.common

/*
 * Widget to be placed on a WidgetCanvas
 */
MouseArea {
    id: root

    property alias animateXPos: xBehavior.enabled
    property alias animateYPos: yBehavior.enabled
    // Widgets that travel a long way (e.g. the clock centring on lock) can
    // shorten this so the move doesn't read as sluggish
    property int moveDuration: Appearance.animation.elementMove.duration
    property list<real> moveCurve: Appearance.animation.elementMove.bezierCurve
    property bool draggable: true
    drag.target: draggable ? root : undefined
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    Behavior on x {
        id: xBehavior
        NumberAnimation {
            duration: root.moveDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.moveCurve
        }
    }
    Behavior on y {
        id: yBehavior
        NumberAnimation {
            duration: root.moveDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.moveCurve
        }
    }
}
