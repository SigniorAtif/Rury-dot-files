pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Media popout: spinning cover inside a live radial visualizer, track info,
// wavy seek bar and controls. Colors adapt to the cover art.
StyledPopup {
    id: root
    padding: 14

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: player?.isPlaying ?? false

    // Cover art download (same cache as the media controls panel)
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(artUrl)}`
    property bool downloaded: false
    readonly property string artSource: (downloaded && artUrl.length > 0) ? Qt.resolvedUrl(artFilePath) : ""
    onArtFilePathChanged: {
        if (artUrl.length === 0) return;
        downloaded = false;
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.running = true;
    }
    property Process artDownloader: Process {
        id: artDownloader
        property string targetFile
        property string artFilePath
        command: ["bash", "-c", `[ -f '${artFilePath}' ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: root.downloaded = true
    }

    property ColorQuantizer quantizer: ColorQuantizer {
        id: quantizer
        source: root.artSource
        depth: 0
        rescaleSize: 1
    }
    property color artColor: artSource.length > 0 && quantizer.colors.length > 0
        ? ColorUtils.mix(quantizer.colors[0], Appearance.colors.colPrimaryContainer, 0.75)
        : Appearance.m3colors.m3secondaryContainer
    property QtObject scheme: AdaptedMaterialScheme {
        color: root.artColor
    }

    // Visualizer (only while visible and playing)
    property list<real> bars: []
    property Process cavaProc: Process {
        running: root.shownInShared && root.playing
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: if (!running) root.bars = []
        stdout: SplitParser {
            onRead: data => {
                root.bars = data.split(";").map(p => parseFloat(p)).filter(p => !isNaN(p));
            }
        }
    }

    property Timer positionTimer: Timer { // Keep position fresh
        running: root.shownInShared && root.playing
        interval: 500
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    component Reveal: OpenReveal {
        open: root.shownInShared
        fromY: 10
        fromScale: 0.97
    }

    component ControlButton: RippleButton {
        id: btn
        property string iconName
        property real iconSize: Appearance.font.pixelSize.huge
        property bool active: false
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: height / 2
        colBackground: active ? root.scheme.colSecondaryContainer : ColorUtils.transparentize(root.scheme.colSecondaryContainer, 1)
        colBackgroundHover: root.scheme.colSecondaryContainerHover
        colRipple: root.scheme.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            text: btn.iconName
            fill: 1
            iconSize: btn.iconSize
            horizontalAlignment: Text.AlignHCenter
            color: btn.active ? root.scheme.colOnSecondaryContainer : root.scheme.colOnLayer1
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: 470
        implicitHeight: 176
        radius: Appearance.rounding.large
        color: root.scheme.colLayer1
        clip: true
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Soft blurred cover backdrop
        Image {
            id: backdrop
            anchors.fill: parent
            source: root.artSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: backdrop
            visible: root.artSource.length > 0
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
            opacity: 0.35
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            Item { // Cover + radial visualizer
                id: disc
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 152
                implicitHeight: 152
                property Reveal reveal: Reveal { target: disc; fromScale: 0.85; fromY: 0 }

                readonly property real coverSize: 100
                readonly property int barCount: 48

                Repeater {
                    model: disc.barCount
                    delegate: Item {
                        id: barSlot
                        required property int index
                        anchors.centerIn: parent
                        width: 3
                        height: disc.width
                        rotation: index * 360 / disc.barCount
                        // mirror the spectrum so the ring is symmetric
                        readonly property int src: {
                            const half = disc.barCount / 2;
                            const i = index < half ? index : disc.barCount - 1 - index;
                            return Math.floor(i * Math.max(root.bars.length, 1) / half);
                        }
                        readonly property real level: Math.min(1, (root.bars[src] ?? 0) / 1000)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (disc.width - disc.coverSize) / 2 - 4 - height
                            width: 3
                            radius: 1.5
                            height: 3 + barSlot.level * ((disc.width - disc.coverSize) / 2 - 8)
                            color: root.scheme.colPrimary
                            opacity: 0.45 + barSlot.level * 0.55
                            Behavior on height {
                                NumberAnimation { duration: 70 }
                            }
                        }
                    }
                }

                Rectangle { // Cover
                    id: cover
                    anchors.centerIn: parent
                    width: disc.coverSize
                    height: disc.coverSize
                    radius: width / 2
                    color: root.scheme.colSecondaryContainer
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.artSource.length === 0
                        text: "music_note"
                        iconSize: 40
                        color: root.scheme.colOnSecondaryContainer
                    }
                    Image {
                        anchors.fill: parent
                        source: root.artSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 200
                        sourceSize.height: 200
                    }

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 14000
                        loops: Animation.Infinite
                        running: root.playing && root.shownInShared
                    }
                }
                Item {
                    id: coverMask
                    anchors.fill: cover
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                    }
                }
                Rectangle { // Spindle
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: root.scheme.colLayer1
                    border.width: 2
                    border.color: ColorUtils.transparentize(root.scheme.colOnLayer1, 0.7)
                }
            }

            ColumnLayout {
                id: infoColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                property Reveal reveal: Reveal { target: infoColumn; delay: 50; fromX: 12; fromY: 0 }

                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Nothing playing")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: root.scheme.colOnLayer1
                    animateChange: true
                    animationDistanceX: 8
                    animationDistanceY: 0
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.player?.trackArtist ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.scheme.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.player?.trackAlbum ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.scheme.colSubtext
                }

                Item { Layout.fillHeight: true }

                Item { // Seek bar
                    Layout.fillWidth: true
                    implicitHeight: 24
                    Loader {
                        anchors.fill: parent
                        active: root.player?.canSeek ?? false
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            highlightColor: root.scheme.colPrimary
                            trackColor: root.scheme.colSecondaryContainer
                            handleColor: root.scheme.colPrimary
                            usePercentTooltip: false
                            value: root.player?.length > 0 ? root.player.position / root.player.length : 0
                            onMoved: root.player.position = value * root.player.length
                        }
                    }
                    Loader {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        active: !(root.player?.canSeek ?? false)
                        sourceComponent: StyledProgressBar {
                            wavy: root.playing
                            highlightColor: root.scheme.colPrimary
                            trackColor: root.scheme.colSecondaryContainer
                            value: root.player?.length > 0 ? root.player.position / root.player.length : 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.scheme.colSubtext
                    }
                    Item { Layout.fillWidth: true }

                    ControlButton {
                        visible: root.player?.shuffleSupported ?? false
                        iconName: "shuffle"
                        iconSize: Appearance.font.pixelSize.larger
                        active: root.player?.shuffle ?? false
                        downAction: () => root.player.shuffle = !root.player.shuffle
                    }
                    ControlButton {
                        iconName: "skip_previous"
                        downAction: () => root.player?.previous()
                    }
                    RippleButton { // Play/pause morphs between circle and squircle
                        implicitWidth: 46
                        implicitHeight: 40
                        buttonRadius: root.playing ? Appearance.rounding.normal : height / 2
                        colBackground: root.scheme.colPrimary
                        colBackgroundHover: root.scheme.colPrimaryHover
                        colRipple: root.scheme.colPrimaryActive
                        downAction: () => root.player?.togglePlaying()
                        contentItem: MaterialSymbol {
                            text: root.playing ? "pause" : "play_arrow"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.huge
                            horizontalAlignment: Text.AlignHCenter
                            color: root.scheme.colOnPrimary
                        }
                    }
                    ControlButton {
                        iconName: "skip_next"
                        downAction: () => root.player?.next()
                    }
                    ControlButton {
                        visible: root.player?.loopSupported ?? false
                        iconName: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                        iconSize: Appearance.font.pixelSize.larger
                        active: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                        downAction: () => {
                            const s = root.player.loopState;
                            root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                                : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
                        }
                    }

                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.player?.length ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.scheme.colSubtext
                    }
                }

                RowLayout { // Player chip + pin hint
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        visible: (root.player?.identity ?? "").length > 0
                        implicitWidth: chipRow.implicitWidth + 16
                        implicitHeight: chipRow.implicitHeight + 6
                        radius: height / 2
                        color: root.scheme.colSecondaryContainer
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: "graphic_eq"
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.scheme.colOnSecondaryContainer
                            }
                            StyledText {
                                text: root.player?.identity ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.scheme.colOnSecondaryContainer
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    MaterialSymbol {
                        text: "keep"
                        visible: BarPopoutState.pinned === root
                        fill: 1
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.scheme.colSubtext
                    }
                }
            }
        }
    }
}
