import QtQuick
import qs.modules.common

// Replays an entrance animation (fade + slide + slight scale) on `target`
// every time `open` turns true, even when the target stays loaded between opens.
// Optionally plays an exit animation too; bind a window's visibility to
// `open || running` to keep it mapped until the exit finishes.
QtObject {
    id: root

    required property Item target
    property bool open: false
    property int delay: 0
    property real fromX: 0
    property real fromY: 16
    property real fromScale: 0.97
    property bool animateOut: false
    property real toX: 0
    property real toY: -8
    property real toScale: fromScale
    property real speed: 1 // >1 = faster
    readonly property bool running: enterAnim.running || exitAnim.running

    property Translate translate: Translate {}
    property Scale scale: Scale {
        origin.x: root.target ? root.target.width / 2 : 0
        origin.y: root.target ? root.target.height / 2 : 0
    }

    function reset() {
        exitAnim.stop();
        if (!target) return; // Target torn down (e.g. popup reloaded)
        target.opacity = 0;
        translate.x = fromX;
        translate.y = fromY;
        scale.xScale = fromScale;
        scale.yScale = fromScale;
    }

    function playIn() {
        reset();
        enterAnim.restart();
    }

    function playOut() {
        enterAnim.stop();
        if (!animateOut) return;
        exitAnim.restart();
    }

    onOpenChanged: open ? playIn() : playOut()

    Component.onCompleted: {
        if (!target) return;
        let transforms = [];
        for (let i = 0; i < target.transform.length; i++)
            transforms.push(target.transform[i]);
        transforms.push(translate, scale);
        target.transform = transforms;
        if (open) playIn();
    }

    property SequentialAnimation enterAnim: SequentialAnimation {
        PauseAnimation {
            duration: root.delay / root.speed
        }
        ParallelAnimation {
            NumberAnimation {
                target: root.target
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration / root.speed
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: root.translate
                properties: "x,y"
                to: 0
                duration: Appearance.animation.elementMove.duration / root.speed
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: root.scale
                properties: "xScale,yScale"
                to: 1
                duration: Appearance.animation.elementMove.duration / root.speed
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    }

    property ParallelAnimation exitAnim: ParallelAnimation {
        NumberAnimation {
            target: root.target
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration / root.speed
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root.translate
            property: "x"
            to: root.toX
            duration: Appearance.animation.elementMoveExit.duration / root.speed
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root.translate
            property: "y"
            to: root.toY
            duration: Appearance.animation.elementMoveExit.duration / root.speed
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root.scale
            properties: "xScale,yScale"
            to: root.toScale
            duration: Appearance.animation.elementMoveExit.duration / root.speed
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }
}
