pragma Singleton
import QtCore
import Quickshell

Singleton {
    id: root

    // ~/Pictures/homework, where the 🌶️ collection lives
    readonly property string homeworkDir: `${StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]}/homework/`.replace(/^file:\/\//, "")

    /**
     * Whether a wallpaper is NSFW: the random fetch marks its downloads "_nsfw_", and
     * everything under ~/Pictures/homework is. Used to pick the collection the save button
     * puts it in and to decide what the wallpaper guard hides.
     * @param {string} path
     * @returns {boolean}
     */
    function isNsfw(path) {
        if (!path) return false;
        const trimmed = path.toString().replace(/^file:\/\//, "");
        const name = trimmed.split("/").pop();
        return name.includes("_nsfw_") || trimmed.startsWith(root.homeworkDir);
    }
}
