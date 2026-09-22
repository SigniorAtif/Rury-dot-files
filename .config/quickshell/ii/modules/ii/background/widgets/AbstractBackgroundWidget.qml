import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    // The unlock exit counts as unlocked: widgets come back while the backdrop
    // un-blurs, not once the lock surface has gone. Held back a beat so the
    // backdrop clears first and the clock is still moving when the bar slides in.
    readonly property bool lockActive: GlobalStates.screenLocked && !GlobalStates.screenUnlocking
    property int unlockLag: 180
    property bool lockShown: GlobalStates.screenLocked
    onLockActiveChanged: {
        if (lockActive) { // Locking is immediate; only the exit lingers
            unlockLagTimer.stop();
            lockShown = true;
        } else {
            unlockLagTimer.restart();
        }
    }
    Timer {
        id: unlockLagTimer
        interval: root.unlockLag
        onTriggered: root.lockShown = false
    }
    visible: opacity > 0
    opacity: (lockShown && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free"
    onReleased: {
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (root.lockShown && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    // Placement engine ported from the Fedora (Oct 2025) Background.qml:
    // search for a region the size of the actual widget (plus margin) and keep
    // it out of the part of the wallpaper that parallax can scroll off-screen.
    readonly property real widgetSizePadding: 20
    readonly property real screenSizePadding: 50
    property real wallpaperZoom: 1 // Background's parallax workspaceZoom
    property real movableXSpace: 0 // Half the horizontal parallax travel, in screen px
    property real movableYSpace: 0 // Half the vertical parallax travel, in screen px
    property real lastPlacedWidth: 0
    property real lastPlacedHeight: 0

    onWidthChanged: placementSizeTimer.restart()
    onHeightChanged: placementSizeTimer.restart()
    onMovableXSpaceChanged: placementSizeTimer.restart()
    onMovableYSpaceChanged: placementSizeTimer.restart()
    Timer {
        id: placementSizeTimer
        interval: 400
        onTriggered: {
            // The lock screen resizes widgets (the "Locked" chip), and replacing
            // them for that means a second, pointless move once they've landed
            if (GlobalStates.screenLocked || GlobalStates.screenUnlocking) return;
            // Ignore tiny size changes (e.g. digits ticking) to avoid jitter
            if (Math.abs(root.width - root.lastPlacedWidth) < 24 && Math.abs(root.height - root.lastPlacedHeight) < 24) return;
            root.refreshPlacementIfNeeded();
        }
    }

    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        if (root.width <= 0 || root.height <= 0) return; // Size unknown yet; the size timer retries
        root.lastPlacedWidth = root.width;
        root.lastPlacedHeight = root.height;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.contentWidth = Math.round((root.width + root.widgetSizePadding * 2) / root.wallpaperZoom);
        leastBusyRegionProc.contentHeight = Math.round((root.height + root.widgetSizePadding * 2) / root.wallpaperZoom);
        leastBusyRegionProc.horizontalPadding = Math.round((root.movableXSpace + root.screenSizePadding * 2) / root.wallpaperZoom);
        leastBusyRegionProc.verticalPadding = Math.round((root.movableYSpace + root.screenSizePadding * 2) / root.wallpaperZoom);
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 100
        property int verticalPadding: 100
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth / root.wallpaperZoom) //
            , "--screen-height", Math.round(root.scaledScreenHeight / root.wallpaperZoom) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperZoom * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperZoom * root.wallpaperScale - root.height / 2;
            }
        }
    }
}

