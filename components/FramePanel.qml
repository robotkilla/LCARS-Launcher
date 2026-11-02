import QtQuick

// Left-rail LCARS panel: solid block, black seams, label bottom-right.
Rectangle {
    id: root

    property string hop: ""
    property string label: ""
    property color textColor: "#000000"
    property string fontFamily: "Antonio"
    property int fontPixelSize: 16
    property int padding: 10
    property int seamTop: 0
    property int seamBottom: 4
    property color seamColor: "#000000"

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.padding
        anchors.bottomMargin: root.padding
        text: root.hop + root.label
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
    }

    Rectangle {
        visible: root.seamTop > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.seamTop
        color: root.seamColor
    }

    Rectangle {
        visible: root.seamBottom > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.seamBottom
        color: root.seamColor
    }
}
