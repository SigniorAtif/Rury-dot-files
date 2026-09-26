pragma Singleton
import QtQuick
import Quickshell

// Shared state for the bar popout: one panel that morphs between whichever
// StyledPopup is currently hovered (Caelestia-style).
Singleton {
    id: root

    property var current: null // StyledPopup being shown
    property var pinned: null // StyledPopup kept open without hover
    property bool popoutHovered: false

    function show(popup) {
        hideTimer.stop();
        root.current = popup;
    }

    function requestHide(popup) {
        if (root.current === popup)
            hideTimer.restart();
    }

    function togglePin(popup) {
        if (root.pinned === popup) {
            root.pinned = null;
            requestHide(popup);
        } else {
            root.pinned = popup;
            show(popup);
        }
    }

    function close() {
        root.pinned = null;
        root.current = null;
    }

    onPopoutHoveredChanged: {
        if (popoutHovered)
            hideTimer.stop();
        else if (root.current)
            hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: {
            const c = root.current;
            if (!c || root.popoutHovered || root.pinned === c || c.active)
                return;
            root.current = root.pinned; // fall back to a pinned popup, if any
        }
    }
}
