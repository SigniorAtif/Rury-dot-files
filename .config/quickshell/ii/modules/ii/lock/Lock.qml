pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})

    // Hyprland slides the workspace back in (the slidevert keyword set on lock).
    // Starts with everything else, on the same frame as the islands scatter:
    // the lock surface is transparent and the background drops below the
    // windows the moment the blur starts unwinding, so the slide is on screen
    // straight away rather than hidden until the surface unmaps.
    property int restoreDelay: 0
    Timer {
        id: restoreTimer
        interval: root.restoreDelay
        onTriggered: root.restoreWorkspaces()
    }
    // Over the existing Hyprland socket rather than spawning bash + hyprctl:
    // a fork/exec storm on the first frames of the reveal costs frames.
    function restoreWorkspaces() {
        for (var j = 0; j < Quickshell.screens.length; ++j) {
            var monName = Quickshell.screens[j].name
            var wsId = root.savedWorkspaces[monName]
            if (wsId === undefined) continue;
            Hyprland.dispatch(`hl.dsp.focus({monitor="${monName}"})`)
            Hyprland.dispatch(`hl.dsp.focus({workspace=${wsId}})`)
        }
    }

    onUnlockStarted: restoreTimer.restart()

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                restoreTimer.stop(); // Re-locked mid-exit
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}
