pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * List of songs recognized by SongRec. Clicking an entry searches it on
 * Apple Music; the trailing button opens the original Shazam page.
 */
ColumnLayout {
    id: root
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 8
        Layout.topMargin: 8
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: 600
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: SongRec.running ? Translation.tr("Listening...") : Translation.tr("Recognized songs")
        }

        IconToolbarButton {
            implicitHeight: 28
            implicitWidth: 28
            visible: SongRec.history.length > 0
            text: "delete_sweep"
            onClicked: SongRec.clearHistory()
            StyledToolTip {
                text: Translation.tr("Clear history")
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.margins: 16
        visible: SongRec.history.length === 0
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
        text: Translation.tr("Nothing recognized yet. Hit the music button to listen.")
    }

    ListView {
        id: listView
        Layout.fillWidth: true
        visible: SongRec.history.length > 0
        implicitHeight: Math.min(320, listView.contentHeight + topMargin + bottomMargin)
        clip: true
        topMargin: 4
        bottomMargin: 10
        spacing: 2
        model: ScriptModel {
            values: SongRec.history
        }

        delegate: RippleButton {
            id: songItem
            required property var modelData
            required property int index

            anchors.left: parent?.left
            anchors.right: parent?.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10

            implicitHeight: songRow.implicitHeight + 12
            buttonRadius: Appearance.rounding.normal
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1)
            colBackgroundHover: Appearance.colors.colPrimaryContainer
            colRipple: Appearance.colors.colPrimaryContainerActive
            readonly property bool selected: songItem.hovered
            property color colForeground: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

            onClicked: {
                Qt.openUrlExternally(SongRec.appleMusicUrl(songItem.modelData));
                GlobalStates.overviewOpen = false;
            }
            altAction: () => SongRec.removeFromHistory(songItem.index)

            StyledToolTip {
                text: Translation.tr("Search on Apple Music | Right-click to remove")
            }

            contentItem: RowLayout {
                id: songRow
                spacing: 10

                MaterialSymbol {
                    Layout.leftMargin: 6
                    iconSize: 22
                    color: songItem.colForeground
                    text: "music_note"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: songItem.colForeground
                        elide: Text.ElideRight
                        text: songItem.modelData.title ?? ""
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        text: songItem.modelData.subtitle ?? ""
                    }
                }

                IconToolbarButton {
                    implicitHeight: 30
                    implicitWidth: 30
                    visible: (songItem.modelData.url ?? "") !== ""
                    text: "open_in_new"
                    onClicked: {
                        Qt.openUrlExternally(songItem.modelData.url);
                        GlobalStates.overviewOpen = false;
                    }
                    StyledToolTip {
                        text: Translation.tr("Open on Shazam")
                    }
                }

                IconToolbarButton {
                    Layout.rightMargin: 4
                    implicitHeight: 30
                    implicitWidth: 30
                    text: "delete"
                    colText: songItem.hovered ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    onClicked: SongRec.removeFromHistory(songItem.index)
                    StyledToolTip {
                        text: Translation.tr("Remove from history")
                    }
                }
            }
        }
    }
}
