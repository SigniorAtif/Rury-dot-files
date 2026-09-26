import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    toggled: SongRec.running
    property int source: SongRec.monitorSource

    name: Translation.tr("Identify Music")
    statusText: toggled ? Translation.tr("Listening...")
        : source === SongRec.MonitorSource.Auto ? Translation.tr("Auto")
        : source === SongRec.MonitorSource.Monitor ? Translation.tr("System sound")
        : Translation.tr("Microphone")
    icon: toggled ? "music_cast"
        : source === SongRec.MonitorSource.Auto ? "hearing"
        : source === SongRec.MonitorSource.Monitor ? "music_note"
        : "frame_person_mic"

    tooltipText: Translation.tr("Recognize music | Right-click to cycle source (auto/system/mic)")

    mainAction: () => {
        SongRec.toggleRunning()
    }
    altAction: () => {
        SongRec.toggleMonitorSource()
    }
}
