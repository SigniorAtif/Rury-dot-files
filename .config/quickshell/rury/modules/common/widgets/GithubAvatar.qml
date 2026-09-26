import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

// Draws a GitHub user's avatar from a local cache, so there is something on
// screen immediately and while offline. A fetch runs in the background; only
// when the picture has actually changed does the new one crossfade in.
//
// `loaded` stays false until a picture is really on screen, so callers can
// fall back to their own icon on a first run with nothing cached yet.
Item {
    id: root

    property string user: ""
    property int pixelSize: 128
    property real refreshHours: 6

    readonly property string cachePath: FileUtils.trimFileProtocol(`${Directories.cache}/user/github-avatar.png`)
    readonly property url cacheUrl: `file://${root.cachePath}`
    readonly property bool loaded: base.status === Image.Ready

    // Set while the new picture is fading over the old one.
    property bool swapping: false

    function refresh(): void {
        if (root.user !== "")
            fetchProcess.running = true;
    }

    // A new username is a new picture, so go and get it rather than waiting
    // for the next scheduled fetch.
    onUserChanged: root.refresh()

    // Something else has written a new picture into the cache.
    Connections {
        target: GlobalStates
        function onGithubAvatarReloadRequestChanged() {
            root.reload(incoming);
        }
    }

    // Qt keeps images keyed by url, and the path never changes, so clearing
    // the source first is what forces a re-read from disk.
    function reload(image: Image): void {
        image.source = "";
        image.source = root.cacheUrl;
    }

    Image {
        id: base
        anchors.fill: parent
        source: root.cacheUrl
        cache: false
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.pixelSize
        sourceSize.height: root.pixelSize
        smooth: true
        asynchronous: true

        onStatusChanged: {
            // The new picture is on the base layer now; drop the overlay.
            if (root.swapping && base.status === Image.Ready) {
                incoming.opacity = 0;
                incoming.source = "";
                root.swapping = false;
            }
        }
    }

    Image {
        id: incoming
        anchors.fill: parent
        cache: false
        opacity: 0
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.pixelSize
        sourceSize.height: root.pixelSize
        smooth: true
        asynchronous: true

        onStatusChanged: if (incoming.status === Image.Ready) crossfade.restart()
    }

    NumberAnimation {
        id: crossfade
        target: incoming
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        onFinished: {
            root.swapping = true;
            root.reload(base);
        }
    }

    Process {
        id: fetchProcess
        command: ["bash", Quickshell.shellPath("scripts/github-avatar.sh"), root.user, String(root.pixelSize)]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "changed")
                    root.reload(incoming);
            }
        }
    }

    Timer {
        interval: Math.max(1, root.refreshHours) * 60 * 60 * 1000
        repeat: true
        running: root.user !== ""
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
