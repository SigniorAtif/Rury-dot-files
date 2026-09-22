pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext

    // Staged unlock: the lock UI leaves, whatever's underneath gets put back
    // (see unlockStarted), and only then does the session lock surface go away.
    // Unlocking in one step showed a frame of the wrong workspace.
    signal unlockStarted()
    // Only as long as the lock UI itself needs to leave: the islands are gone
    // after 250ms (elementMoveExit 200ms over speed 0.8). The backdrop's blur
    // fade is 400ms but lives on the background layer, so it keeps going after
    // the surface unmaps -- holding the surface up for it just delayed the
    // workspace slide until the clock had already landed.
    readonly property int exitDuration: 260

    Timer {
        id: exitTimer
        interval: root.exitDuration
        onTriggered: root.finishUnlock()
    }
    function finishUnlock() {
        // Unlock first: a failure below must never stand between you and your session
        GlobalStates.screenLocked = false;
        GlobalStates.screenUnlocking = false;
        lockContext.reset();
        if (lockContext.alsoInhibitIdle) {
            lockContext.alsoInhibitIdle = false;
            Idle.toggleInhibit(true);
        }
    }
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            active: GlobalStates.screenLocked
            anchors.fill: parent
            opacity: active ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.screenUnlocking = false; // Locked again mid-exit
                    exitTimer.stop();
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            if (GlobalStates.screenUnlocking) return; // Already on the way out

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // Play the exit while the surface still covers the screen
            GlobalStates.screenUnlocking = true;
            root.unlockStarted();
            exitTimer.restart();
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
