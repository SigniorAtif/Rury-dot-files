pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Decorative lock screen extras: greeting, now playing, notification chip.
// Loaded through a Loader in LockSurface so a problem here can never take the
// password field down with it.
Item {
    id: root

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hasMedia: (player?.trackTitle ?? "").length > 0
    readonly property int hour: DateTime.clock.date.getHours()
    readonly property string greeting: hour < 5 ? Translation.tr("Good night")
        : hour < 12 ? Translation.tr("Good morning")
        : hour < 18 ? Translation.tr("Good afternoon")
        : Translation.tr("Good evening")

    // Comes in on lock, scatters away from the centre on unlock
    component Reveal: OpenReveal {
        open: !GlobalStates.screenUnlocking
        speed: 1.1
        animateOut: true
        toScale: 1
    }

    // Soft top gradient so the text stays readable on any wallpaper
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 220
        opacity: GlobalStates.screenUnlocking ? 0 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveExit.numberAnimation.createObject(this)
        }
        gradient: Gradient {
            GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.55) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // Greeting (top left)
    ColumnLayout {
        id: greetingBlock
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 36
            topMargin: 30
        }
        spacing: 0
        property Reveal reveal: Reveal { target: greetingBlock; fromX: -30; fromY: 0; delay: 80; toX: -90; toY: -70 }

        StyledText {
            text: root.greeting + ","
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
            opacity: 0.8
        }
        StyledText {
            text: SystemInfo.username
            font.family: Appearance.font.family.expressive
            font.pixelSize: 34
            font.weight: Font.Bold
            color: Appearance.colors.colPrimary
        }
    }

    // Notifications chip (top right)
    Rectangle {
        id: notifChip
        visible: Notifications.list.length > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 36
            topMargin: 36
        }
        implicitWidth: notifRow.implicitWidth + 24
        implicitHeight: notifRow.implicitHeight + 14
        radius: height / 2
        color: Appearance.m3colors.m3surfaceContainer
        property Reveal reveal: Reveal { target: notifChip; fromX: 30; fromY: 0; delay: 140; toX: 90; toY: -70 }

        RowLayout {
            id: notifRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: "notifications"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Notifications.list.length === 1 ? Translation.tr("1 notification")
                    : Translation.tr("%1 notifications").arg(Notifications.list.length)
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    // Now playing (top center)
    Rectangle {
        id: mediaPill
        visible: root.hasMedia
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 28
        }
        implicitWidth: Math.min(460, mediaRow.implicitWidth + 20)
        implicitHeight: 64
        radius: height / 2
        color: Appearance.m3colors.m3surfaceContainer
        property Reveal reveal: Reveal { target: mediaPill; fromY: -30; delay: 200; toY: -110 }

        RowLayout {
            id: mediaRow
            anchors {
                fill: parent
                leftMargin: 8
                rightMargin: 12
            }
            spacing: 10

            Item { // Spinning cover
                implicitWidth: 48
                implicitHeight: 48
                Rectangle {
                    id: art
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colSecondaryContainer
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: artMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 24
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    Image {
                        anchors.fill: parent
                        source: root.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 96
                        sourceSize.height: 96
                    }
                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 12000
                        loops: Animation.Infinite
                        running: root.player?.isPlaying ?? false
                    }
                }
                Item {
                    id: artMask
                    anchors.fill: art
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 260
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || ""
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    animateChange: true
                    animationDistanceX: 6
                    animationDistanceY: 0
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.player?.trackArtist ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: height / 2
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                downAction: () => root.player?.previous()
                contentItem: MaterialSymbol {
                    text: "skip_previous"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: (root.player?.isPlaying ?? false) ? Appearance.rounding.normal : height / 2
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                downAction: () => root.player?.togglePlaying()
                contentItem: MaterialSymbol {
                    text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnPrimary
                }
            }
            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: height / 2
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                downAction: () => root.player?.next()
                contentItem: MaterialSymbol {
                    text: "skip_next"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
