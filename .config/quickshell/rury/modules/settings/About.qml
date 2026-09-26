import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")
        
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath(SystemInfo.logo)
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                // spacing: 10
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: SystemInfo.homeUrl
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.documentationUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "support"
                mainText: Translation.tr("Help & Support")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.supportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a Bug")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.bugReportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.privacyPolicyUrl)
                }
            }
            
        }

    }
    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Dotfiles")

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            ClippingRectangle {
                implicitWidth: 80
                implicitHeight: 80
                radius: width / 2
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(Quickshell.shellPath("assets/icons/rury.png"))
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 160
                    sourceSize.height: 160
                    smooth: true
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // StyledToolTip looks for `hovered` on its parent.
                    property bool hovered: containsMouse
                    onClicked: Qt.openUrlExternally("https://github.com/SigniorAtif")

                    StyledToolTip {
                        text: Translation.tr("github.com/SigniorAtif")
                    }
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                // spacing: 10
                StyledText {
                    text: Translation.tr("SigniorAtif")
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    id: tagline
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext

                    readonly property string plain: Translation.tr("Personal Hyprland desktop")
                    // What the shell calls itself, for anyone who pokes at the subtitle.
                    readonly property string aside: Translation.tr("Rury, to those who know it")
                    property bool revealed: false
                    text: tagline.revealed ? tagline.aside : tagline.plain

                    MouseArea {
                        anchors.fill: parent
                        property int taps: 0
                        onClicked: {
                            if (tagline.revealed) return;
                            if (++taps < 3) return;
                            taps = 0;
                            revealAside.restart();
                        }
                    }

                    SequentialAnimation {
                        id: revealAside
                        NumberAnimation {
                            target: tagline; property: "opacity"; to: 0; duration: 120
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        PropertyAction { target: tagline; property: "revealed"; value: true }
                        NumberAnimation {
                            target: tagline; property: "opacity"; to: 1; duration: 180
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                        }
                        PauseAnimation { duration: 3500 }
                        NumberAnimation {
                            target: tagline; property: "opacity"; to: 0; duration: 120
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        PropertyAction { target: tagline; property: "revealed"; value: false }
                        NumberAnimation {
                            target: tagline; property: "opacity"; to: 1; duration: 180
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                        }
                    }
                }
                StyledText {
                    text: Translation.tr("Based on [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4, under the GPL-3.0")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "folder_code"
                mainText: Translation.tr("This repo")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/SigniorAtif/Rury-dot-files")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "code"
                mainText: Translation.tr("Upstream project")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "balance"
                materialIconFill: false
                mainText: Translation.tr("License")
                onClicked: {
                    Qt.openUrlExternally("https://www.gnu.org/licenses/gpl-3.0.html")
                }
            }
        }
    }
}
