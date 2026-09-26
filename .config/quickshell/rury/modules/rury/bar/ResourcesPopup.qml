import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    padding: 12

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    component ResourceCard: Rectangle {
        id: card
        required property string icon
        required property string label
        required property real value
        required property string detail
        required property list<real> history
        property real warning: 1
        readonly property bool hot: value >= warning
        readonly property color accent: hot ? Appearance.m3colors.m3error : Appearance.colors.colPrimary

        implicitWidth: 148
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        property OpenReveal reveal: OpenReveal {
            target: card
            open: root.shownInShared
            fromY: 10
            fromScale: 0.96
            delay: Math.max(0, card.Positioner.index) * 40
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            RowLayout {
                spacing: 10
                Item {
                    implicitWidth: 52
                    implicitHeight: 52
                    CircularProgress {
                        anchors.fill: parent
                        implicitSize: 52
                        lineWidth: 5
                        value: card.value
                        colPrimary: card.accent
                        colSecondary: Appearance.colors.colSecondaryContainer
                        enableAnimation: true
                        animationDuration: 600
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.icon
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: card.accent
                    }
                }
                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: `${Math.round(card.value * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: card.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 34
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true
                    Graph {
                        anchors.fill: parent
                        values: card.history
                        points: ResourceUsage.historyLength
                        alignment: Graph.Alignment.Right
                        color: card.accent
                        fillOpacity: 0.25
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: card.detail
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 8

        ResourceCard {
            icon: "planner_review"
            label: Translation.tr("CPU")
            value: ResourceUsage.cpuUsage
            history: ResourceUsage.cpuUsageHistory
            warning: Config.options.bar.resources.cpuWarningThreshold / 100
            detail: ResourceUsage.maxAvailableCpuString !== "--" ? Translation.tr("Max %1").arg(ResourceUsage.maxAvailableCpuString) : Translation.tr("Processor load")
        }
        ResourceCard {
            icon: "memory"
            label: Translation.tr("Memory")
            value: ResourceUsage.memoryUsedPercentage
            history: ResourceUsage.memoryUsageHistory
            warning: Config.options.bar.resources.memoryWarningThreshold / 100
            detail: `${root.formatKB(ResourceUsage.memoryUsed)} / ${root.formatKB(ResourceUsage.memoryTotal)}`
        }
        ResourceCard {
            visible: ResourceUsage.swapTotal > 0
            icon: "swap_horiz"
            label: Translation.tr("Swap")
            value: ResourceUsage.swapUsedPercentage
            history: ResourceUsage.swapUsageHistory
            warning: Config.options.bar.resources.swapWarningThreshold / 100
            detail: `${root.formatKB(ResourceUsage.swapUsed)} / ${root.formatKB(ResourceUsage.swapTotal)}`
        }
    }
}
