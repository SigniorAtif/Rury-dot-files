import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // The bar runs under a named config; the settings app does not, so it has
    // to be named explicitly to talk to it.
    readonly property string shellConfigName: Quickshell.env("qsConfig") || "rury"

    // Accepts a bare username or a full profile URL, and keeps the username.
    function normalizeUser(value: string): string {
        const trimmed = value.trim().replace(/\/+$/, "");
        const match = trimmed.match(/github\.com\/([^\/?#]+)/i);
        return match ? match[1] : trimmed;
    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread indicator: show count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }
    
    ContentSection {
        icon: "spoke"
        title: Translation.tr("Positioning")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Automatically hide")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.autoHide.enable
                    onSelected: newValue => {
                        Config.options.bar.autoHide.enable = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigRow {
            
            ContentSubsection {
                title: Translation.tr("Corner style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.borderless
                    onSelected: newValue => {
                        Config.options.bar.borderless = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Pills"),
                            icon: "location_chip",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Line-separated"),
                            icon: "split_scene",
                            value: true
                        }
                    ]
                }
            }
        }
    }

    ContentSection {
        icon: "account_circle"
        title: Translation.tr("Top-left icon")

        ContentSubsection {
            title: Translation.tr("Source")

            ConfigSelectionArray {
                currentValue: Config.options.bar.githubAvatar.enable
                onSelected: newValue => {
                    Config.options.bar.githubAvatar.enable = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Picture"),
                        icon: "image",
                        value: false
                    },
                    {
                        displayName: Translation.tr("GitHub"),
                        icon: "cloud_download",
                        value: true
                    }
                ]
            }
        }

        ContentSubsection {
            visible: !Config.options.bar.githubAvatar.enable
            title: Translation.tr("Picture")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("e.g. rury.png")
                text: Config.options.bar.topLeftIcon
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.bar.topLeftIcon = text;
                    });
                }
            }

            StyledText {
                Layout.leftMargin: 10
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                wrapMode: Text.Wrap
                text: Translation.tr("A file in the shell's assets/icons folder, or a symbolic icon name from it. \"distro\" uses your distro's logo.")
            }
        }

        ContentSubsection {
            visible: Config.options.bar.githubAvatar.enable
            title: Translation.tr("GitHub profile")

            MaterialTextArea {
                id: githubUserField
                Layout.fillWidth: true
                rightPadding: fetchButton.implicitWidth + 16
                placeholderText: Translation.tr("Username or profile URL")
                text: Config.options.bar.githubAvatar.user
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.bar.githubAvatar.user = text.trim();
                    });
                }

                // Normalise once the field is done being typed in, so pasting a
                // profile URL works without rewriting it mid-keystroke.
                onActiveFocusChanged: {
                    if (githubUserField.activeFocus)
                        return;
                    const cleaned = root.normalizeUser(githubUserField.text);
                    if (cleaned !== githubUserField.text)
                        githubUserField.text = cleaned;
                }

                RippleButton {
                    id: fetchButton
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full

                    // idle | running | changed | unchanged | offline
                    property string fetchState: "idle"
                    enabled: fetchButton.fetchState !== "running"
                    onFetchStateChanged: {
                        if (fetchButton.fetchState !== "running")
                            fetchIcon.rotation = 0;
                    }

                    downAction: () => {
                        resetTimer.stop();
                        fetchButton.fetchState = "running";
                        fetchProcess.running = true;
                    }

                    contentItem: MaterialSymbol {
                        id: fetchIcon
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: Appearance.font.pixelSize.larger
                        text: {
                            if (fetchButton.fetchState === "offline")
                                return "cloud_off";
                            if (fetchButton.fetchState === "changed")
                                return "check";
                            if (fetchButton.fetchState === "unchanged")
                                return "done_all";
                            return "refresh";
                        }
                        color: fetchButton.fetchState === "offline" ?
                            Appearance.m3colors.m3error : Appearance.colors.colOnLayer1

                        RotationAnimation on rotation {
                            running: fetchButton.fetchState === "running"
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }

                    StyledToolTip {
                        text: {
                            if (fetchButton.fetchState === "running")
                                return Translation.tr("Fetching…");
                            if (fetchButton.fetchState === "changed")
                                return Translation.tr("Got a new picture");
                            if (fetchButton.fetchState === "unchanged")
                                return Translation.tr("Already up to date");
                            if (fetchButton.fetchState === "offline")
                                return Translation.tr("Could not reach GitHub");
                            return Translation.tr("Fetch now");
                        }
                    }

                    Process {
                        id: fetchProcess
                        command: ["bash", Quickshell.shellPath("scripts/github-avatar.sh"),
                            Config.options.bar.githubAvatar.user, "128"]
                        stdout: SplitParser {
                            onRead: data => {
                                const result = data.trim();
                                fetchButton.fetchState = ["changed", "unchanged", "offline"].includes(result) ?
                                    result : "offline";
                                // The bar is a different process, so it has to be told.
                                if (result === "changed")
                                    Quickshell.execDetached(["qs", "-c", root.shellConfigName,
                                        "ipc", "call", "githubAvatar", "reload"]);
                                resetTimer.restart();
                            }
                        }
                    }

                    Timer {
                        id: resetTimer
                        interval: 2500
                        onTriggered: fetchButton.fetchState = "idle"
                    }
                }
            }

            StyledText {
                Layout.leftMargin: 10
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                wrapMode: Text.Wrap
                text: Translation.tr("Cached, so it still shows while you are offline")
            }

            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Check for a new one every (h)")
                value: Config.options.bar.githubAvatar.refreshHours
                from: 1
                to: 168
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.githubAvatar.refreshHours = value;
                }
            }
        }
    }

    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }
        
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint icons')
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility buttons")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard toggle")
                checked: Config.options.bar.utilButtons.showKeyboardToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather")
        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.bar.weather.enable
            onCheckedChanged: {
                Config.options.bar.weather.enable = checked;
            }
        }
    }

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspaces")

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr('Always show numbers')
            checked: Config.options.bar.workspaces.alwaysShowNumbers
            onCheckedChanged: {
                Config.options.bar.workspaces.alwaysShowNumbers = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "award_star"
            text: Translation.tr('Show app icons')
            checked: Config.options.bar.workspaces.showAppIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.showAppIcons = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint app icons')
            checked: Config.options.bar.workspaces.monochromeIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.monochromeIcons = checked;
            }
        }

        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
            value: Config.options.bar.workspaces.shown
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.shown = value;
            }
        }

        ConfigSpinBox {
            icon: "touch_long"
            text: Translation.tr("Number show delay when pressing Super (ms)")
            value: Config.options.bar.workspaces.showNumberDelay
            from: 0
            to: 1000
            stepSize: 50
            onValueChanged: {
                Config.options.bar.workspaces.showNumberDelay = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Number style")

            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                onSelected: newValue => {
                    Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                }
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "timer_10",
                        value: '[]'
                    },
                    {
                        displayName: Translation.tr("Han chars"),
                        icon: "square_dot",
                        value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    },
                    {
                        displayName: Translation.tr("Roman"),
                        icon: "account_balance",
                        value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")
        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
        }
    }
}
