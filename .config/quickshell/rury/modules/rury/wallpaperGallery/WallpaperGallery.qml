import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// The Classwork wallpapers as a grid you can search by tag (Super+Shift+H)
Scope {
    id: root
    property bool open: false

    Loader {
        active: root.open

        sourceComponent: PanelWindow {
            id: panelWindow

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperGallery"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.open = false;
                }
            }

            WallpaperGalleryContent {
                id: content
                anchors.fill: parent
                thumbnailRevision: root.thumbnailRevision
                thumbnailsRunning: thumbsProc.running
                onClosed: root.open = false
                onThumbnailsNeeded: sizeName => root.makeThumbnails(sizeName)
            }
        }
    }

    // Makes only the missing thumbnails, with the same scripts the selector uses. It runs
    // out here so a first run over big images can finish after the gallery is closed.
    property int thumbnailRevision: 0
    function makeThumbnails(sizeName) {
        if (thumbsProc.running) return;
        thumbsProc.command = ["bash", "-c", '"$1" --size "$3" --machine_progress -d "$4" || "$2" --size "$3" -d "$4"', "thumbnails", Wallpapers.thumbgenScriptPath, Wallpapers.generateThumbnailsMagickScriptPath, sizeName, Directories.classworkWallpapers];
        thumbsProc.running = true;
    }
    Process {
        id: thumbsProc
        stdout: SplitParser {
            onRead: data => {
                if (/FILE .+/.test(data)) root.thumbnailRevision++;
            }
        }
        onExited: root.thumbnailRevision++
    }

    IpcHandler {
        target: "wallpaperGallery"

        function toggle(): void {
            root.open = !root.open;
        }
    }

    GlobalShortcut {
        name: "wallpaperGalleryToggle"
        description: "Toggle the Classwork wallpaper gallery"
        onPressed: root.open = !root.open
    }
}
