import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

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
                    source: Qt.resolvedUrl(Quickshell.shellPath("assets/icons/Rury.png"))
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
                Item {
                    id: tagline

                    // The tagline alone sets the slot, so picking a longer
                    // line cannot nudge the section sideways. A wider one
                    // simply overhangs to the right while it is showing.
                    Layout.preferredWidth: plainLabel.implicitWidth
                    Layout.preferredHeight: plainLabel.implicitHeight

                    // 0 is the tagline, 1 is the line about her. One animated
                    // number drives the whole thing; each letter reads its own
                    // slice out of it, which is where the stagger comes from
                    // without a timer per letter.
                    property real reveal: 0

                    readonly property var lines: [
                        "Maintained by me, approved by Rury",
                        "Rury's, technically",
                        "Personal Hyprland desktop \u2014 hers too",
                        "Not personal, actually",
                        "Still her favourite logo",
                        "Now with 100% more Rury",
                        "Rury-certified",
                        "Compiles faster when she's online"
                    ]

                    // Drawn from a shuffled bag rather than at random, so every
                    // line shows once before any of them comes back.
                    property var bag: []
                    property string aside: lines[0]

                    function nextLine(): string {
                        if (tagline.bag.length === 0) {
                            let fresh = tagline.lines.slice();
                            for (let i = fresh.length - 1; i > 0; i--) {
                                const j = Math.floor(Math.random() * (i + 1));
                                [fresh[i], fresh[j]] = [fresh[j], fresh[i]];
                            }
                            // A refill must not hand straight back the line that
                            // just showed, which is the one seam a bag can repeat.
                            if (fresh.length > 1 && fresh[fresh.length - 1] === tagline.aside)
                                [fresh[fresh.length - 1], fresh[0]] = [fresh[0], fresh[fresh.length - 1]];
                            tagline.bag = fresh;
                        }
                        const rest = tagline.bag.slice();
                        const line = rest.pop();
                        tagline.bag = rest;
                        return line;
                    }

                    // Letters in the air at once, kept proportional so a long
                    // line does not race past in the same time a short one takes.
                    readonly property real trail: Math.max(2.5, aside.length * 0.25)

                    // The tagline is out of the way before the first letter
                    // arrives, so the two are never on screen together.
                    readonly property real handover: 0.3
                    readonly property real lettersIn: Math.max(0, (reveal - handover) / (1 - handover))

                    StyledText {
                        id: plainLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -7 * Math.min(1, tagline.reveal / tagline.handover)
                        text: Translation.tr("Personal Hyprland desktop")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        opacity: 1 - Math.min(1, tagline.reveal / tagline.handover)
                    }

                    Item {
                        id: nameRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        width: parent.width
                        height: plainLabel.implicitHeight

                        Repeater {
                            model: tagline.aside.length

                            StyledText {
                                id: letter
                                required property int index

                                // Each letter sits where the whole string would
                                // have put it, so the kerning is the same as one
                                // label; a Row of single characters loses it.
                                TextMetrics {
                                    id: upToHere
                                    font: letter.font
                                    text: tagline.aside.substring(0, letter.index)
                                }

                                // This letter's own 0..1, opening one after
                                // another as the shared number sweeps past.
                                readonly property real t: Math.max(0, Math.min(1,
                                    (tagline.lettersIn * (tagline.aside.length + tagline.trail) - index) / tagline.trail))

                                text: tagline.aside.charAt(index)
                                // Taken whole, so a lone digit cannot flip this
                                // one letter into the number font.
                                font: plainLabel.font
                                // advanceWidth, not width: width drops a
                                // trailing space, which would pull every letter
                                // after a word one space to the left.
                                x: upToHere.advanceWidth
                                y: (1 - t) * 9
                                opacity: t
                                scale: 0.82 + 0.18 * t
                                // Arrives lit and cools into the subtitle colour;
                                // squared so the accent lingers past the fade-in.
                                color: ColorUtils.mix(Appearance.colors.colSubtext, Appearance.m3colors.m3primary, t * t)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        property int taps: 0
                        onClicked: {
                            if (tagline.reveal > 0) return;
                            if (++taps < 3) return;
                            taps = 0;
                            tagline.aside = tagline.nextLine();
                            revealAside.restart();
                        }
                    }

                    SequentialAnimation {
                        id: revealAside
                        NumberAnimation {
                            target: tagline; property: "reveal"; from: 0; to: 1; duration: 850
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                        PauseAnimation { duration: 3200 }
                        NumberAnimation {
                            target: tagline; property: "reveal"; to: 0; duration: 650
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
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
