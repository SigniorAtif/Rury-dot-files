import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property bool showPing: false

    // A topLeftIcon with a file extension is a picture in assets/icons, drawn
    // as-is and clipped to a circle. Anything else is a symbolic icon name.
    readonly property string topLeftIcon: Config.options.bar.topLeftIcon
    readonly property bool pictureIcon: root.topLeftIcon.includes(".")

    // A GitHub avatar wins when one is cached; the configured icon stays as
    // the fallback for a first run with nothing fetched yet.
    readonly property bool avatarWanted: Config.options.bar.githubAvatar.enable
        && Config.options.bar.githubAvatar.user !== ""
    readonly property bool avatarShown: root.avatarWanted && githubAvatar.loaded

    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    visible: aiChatEnabled || translatorEnabled || animeEnabled

    property real buttonPadding: 5
    implicitWidth: iconArea.width + buttonPadding * 2
    implicitHeight: iconArea.height + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    // Right click pins the icon settings into the shared bar popout.
    altAction: () => BarPopoutState.togglePin(iconPopup)

    TopLeftIconPopup {
        id: iconPopup
        // BarPopoutHost lines the shared panel up over this item; with no
        // target it skips the popup entirely and nothing is ever drawn.
        hoverTarget: root
        active: false // Right click only, so hovering must not open it
        onRefreshRequested: githubAvatar.refresh()
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    Item {
        id: iconArea
        anchors.centerIn: parent
        width: 19.5
        height: 19.5

        GithubAvatar {
            id: githubAvatar
            anchors.fill: parent
            visible: root.avatarShown
            user: root.avatarWanted ? Config.options.bar.githubAvatar.user : ""
            refreshHours: Config.options.bar.githubAvatar.refreshHours
            pixelSize: 128
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: githubAvatar.width
                    height: githubAvatar.height
                    radius: width / 2
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: !root.pictureIcon && !root.avatarShown
            sourceComponent: CustomIcon {
                source: root.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${root.topLeftIcon}-symbolic`
                colorize: true
                color: Appearance.colors.colOnLayer0
            }
        }

        Loader {
            anchors.fill: parent
            active: root.pictureIcon && !root.avatarShown
            sourceComponent: ClippingRectangle {
                radius: width / 2
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(Quickshell.shellPath(`assets/icons/${root.topLeftIcon}`))
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 64
                    sourceSize.height: 64
                    smooth: true
                    asynchronous: true
                }
            }
        }

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
