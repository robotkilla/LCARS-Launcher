import QtQuick

// Thin connecting bar: square LCARS segments, optional status label.
Item {
    id: root

    property string text: ""
    property color textColor: "#000000"
    property int spacing: 5
    property string fontFamily: "Antonio"
    property int fontPixelSize: 14
    property color capColor: "#cf4f4f"
    property color tickColor: "#ea9c72"
    property color midColor: "#baa4e5"
    property color endColor: "#ea9c72"

    PillBar {
        anchors.fill: parent
        spacing: root.spacing
        textColor: root.textColor
        fontFamily: root.fontFamily
        fontPixelSize: root.fontPixelSize
        segments: [
            { width: Math.max(240, Math.round(root.width * 0.38)), color: root.capColor },
            { width: 22, color: root.tickColor },
            { width: 80, color: root.capColor, heightFraction: 0.5 },
            { fill: true, color: root.midColor, text: root.text },
            { width: 22, color: root.endColor }
        ]
    }
}
