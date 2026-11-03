import QtQuick

Item {
    id: root

    property int rowIndex: 0
    property string label: ""
    property string subtext: ""
    property string kind: "action"
    property bool selected: false
    property bool favorite: false
    property string fontFamily: "Antonio"

    readonly property bool isSubmenu: root.kind === "menu" || root.kind === "link" || root.kind === "back"
    readonly property bool isBack: root.kind === "back"
    readonly property bool isApp: root.kind === "app"

    readonly property color orange: "#eb943a"
    readonly property color barley: "#edb378"
    readonly property color africanViolet: "#baa4e5"
    readonly property color butterscotch: "#ea9c72"
    readonly property color bluey: "#8899ff"
    readonly property color almond: "#d29b7f"
    readonly property color red: "#cf4f4f"
    readonly property color bg: "#000000"

    readonly property color barColor: {
        if (root.isSubmenu) {
            if (root.selected) return root.barley
            if (root.isBack) return root.almond
            return root.bluey
        }
        if (root.selected) return root.orange
        if (root.isApp) return root.africanViolet
        return root.butterscotch
    }

    readonly property color nameColor: {
        if (root.selected) return root.orange
        if (root.isApp) return root.africanViolet
        return root.barley
    }

    signal clicked()
    signal hovered(real x, real y)
    signal favoriteClicked()

    height: root.isSubmenu ? 36 : (root.subtext.length > 0 ? 50 : 40)
    width: parent ? parent.width : 400

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    // Submenu/Back: square-cut frame bar + tick.
    Item {
        id: bar
        visible: root.isSubmenu
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 32

        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 22
            color: root.barColor
        }
        Rectangle {
            id: tick
            width: 16
            height: parent.height
            color: root.selected ? root.orange : root.barColor
            anchors.right: parent.right
        }

        Text {
            width: 36
            height: parent.height
            text: root.pad2(root.rowIndex + 1)
            color: "#000000"
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 44
            anchors.right: menuSub.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: "#000000"
            font.family: root.fontFamily
            font.pixelSize: 18
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            elide: Text.ElideRight
        }

        Text {
            id: menuSub
            visible: root.subtext.length > 0
            width: visible ? Math.min(implicitWidth, Math.round(bar.width * 0.32)) : 0
            anchors.right: parent.right
            anchors.rightMargin: 30
            anchors.verticalCenter: parent.verticalCenter
            text: root.subtext
            color: "#000000"
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
    }

    // Executable: pill cap for the index, name and description as text.
    Item {
        id: execRow
        visible: !root.isSubmenu
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Column {
            id: execText
            anchors.left: indexPill.right
            anchors.leftMargin: 10
            anchors.right: favMark.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                id: execName
                width: parent.width
                text: root.label
                color: root.nameColor
                font.family: root.fontFamily
                font.pixelSize: 18
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }

            Text {
                id: execDesc
                visible: root.subtext.length > 0
                width: parent.width
                text: root.subtext
                color: root.almond
                font.family: root.fontFamily
                font.pixelSize: 12
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: indexPill
            // Same cap as the query bar: 36×36, left end fully round.
            width: 36
            height: 36
            anchors.left: parent.left
            anchors.verticalCenter: execText.verticalCenter
            color: root.barColor
            topLeftRadius: height / 2
            bottomLeftRadius: height / 2

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 3
                text: root.pad2(root.rowIndex + 1)
                color: "#000000"
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
            }
        }

        Rectangle {
            id: favMark
            visible: root.favorite
            width: visible ? 10 : 0
            height: 10
            color: root.favorite ? root.nameColor : "transparent"
            border.width: root.favorite ? 0 : 1
            border.color: root.nameColor
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                enabled: favMark.visible
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.favoriteClicked()
                onPositionChanged: function (mouse) {
                    var pos = mapToGlobal(mouse.x, mouse.y)
                    root.hovered(pos.x, pos.y)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        // A rebuilt row appears under a stationary pointer and reports a
        // position. The launcher ignores that sample unless the pointer moves.
        onPositionChanged: function (mouse) {
            var pos = mapToGlobal(mouse.x, mouse.y)
            root.hovered(pos.x, pos.y)
        }
        z: -1
    }
}
