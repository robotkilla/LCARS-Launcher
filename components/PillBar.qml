import QtQuick

// Horizontal LCARS bar: square segments (frame bars) or pill caps (buttons).
//
// Segment object:
//   width           number   fixed width (ignored when fill is true)
//   fill            bool     consume remaining width
//   color           color    block color
//   text            string   optional uppercase label
//   textColor       color    defaults to bar textColor
//   pillLeft        bool     round the left cap
//   pillRight       bool     round the right cap
//   heightFraction  number   0–1, default 1 (classic half-height ticks)
Item {
    id: root

    property var segments: []
    property int spacing: 5
    property color textColor: "#000000"
    property string fontFamily: "Antonio"
    property int fontPixelSize: 14
    property color defaultColor: "#eb943a"

    function segAt(index) {
        if (!root.segments || index < 0 || index >= root.segments.length)
            return ({})
        return root.segments[index] || ({})
    }

    function widthFor(index) {
        var seg = root.segAt(index)
        if (!seg.fill)
            return Math.max(0, Number(seg.width || 0))

        var fixed = 0
        var fills = 0
        for (var i = 0; i < root.segments.length; i++) {
            var s = root.segAt(i)
            if (s.fill)
                fills++
            else
                fixed += Number(s.width || 0)
        }
        var gaps = root.spacing * Math.max(0, root.segments.length - 1)
        var remain = Math.max(0, root.width - fixed - gaps)
        return fills > 0 ? remain / fills : remain
    }

    Row {
        id: row
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            model: root.segments

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                width: root.widthFor(index)
                height: root.height

                readonly property var seg: modelData || ({})
                readonly property color blockColor: cell.seg.color || root.defaultColor
                readonly property bool pillLeft: !!cell.seg.pillLeft
                readonly property bool pillRight: !!cell.seg.pillRight
                readonly property string label: String(cell.seg.text || "")
                readonly property color labelColor: cell.seg.textColor || root.textColor
                readonly property real heightFraction: {
                    var f = Number(cell.seg.heightFraction)
                    return (f > 0 && f <= 1) ? f : 1
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: cell.pillLeft ? cell.height / 2 : 0
                    anchors.rightMargin: cell.pillRight ? cell.height / 2 : 0
                    height: parent.height * cell.heightFraction
                    color: cell.blockColor
                }
                Rectangle {
                    visible: cell.pillLeft
                    width: parent.height * cell.heightFraction
                    height: width
                    radius: width / 2
                    color: cell.blockColor
                }
                Rectangle {
                    visible: cell.pillRight
                    width: parent.height * cell.heightFraction
                    height: width
                    anchors.right: parent.right
                    radius: width / 2
                    color: cell.blockColor
                }

                Text {
                    visible: cell.label.length > 0
                    anchors.fill: parent
                    anchors.leftMargin: (cell.pillLeft ? cell.height / 2 : 0) + 10
                    anchors.rightMargin: (cell.pillRight ? cell.height / 2 : 0) + 8
                    text: cell.label
                    color: cell.labelColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPixelSize
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
