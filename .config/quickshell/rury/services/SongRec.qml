pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    enum MonitorSource { Auto, Monitor, Input }

    property var monitorSource: SongRec.MonitorSource.Auto
    property int timeoutInterval: Config.options.musicRecognition.interval
    property int timeoutDuration: Config.options.musicRecognition.timeout
    readonly property bool running: recognizeMusicProc.running

    function toggleRunning(running) {
        if (recognizeMusicProc.running && !running === true) root.manuallyStopped = true;
        if (running != undefined) {
            recognizeMusicProc.running = running
        } else {
            recognizeMusicProc.running = !root.running
        }
        musicReconizedProc.running = false
    }

    function toggleMonitorSource(source) {
        if (source !== undefined) {
            root.monitorSource = source
            return
        }
        if (root.monitorSource === SongRec.MonitorSource.Auto) {
            root.monitorSource = SongRec.MonitorSource.Monitor
        } else if (root.monitorSource === SongRec.MonitorSource.Monitor) {
            root.monitorSource = SongRec.MonitorSource.Input
        } else {
            root.monitorSource = SongRec.MonitorSource.Auto
        }
    }
    function monitorSourceToString(source) {
        if (source === SongRec.MonitorSource.Auto) {
            return "auto"
        } else if (source === SongRec.MonitorSource.Monitor) {
            return "monitor"
        } else {
            return "input"
        }
    }
    readonly property string monitorSourceString: monitorSourceToString(monitorSource)
    property var recognizedTrack: ({ title:"", subtitle:"", url:""})
    property bool manuallyStopped: false

    // History of recognized songs, newest first. Persisted across restarts.
    property var history: []
    readonly property int maxHistoryLength: 50

    function appleMusicUrl(track) {
        const term = `${track.title ?? ""} ${track.subtitle ?? ""}`.trim()
        return "https://music.apple.com/search?term=" + encodeURIComponent(term)
    }

    function addToHistory(track) {
        const list = root.history.slice(0)
        // Collapse repeats of the same song instead of stacking them
        const existingIndex = list.findIndex(item => item.title === track.title && item.subtitle === track.subtitle)
        if (existingIndex !== -1) list.splice(existingIndex, 1)
        list.unshift({
            title: track.title,
            subtitle: track.subtitle,
            url: track.url,
            time: Date.now()
        })
        root.history = list.slice(0, root.maxHistoryLength)
        historyFileView.setText(JSON.stringify(root.history))
    }

    function removeFromHistory(index) {
        if (index < 0 || index >= root.history.length) return
        const list = root.history.slice(0)
        list.splice(index, 1)
        root.history = list
        historyFileView.setText(JSON.stringify(root.history))
    }

    function clearHistory() {
        root.history = []
        historyFileView.setText(JSON.stringify(root.history))
    }

    FileView {
        id: historyFileView
        path: Qt.resolvedUrl(Directories.musicRecognitionHistoryPath)
        onLoaded: {
            try {
                const parsed = JSON.parse(historyFileView.text())
                root.history = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                root.history = []
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                root.history = []
                historyFileView.setText(JSON.stringify(root.history))
            }
        }
    }

    Component.onCompleted: historyFileView.reload()

    function handleRecognition(jsonText) {
        try {
            var obj = JSON.parse(jsonText)
            root.recognizedTrack = {
                title: obj.track.title,
                subtitle: obj.track.subtitle,
                url: obj.track.url
            }
            root.addToHistory(root.recognizedTrack)
            musicReconizedProc.running = true
        } catch(e) {
            Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Perhaps what you're listening to is too niche"), "-a", "Shell"])
        }
    }

    Process {
        id: recognizeMusicProc
        running: false
        command: [`${Directories.scriptPath}/musicRecognition/recognize-music.sh`, "-i", root.timeoutInterval, "-t", root.timeoutDuration, "-s", root.monitorSourceString]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.manuallyStopped) {
                    root.manuallyStopped = false
                    return
                }
                handleRecognition(this.text)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Make sure you have songrec installed"), "-a", "Shell"])
            }
        }
    }

    Process {
        id: musicReconizedProc
        running: false
        command: [
            "notify-send",
            Translation.tr("Music Recognized"), 
            root.recognizedTrack.title + " - " + root.recognizedTrack.subtitle, 
            "-A", "Shazam",
            "-A", "Apple Music",
            "-A", "YouTube",
            "-a", "Shell"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const action = this.text.trim()
                if (action === "") return
                if (action == 0) {
                    Qt.openUrlExternally(root.recognizedTrack.url);
                } else if (action == 1) {
                    Qt.openUrlExternally(root.appleMusicUrl(root.recognizedTrack));
                } else {
                    Qt.openUrlExternally("https://www.youtube.com/results?search_query=" + encodeURIComponent(root.recognizedTrack.title + " - " + root.recognizedTrack.subtitle));
                }
            }
        }
    }
}