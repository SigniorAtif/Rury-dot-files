import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3
// Icon-theme lookups come back empty on some themes (Quickshell.iconPath
// returns ""), which left folders blank, so there's a symbol fallback.

Item {
    id: root
    required property var fileModelData

    readonly property string themeIcon: {
        if (!fileModelData.fileIsDir)
            return Quickshell.iconPath("application-x-zerosize", true);

        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return Quickshell.iconPath(`folder-${fileModelData.fileName.toLowerCase()}`, "inode-directory");

        return Quickshell.iconPath("inode-directory", "folder");
    }
    property string overrideSource: ""
    readonly property bool imageShown: image.status === Image.Ready

    StyledImage {
        id: image
        anchors.fill: parent
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: root.overrideSource.length > 0 ? root.overrideSource : root.themeIcon
    }

    MaterialSymbol { // Fallback when the icon theme has nothing usable
        anchors.centerIn: parent
        visible: !root.imageShown
        text: root.fileModelData.fileIsDir ? "folder" : "draft"
        fill: 1
        iconSize: Math.max(24, Math.min(parent.width, parent.height) * 0.55)
        color: Appearance.colors.colOnLayer1
    }

    Process {
        running: !root.fileModelData.fileIsDir
        command: ["file", "--mime", "-b", root.fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].replace("/", "-");
                root.overrideSource = Images.validImageTypes.some(t => mime === `image-${t}`)
                    ? root.fileModelData.fileUrl
                    : Quickshell.iconPath(mime, "image-missing");
            }
        }
    }
}
