import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

StyledPopup {
    id: root
    padding: 12

    readonly property real pct: Battery.percentage
    readonly property bool low: Battery.isLow && !Battery.isCharging
    readonly property color accent: low ? Appearance.m3colors.m3error : Appearance.colors.colPrimary

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    readonly property string statusText: {
        if (Battery.chargeState == UPowerDeviceState.FullyCharged) return Translation.tr("Fully charged");
        const t = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
        const hasTime = t > 0 && Battery.energyRate > 0.01;
        if (Battery.isCharging)
            return hasTime ? Translation.tr("%1 until full").arg(formatTime(t)) : Translation.tr("Charging");
        return hasTime ? Translation.tr("%1 left").arg(formatTime(t)) : Translation.tr("On battery");
    }

    component Reveal: OpenReveal {
        open: root.shownInShared
        fromY: 10
        fromScale: 0.97
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10

        RowLayout { // Big battery
            id: headRow
            spacing: 14
            property Reveal reveal: Reveal { target: headRow }

            Item { // Battery body
                implicitWidth: 92
                implicitHeight: 44
                Rectangle {
                    id: body
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        right: nub.left
                        rightMargin: 2
                    }
                    radius: 12
                    color: Appearance.colors.colSecondaryContainer
                    clip: true

                    Rectangle { // Fill
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: parent.width * (root.shownInShared ? root.pct : 0)
                        radius: parent.radius
                        color: root.accent
                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: Battery.isCharging
                        text: "bolt"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnPrimary
                        SequentialAnimation on opacity {
                            running: Battery.isCharging && root.shownInShared
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                }
                Rectangle {
                    id: nub
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    implicitWidth: 5
                    implicitHeight: 16
                    radius: 2
                    color: Appearance.colors.colSecondaryContainer
                }
            }

            ColumnLayout {
                spacing: 0
                StyledText {
                    text: `${Math.round(root.pct * 100)}%`
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    color: root.accent
                }
                StyledText {
                    text: root.statusText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout { // Stats chips
            id: chipRow
            Layout.fillWidth: true
            spacing: 6
            property Reveal reveal: Reveal { target: chipRow; delay: 40 }

            Repeater {
                model: [
                    { icon: "bolt", text: Battery.energyRate > 0.01 ? `${Battery.energyRate.toFixed(1)} W` : "—" },
                    { icon: "heart_check", text: `${Battery.health.toFixed(0)}%` },
                    { icon: Battery.isPluggedIn ? "power" : "power_off", text: Battery.isPluggedIn ? Translation.tr("Plugged") : Translation.tr("Unplugged") },
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitWidth: chip.implicitWidth + 16
                    implicitHeight: chip.implicitHeight + 10
                    radius: height / 2
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        id: chip
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        Rectangle { // Power profile segmented control with a sliding pill
            id: profiles
            Layout.fillWidth: true
            implicitWidth: 270
            implicitHeight: 44
            radius: height / 2
            color: Appearance.colors.colLayer1
            property Reveal reveal: Reveal { target: profiles; delay: 80 }

            readonly property var options: PowerProfiles.hasPerformanceProfile
                ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                : [PowerProfile.PowerSaver, PowerProfile.Balanced]
            readonly property int currentIndex: Math.max(0, options.indexOf(PowerProfiles.profile))
            readonly property real segW: (width - 8) / options.length

            Rectangle {
                y: 4
                height: parent.height - 8
                width: profiles.segW
                x: 4 + profiles.currentIndex * profiles.segW
                radius: height / 2
                color: Appearance.colors.colPrimary
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            Row {
                anchors.fill: parent
                anchors.margins: 4
                Repeater {
                    model: profiles.options
                    delegate: MouseArea {
                        id: seg
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === profiles.currentIndex
                        width: profiles.segW
                        height: parent.height
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = modelData
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: seg.modelData === PowerProfile.PowerSaver ? "energy_savings_leaf"
                                    : seg.modelData === PowerProfile.Balanced ? "airwave" : "local_fire_department"
                                fill: seg.selected ? 1 : 0
                                iconSize: Appearance.font.pixelSize.larger
                                color: seg.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                            StyledText {
                                visible: seg.selected
                                text: seg.modelData === PowerProfile.PowerSaver ? Translation.tr("Saver")
                                    : seg.modelData === PowerProfile.Balanced ? Translation.tr("Balanced") : Translation.tr("Boost")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
