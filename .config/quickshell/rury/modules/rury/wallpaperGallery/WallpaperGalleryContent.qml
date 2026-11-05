import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property int columns: 4
    property real previewCellAspectRatio: 16 / 9
    readonly property string directory: Directories.classworkWallpapers
    readonly property string indexScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/random/collection_index.sh`
    // Worked out the way the selector does it, so both use the same thumbnails
    readonly property string thumbnailSizeName: {
        const cellWidth = Appearance.sizes.wallpaperSelectorWidth / root.columns;
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        return Images.thumbnailSizeNameForDimensions(cellWidth - totalImageMargin, cellWidth / root.previewCellAspectRatio - totalImageMargin);
    }

    // The thumbnail run lives in WallpaperGallery.qml, so it keeps going after the gallery closes
    property int thumbnailRevision: 0
    property bool thumbnailsRunning: false

    signal closed()
    signal thumbnailsNeeded(string sizeName)

    // From collection_index.sh: {path, mtime, tags}, newest first
    property var entries: []
    // Space-separated words, each matching part of a tag or the file name; "-word" excludes
    property string query: ""
    readonly property var shown: {
        const terms = root.query.toLowerCase().split(/\s+/).filter(term => term.length > 0);
        return root.entries.filter(entry => {
            const tags = entry.tags.toLowerCase().split(" ");
            const name = FileUtils.fileNameForPath(entry.path).toLowerCase();
            return terms.every(term => {
                const exclude = term.length > 1 && term.startsWith("-");
                const word = exclude ? term.slice(1) : term;
                const found = name.includes(word) || tags.some(tag => tag.includes(word));
                return found !== exclude;
            });
        });
    }

    function apply(entry) {
        if (!entry) return;
        Wallpapers.apply(entry.path, Appearance.m3colors.darkmode);
        root.closed();
    }

    function shuffle() {
        if (root.shown.length === 0) return;
        root.apply(root.shown[Math.floor(Math.random() * root.shown.length)]);
    }

    Component.onCompleted: {
        indexProc.running = true;
        filterField.forceActiveFocus();
    }

    Process {
        id: indexProc
        command: ["bash", root.indexScriptPath, root.directory]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text);
                } catch (e) {
                    root.entries = [];
                }
                grid.currentIndex = 0;
                root.thumbnailsNeeded(root.thumbnailSizeName);
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closed();
        } else if (event.key === Qt.Key_Left) {
            grid.moveSelection(-1);
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1);
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns);
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent();
        } else if (event.text.length > 0) {
            filterField.text += event.text;
            filterField.cursorPosition = filterField.text.length;
            filterField.forceActiveFocus();
        } else {
            return;
        }
        event.accepted = true;
    }

    implicitHeight: galleryBackground.implicitHeight
    implicitWidth: galleryBackground.implicitWidth

    StyledRectangularShadow {
        target: galleryBackground
    }
    Rectangle {
        id: galleryBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.bottomMargin: 6
                spacing: 8

                StyledText {
                    font {
                        pixelSize: Appearance.font.pixelSize.normal
                        weight: Font.Medium
                    }
                    text: Translation.tr("Classwork")
                }
                StyledText {
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.shown.length === root.entries.length ? `${root.entries.length}` : Translation.tr("%1 of %2").arg(root.shown.length).arg(root.entries.length)
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledText {
                    visible: root.thumbnailsRunning
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Making thumbnails...")
                }
            }

            Item {
                id: gridDisplayRegion
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledIndeterminateProgressBar {
                    visible: indexProc.running
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        leftMargin: 12
                        rightMargin: 12
                    }
                }

                GridView {
                    id: grid

                    readonly property int columns: root.columns
                    property int currentIndex: 0

                    anchors.fill: parent
                    cellWidth: width / root.columns
                    cellHeight: cellWidth / root.previewCellAspectRatio
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    bottomMargin: galleryToolbar.implicitHeight + 16
                    ScrollBar.vertical: StyledScrollBar {}

                    function moveSelection(delta) {
                        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
                        positionViewAtIndex(currentIndex, GridView.Contain);
                    }

                    function activateCurrent() {
                        root.apply(root.shown[currentIndex]);
                    }

                    model: root.shown
                    onModelChanged: currentIndex = 0

                    delegate: WallpaperGalleryItem {
                        required property var modelData
                        required property int index
                        entry: modelData
                        width: grid.cellWidth
                        height: grid.cellHeight
                        selected: index === grid.currentIndex
                        thumbnailSizeName: root.thumbnailSizeName
                        thumbnailRevision: root.thumbnailRevision

                        onEntered: grid.currentIndex = index
                        onActivated: root.apply(modelData)
                    }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: gridDisplayRegion.width
                            height: gridDisplayRegion.height
                            radius: galleryBackground.radius
                        }
                    }
                }

                PagePlaceholder {
                    anchors.centerIn: parent
                    shown: !indexProc.running && root.shown.length === 0
                    icon: root.entries.length === 0 ? "image_not_supported" : "search_off"
                    title: root.entries.length === 0 ? Translation.tr("Nothing saved here yet") : Translation.tr("Nothing matches")
                    description: root.entries.length === 0 ? Translation.tr("The Save button in settings puts wallpapers here") : Translation.tr("Tags match by part, \"-tag\" leaves one out")
                }

                Row {
                    id: galleryToolbar
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: 8
                    }
                    spacing: 6

                    Toolbar {
                        IconToolbarButton {
                            text: "shuffle"
                            onClicked: root.shuffle()
                            StyledToolTip {
                                text: Translation.tr("Set a random one of these")
                            }
                        }

                        ToolbarTextField {
                            id: filterField
                            placeholderText: Translation.tr("Search tags")
                            clip: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            onTextChanged: root.query = text

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down) {
                                    grid.moveSelection(grid.columns);
                                } else if (event.key === Qt.Key_Up) {
                                    grid.moveSelection(-grid.columns);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    grid.activateCurrent();
                                } else if (event.key === Qt.Key_Escape) {
                                    root.closed();
                                } else {
                                    event.accepted = false;
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    ToolbarPairedFab {
                        iconText: "close"
                        onClicked: root.closed()
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                    }
                }
            }
        }
    }
}
