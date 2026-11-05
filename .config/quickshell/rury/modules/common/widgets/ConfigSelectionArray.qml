import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    Layout.fillWidth: true
    // A Flow that isn't stretched has no width to wrap against, so it gives every
    // button its own line. When not filling, ask the layout for one row's worth.
    Layout.preferredWidth: Layout.fillWidth ? -1 : singleRowWidth
    spacing: 2
    readonly property real singleRowWidth: {
        let total = 0;
        let count = 0;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (!child.visible || child.implicitWidth <= 0) continue; // skips the Repeater
            total += child.implicitWidth;
            count++;
        }
        return total + spacing * Math.max(0, count - 1);
    }
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null

    signal selected(var newValue)

    Repeater {
        model: root.options
        delegate: SelectionGroupButton {
            id: paletteButton
            required property var modelData
            required property int index
            onYChanged: {
                if (index === 0) {
                    paletteButton.leftmost = true
                } else {
                    var prev = root.children[index - 1]
                    var thisIsOnNewLine = prev && prev.y !== paletteButton.y
                    paletteButton.leftmost = thisIsOnNewLine
                    prev.rightmost = thisIsOnNewLine
                }
            }
            leftmost: index === 0
            rightmost: index === root.options.length - 1
            buttonIcon: modelData.icon || ""
            buttonText: modelData.displayName
            toggled: root.currentValue == modelData.value
            onClicked: {
                root.selected(modelData.value);
            }
        }
    }
}
