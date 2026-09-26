pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// Settings for the top-left icon, shown in the shared bar popout on right
// click: fetch the picture from a GitHub profile, or use one from disk.
StyledPopup {
    id: root
    padding: 14

    signal refreshRequested()

    readonly property bool fromGithub: Config.options.bar.githubAvatar.enable

    // Accepts a bare username or a full profile URL, and keeps the username.
    function normalizeUser(value: string): string {
        const trimmed = value.trim().replace(/\/+$/, "");
        const match = trimmed.match(/github\.com\/([^\/?#]+)/i);
        return match ? match[1] : trimmed;
    }

    ColumnLayout {
        spacing: 10

        StyledPopupHeaderRow {
            icon: "account_circle"
            label: Translation.tr("Top-left icon")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "cloud_download"
                mainText: Translation.tr("GitHub")
                toggled: root.fromGithub
                onClicked: Config.options.bar.githubAvatar.enable = true
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("File")
                toggled: !root.fromGithub
                onClicked: Config.options.bar.githubAvatar.enable = false
            }
        }

        MaterialTextField {
            id: sourceField
            Layout.fillWidth: true
            Layout.preferredWidth: 280
            placeholderText: root.fromGithub ?
                Translation.tr("GitHub username or profile URL") :
                Translation.tr("Picture in assets/icons, e.g. rury.png")
            text: root.fromGithub ? Config.options.bar.githubAvatar.user : Config.options.bar.topLeftIcon

            // Follow the mode switch rather than the user's half-typed text.
            Connections {
                target: Config.options.bar.githubAvatar
                function onEnableChanged() {
                    sourceField.text = root.fromGithub ?
                        Config.options.bar.githubAvatar.user : Config.options.bar.topLeftIcon;
                }
            }

            onAccepted: root.apply()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                visible: root.fromGithub
                materialIcon: "refresh"
                mainText: Translation.tr("Fetch now")
                onClicked: {
                    root.apply();
                    root.refreshRequested();
                }
            }
            RippleButtonWithIcon {
                materialIcon: "check"
                mainText: Translation.tr("Apply")
                onClicked: root.apply()
            }
        }
    }

    function apply(): void {
        const value = sourceField.text.trim();
        if (value === "")
            return;
        if (root.fromGithub)
            Config.options.bar.githubAvatar.user = root.normalizeUser(value);
        else
            Config.options.bar.topLeftIcon = value;
    }
}
