import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.rury.background
import qs.modules.rury.bar
import qs.modules.rury.cheatsheet
import qs.modules.rury.dock
import qs.modules.rury.lock
import qs.modules.rury.mediaControls
import qs.modules.rury.notificationPopup
import qs.modules.rury.onScreenDisplay
import qs.modules.rury.onScreenKeyboard
import qs.modules.rury.overview
import qs.modules.rury.polkit
import qs.modules.rury.regionSelector
import qs.modules.rury.screenCorners
import qs.modules.rury.screenTranslator
import qs.modules.rury.sessionScreen
import qs.modules.rury.sidebarLeft
import qs.modules.rury.sidebarRight
import qs.modules.rury.overlay
import qs.modules.rury.verticalBar
import qs.modules.rury.wallpaperSelector

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
}
