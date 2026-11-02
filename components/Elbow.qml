import QtQuick

// Classic LCARS elbow as an L of square rects plus one rounded outer corner.
// Square edges stay crisp where the connecting bar meets the rail.
// corner: "tl" | "tr" | "bl" | "br"
Item {
    id: root

    property color color: "#8899ff"
    property color cutout: "#000000"
    property string corner: "bl"
    property int radius: 130
    property int innerRadius: 48
    property int armThickness: 24
    property bool innerCut: true

    readonly property bool fromLeft: corner === "tl" || corner === "bl"
    readonly property bool fromTop: corner === "tl" || corner === "tr"
    readonly property int outer: Math.max(1, Math.min(root.radius, width, height))

    // Stem: the part away from the outer rounded corner (full width).
    Rectangle {
        color: root.color
        x: 0
        y: root.fromTop ? root.outer : 0
        width: parent.width
        height: Math.max(0, parent.height - root.outer)
    }

    // Arm block beside the outer corner (square; this edge meets the bar).
    Rectangle {
        color: root.color
        x: root.fromLeft ? root.outer : 0
        y: root.fromTop ? 0 : parent.height - root.outer
        width: Math.max(0, parent.width - root.outer)
        height: root.outer
    }

    // Outer quarter-circle.
    Rectangle {
        color: root.color
        width: root.outer
        height: root.outer
        x: root.fromLeft ? 0 : parent.width - width
        y: root.fromTop ? 0 : parent.height - height
        topLeftRadius: root.corner === "tl" ? root.outer : 0
        topRightRadius: root.corner === "tr" ? root.outer : 0
        bottomLeftRadius: root.corner === "bl" ? root.outer : 0
        bottomRightRadius: root.corner === "br" ? root.outer : 0
    }

    // Tucks 2px of rail color under the connecting bar to hide the join.
    Rectangle {
        visible: root.innerCut
        width: 2
        height: root.armThickness
        color: root.color
        x: root.fromLeft ? parent.width : -width
        y: root.fromTop ? 0 : parent.height - height
    }

    // Inner well: rail-colored square + black quarter-circle cut.
    Rectangle {
        visible: root.innerCut
        width: root.innerRadius
        height: root.innerRadius
        color: root.color
        x: root.fromLeft ? parent.width : -width
        y: root.fromTop ? root.armThickness : (parent.height - root.armThickness - height)
    }

    Rectangle {
        visible: root.innerCut
        width: root.innerRadius
        height: root.innerRadius
        color: root.cutout
        x: root.fromLeft ? parent.width : -width
        y: root.fromTop ? root.armThickness : (parent.height - root.armThickness - height)
        topLeftRadius: root.corner === "tl" ? root.innerRadius : 0
        topRightRadius: root.corner === "tr" ? root.innerRadius : 0
        bottomLeftRadius: root.corner === "bl" ? root.innerRadius : 0
        bottomRightRadius: root.corner === "br" ? root.innerRadius : 0
    }
}
