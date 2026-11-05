import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Qt5Compat.GraphicalEffects

// One wallpaper in the gallery: its thumbnail, a check on the current one, and its tags while hovered
MouseArea {
    id: root
    required property var entry
    required property string thumbnailSizeName
    property bool selected: false
    property int thumbnailRevision: 0
    readonly property bool isCurrent: entry.path === FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
    readonly property list<string> tags: entry.tags.length > 0 ? entry.tags.split(" ") : []

    signal activated()

    hoverEnabled: true
    onClicked: root.activated()

    Rectangle {
        id: background
        anchors {
            fill: parent
            margins: Appearance.sizes.wallpaperSelectorItemMargins
        }
        radius: Appearance.rounding.normal
        color: (root.selected || root.containsMouse) ? Appearance.colors.colPrimary : root.isCurrent ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
        // Lift on hover, squish on press
        scale: root.pressed ? 0.95 : root.containsMouse ? 1.04 : 1
        Behavior on scale {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Item {
            id: imageContainer
            anchors {
                fill: parent
                margins: Appearance.sizes.wallpaperSelectorItemPadding
            }

            ThumbnailImage {
                id: thumbnail
                anchors.fill: parent
                sourcePath: root.entry.path
                generateThumbnail: false // The gallery makes them for the whole folder at once
                thumbnailSizeName: root.thumbnailSizeName
                cache: false
                fillMode: Image.PreserveAspectCrop

                // A new wallpaper has no thumbnail until the gallery's run gets to it
                Connections {
                    target: root
                    function onThumbnailRevisionChanged() {
                        if (thumbnail.status !== Image.Error) return;
                        thumbnail.source = "";
                        thumbnail.source = thumbnail.thumbnailPath;
                    }
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: imageContainer.width
                        height: imageContainer.height
                        radius: Appearance.rounding.small
                    }
                }
            }

            MaterialSymbol {
                visible: thumbnail.status !== Image.Ready
                anchors.centerIn: parent
                text: "image"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }

            Rectangle { // Current wallpaper badge
                visible: root.isCurrent
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 6
                }
                implicitWidth: 26
                implicitHeight: 26
                radius: 13
                color: Appearance.colors.colPrimary
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }

            Rectangle { // Tags
                visible: root.containsMouse && root.tags.length > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitHeight: tagText.implicitHeight + 10
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.35)

                StyledText {
                    id: tagText
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 8
                        rightMargin: 8
                    }
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: "white"
                    text: root.tags.join("  ").replace(/_/g, " ")
                }
            }
        }
    }
}
