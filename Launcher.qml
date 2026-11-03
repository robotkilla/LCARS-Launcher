import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model
import "components"

Item {
    id: root

    // Injected by omarchy-shell
    property var shell: null
    property var manifest: null
    property string omarchyPath: ""

    property bool opened: false
    property string query: ""
    property int selectedIndex: 0
    property bool hoverArmed: false
    property int hoverX: -99999
    property int hoverY: -99999
    property var usage: ({})
    property var defaultMenuItems: []
    property var userMenuItems: []
    property var items: ({})
    property var itemOrder: []
    property string activeMenu: "root"
    property var navStack: []
    property var providersLoaded: ({})
    property var providerQueue: []
    property int providerRevision: 0
    property var whenResults: ({})
    property var checkedResults: ({})
    property bool guardsPending: false
    property string hostname: ""
    property string clockText: "--:--"
    property string ip0: "--"
    property string ip1: "--"
    property string ip2: "--"
    property string ip3: "--"
    readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/omarchy/lcars-launcher-usage.json"
    readonly property string defaultMenuPath: (root.omarchyPath && root.omarchyPath.length ? root.omarchyPath : "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
    readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    readonly property string currentTitle: {
        var entry = root.items && root.items[root.activeMenu]
        if (!entry || root.activeMenu === "root") return "System Menu"
        return entry.title || entry.label || "System Menu"
    }
    readonly property string currentPath: {
        if (root.activeMenu === "root") return ""
        return Model.parentPathFor(root.items, root.activeMenu)
    }

    readonly property var providers: ({
        "fonts": {
            script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
            volatile: true,
            actionFor: function (value) { return "omarchy-font-set " + root.shellQuote(value) }
        },
        "power-profiles": {
            script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
            volatile: true,
            actionFor: function (value) { return "omarchy-powerprofiles-set autodetect " + root.shellQuote(value) }
        }
    })

    // Classic LCARS palette (thelcars.com Classic theme)
    readonly property color bg: "#000000"
    readonly property color africanViolet: "#baa4e5"
    readonly property color almond: "#d29b7f"
    readonly property color almondCreme: "#fcc19f"
    readonly property color barley: "#edb378"
    readonly property color bluey: "#8899ff"
    readonly property color orange: "#eb943a"
    readonly property color butterscotch: "#ea9c72"
    readonly property color lilac: "#8a72a7"
    readonly property color red: "#cf4f4f"
    readonly property color sienna: "#c47d69"
    readonly property color trueMauve: "#c082a9"

    readonly property int railWidth: 200
    readonly property int barHeight: 24
    readonly property int elbowRadius: 124
    readonly property int innerRadius: 48
    readonly property int frameGap: 8
    readonly property int contentPad: 64
    readonly property int contentWidth: 800
    readonly property int frameMargin: 10

    FontLoader {
        id: antonioRegular
        source: Qt.resolvedUrl("fonts/Antonio-Regular.ttf")
    }
    FontLoader {
        id: antonioBold
        source: Qt.resolvedUrl("fonts/Antonio-Bold.ttf")
    }

    readonly property string lcarsFont: {
        var name = antonioRegular.family
        return (name && name.length) ? name : "Antonio"
    }

    function pluginId() {
        return (root.manifest && root.manifest.id) || "robotkilla.lcars-launcher"
    }

    function desktopFile(id) {
        var value = String(id || "")
        if (value.slice(-8) === ".desktop") return value
        return value + ".desktop"
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
    }

    function refreshClock() {
        root.clockText = Qt.formatTime(new Date(), "HH:mm")
    }

    function refreshAddress() {
        if (ipProc.running) return
        ipProc.collected = ""
        ipProc.command = ["ip", "-4", "route", "get", "1.1.1.1"]
        ipProc.running = true
    }

    function applyAddress(raw) {
        var token = ""
        var parts = String(raw || "").split(/\s+/)
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === "src" && i + 1 < parts.length) {
                token = parts[i + 1]
                break
            }
        }
        var octets = token.split(".")
        if (octets.length === 4) {
            root.ip0 = octets[0]
            root.ip1 = octets[1]
            root.ip2 = octets[2]
            root.ip3 = octets[3]
        } else {
            root.ip0 = "--"
            root.ip1 = "--"
            root.ip2 = "--"
            root.ip3 = "--"
        }
    }

    function selectedId() {
        if (root.selectedIndex < 0 || root.selectedIndex >= resultModel.count) return ""
        return String(resultModel.get(root.selectedIndex).itemId || "")
    }

    function markProviderLoaded(id) {
        var next = {}
        var src = root.providersLoaded || {}
        for (var k in src) next[k] = src[k]
        next[id] = true
        root.providersLoaded = next
    }

    function rebuildMenuCatalog() {
        var merged = Model.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
        root.providerRevision += 1
        root.providersLoaded = ({})
        root.providerQueue = []
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        root.ensureApps()
        root.evaluateGuards()
        if (root.opened) {
            if (!root.items[root.activeMenu]) root.activeMenu = "root"
            root.rebuildResults()
            if (String(root.query || "").trim()) root.loadProvidersForSearch()
            else root.loadProviderForMenu(root.activeMenu)
        }
    }

    // Last complete batch stays on screen until the next one finishes.
    // A second call while bash is running waits; Process drops a command
    // change that arrives mid-run.
    function evaluateGuards() {
        if (guardProc.running) {
            root.guardsPending = true
            return
        }
        root.guardsPending = false
        var script = Model.guardScript(root.items, root.itemOrder)
        if (!script) {
            root.whenResults = ({})
            root.checkedResults = ({})
            return
        }
        guardProc.collected = ""
        guardProc.command = ["bash", "-lc", script]
        guardProc.running = true
    }

    function applyGuardOutput(raw) {
        var parsed = Model.parseGuardOutput(raw)
        root.whenResults = parsed.whenResults || ({})
        root.checkedResults = parsed.checkedResults || ({})
        if (root.opened) root.rebuildResults()
    }

    function collectAppRows() {
        var appRows = []
        try {
            var apps = DesktopEntries.applications.values || []
            for (var i = 0; i < apps.length; i++) {
                var app = apps[i]
                if (!app || app.noDisplay === true) continue
                var appId = String(app.id || "")
                if (!appId) continue
                var subtext = String(app.genericName || "")
                var aliases = subtext ? [subtext] : []
                try {
                    if (app.keywords && typeof app.keywords.join === "function")
                        aliases = aliases.concat(app.keywords)
                } catch (e) {
                }
                appRows.push({
                    id: "apps." + appId,
                    parent: "apps",
                    kind: "app",
                    icon: "",
                    appId: appId,
                    label: String(app.name || appId),
                    title: "",
                    target: "",
                    description: subtext,
                    action: "",
                    provider: "",
                    aliases: aliases,
                    when: "",
                    checked: "",
                    order: 0
                })
            }
        } catch (e) {
        }
        return appRows
    }

    function ensureApps() {
        var appsEntry = root.items ? root.items["apps"] : null
        if (!appsEntry || appsEntry.provider !== "apps") return
        if (root.providersLoaded["apps"]) return
        root.refreshAppRows()
    }

    function refreshAppRows() {
        var appsEntry = root.items ? root.items["apps"] : null
        if (!appsEntry || appsEntry.provider !== "apps") return
        root.markProviderLoaded("apps")
        var merged = Model.mergeAppRows(root.items, root.itemOrder, root.collectAppRows())
        root.items = merged.items
        root.itemOrder = merged.itemOrder
    }

    function mergeAppRows() {
        root.refreshAppRows()
        if (root.opened) root.rebuildResults()
    }

    function startProviderForMenu(id) {
        var entry = root.items[id]
        if (!entry || !entry.provider || root.providersLoaded[id]) return
        if (entry.provider === "apps") {
            root.mergeAppRows()
            return
        }
        var spec = root.providers[entry.provider]
        if (!spec) return
        root.markProviderLoaded(id)
        providerProc.menuId = id
        providerProc.providerKey = entry.provider
        providerProc.revision = root.providerRevision
        providerProc.collected = ""
        providerProc.command = ["bash", "-lc", spec.script]
        providerProc.running = true
    }

    function mergeProviderRows(raw, menuId, providerKey) {
        var spec = root.providers[providerKey]
        if (!spec) return
        var lines = String(raw || "").split("\n")
        var providerRows = []
        var takenIds = ({})
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var parts = line.split("\t")
            var label = parts[0] || ""
            var value = parts[1] || parts[0] || ""
            var current = parts[2] || ""
            if (!label) continue
            var rowId = menuId + "." + Model.slugify(value)
            while (takenIds[rowId]) rowId += "-"
            takenIds[rowId] = true
            providerRows.push({
                id: rowId,
                parent: menuId,
                kind: "action",
                icon: "",
                label: label,
                title: "",
                target: "",
                description: value === current ? "CURRENT" : "",
                action: spec.actionFor(value),
                provider: "",
                aliases: [],
                when: "",
                checked: "",
                order: 0
            })
        }
        var merged = Model.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        if (root.opened) root.rebuildResults()
    }

    function startNextProvider() {
        if (providerProc.running) return
        while (root.providerQueue.length > 0) {
            var id = root.providerQueue.shift()
            var entry = root.items[id]
            if (!entry || !entry.provider || root.providersLoaded[id]) continue
            root.startProviderForMenu(id)
            return
        }
    }

    function loadProviderForMenu(id) {
        var entry = root.items[id]
        if (!entry || !entry.provider || root.providersLoaded[id]) return
        if (entry.provider === "apps") {
            root.startProviderForMenu(id)
            return
        }
        if (providerProc.running) {
            if (root.providerQueue.indexOf(id) < 0)
                root.providerQueue = root.providerQueue.concat([id])
            return
        }
        root.startProviderForMenu(id)
    }

    function loadProvidersForSearch() {
        var active = root.items[root.activeMenu] ? root.activeMenu : "root"
        for (var i = 0; i < root.itemOrder.length; i++) {
            var entry = root.items[root.itemOrder[i]]
            if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
            if (active !== "root" && entry.id !== active && !Model.isDescendantOf(root.items, entry.id, active))
                continue
            root.loadProviderForMenu(entry.id)
        }
    }

    function invalidateVolatileProvider(id) {
        var entry = root.items[id]
        var spec = entry && entry.provider ? root.providers[entry.provider] : null
        if (!spec || !spec.volatile) return
        var next = {}
        var src = root.providersLoaded || {}
        for (var k in src) {
            if (k !== id) next[k] = src[k]
        }
        root.providersLoaded = next
    }

    function disarmHover() {
        // The next hover sample is where the pointer already sits.
        root.hoverArmed = false
    }

    function hoverRow(index, x, y) {
        var ix = Math.round(x)
        var iy = Math.round(y)
        if (!root.hoverArmed) {
            root.hoverArmed = true
            root.hoverX = ix
            root.hoverY = iy
            return
        }
        if (ix === root.hoverX && iy === root.hoverY)
            return
        root.hoverX = ix
        root.hoverY = iy
        root.selectedIndex = index
    }

    function rebuildResults(keepSelection) {
        root.disarmHover()
        root.ensureApps()
        var keepId = keepSelection === false ? "" : root.selectedId()
        var rows = Model.browseRows(root.items, root.itemOrder, root.activeMenu, root.query, root.whenResults, root.checkedResults, root.usage, Date.now())
        resultModel.clear()
        if (root.activeMenu !== "root" && String(root.query || "").trim() === "") {
            var parent = root.items[root.activeMenu]
            resultModel.append({
                itemId: "__back__",
                kind: "back",
                appId: "",
                label: "Back",
                subtext: parent && parent.parent && parent.parent !== "root" ? Model.pathFor(root.items, parent.parent) : "System Menu",
                target: "",
                action: "",
                usageKey: "",
                favorite: false,
                section: ""
            })
        }
        for (var i = 0; i < rows.length; i++) {
            resultModel.append({
                itemId: rows[i].itemId,
                kind: rows[i].kind,
                appId: rows[i].appId,
                label: rows[i].label,
                subtext: rows[i].subtext,
                target: rows[i].target,
                action: rows[i].action,
                usageKey: rows[i].usageKey,
                favorite: rows[i].favorite,
                section: rows[i].section
            })
        }
        var next = 0
        if (keepId) {
            for (var s = 0; s < resultModel.count; s++) {
                if (String(resultModel.get(s).itemId || "") === keepId) {
                    next = s
                    break
                }
            }
        }
        if (resultModel.count === 0)
            root.selectedIndex = 0
        else if (next >= resultModel.count)
            root.selectedIndex = resultModel.count - 1
        else
            root.selectedIndex = next
        Qt.callLater(function () {
            if (resultModel.count > 0)
                resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        })
    }

    function selectDelta(delta) {
        if (resultModel.count === 0) return
        var next = root.selectedIndex + delta
        if (next < 0) next = 0
        if (next >= resultModel.count) next = resultModel.count - 1
        root.selectedIndex = next
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }

    function saveUsage() {
        usageFile.setText(Model.serializeUsage(root.usage))
    }

    function restrictUsageFile() {
        // FileView creates the file with the process umask. Keep the
        // frecency record owner-only, including a copy that already exists.
        Quickshell.execDetached([
            "bash", "-c",
            'f=$1; [ -e "$f" ] || exit 0; m=$(stat -c %a "$f" 2>/dev/null) || exit 0; [ "$m" = 600 ] || chmod 600 -- "$f"',
            "restrict-usage",
            root.usagePath
        ])
    }

    function setActiveMenu(id, pushHistory) {
        if (!root.items[id]) id = "root"
        if (pushHistory && id !== root.activeMenu)
            root.navStack = root.navStack.concat([root.activeMenu])
        root.activeMenu = id
        root.query = ""
        root.selectedIndex = 0
        root.rebuildResults(false)
        root.invalidateVolatileProvider(id)
        root.loadProviderForMenu(id)
    }

    function goBack() {
        if (root.activeMenu === "root") return false
        if (root.navStack.length > 0) {
            var previous = root.navStack[root.navStack.length - 1]
            root.navStack = root.navStack.slice(0, root.navStack.length - 1)
            root.setActiveMenu(previous, false)
            return true
        }
        var active = root.items[root.activeMenu]
        root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
        return true
    }

    function handleEscape() {
        if (String(root.query || "").length) {
            root.query = ""
            return
        }
        root.dismiss()
    }

    function activateIndex(index) {
        if (index < 0 || index >= resultModel.count) return
        var row = resultModel.get(index)
        var kind = String(row.kind || "")
        if (kind === "back") {
            root.goBack()
            return
        }
        if (kind === "menu" || kind === "link") {
            root.setActiveMenu(row.target || row.itemId, true)
            return
        }
        var usageKey = String(row.usageKey || row.itemId || "")
        if (usageKey) {
            root.usage = Model.recordUsage(root.usage, usageKey, Date.now())
            root.saveUsage()
        }
        root.dismiss()
        if (kind === "app") {
            var appId = String(row.appId || "")
            if (appId)
                Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", root.desktopFile(appId)])
            return
        }
        var action = String(row.action || "")
        if (action)
            Quickshell.execDetached(["bash", "-lc", action])
    }

    function toggleFavoriteIndex(index) {
        if (index < 0 || index >= resultModel.count) return
        var key = String(resultModel.get(index).usageKey || "")
        if (!key) return
        root.usage = Model.toggleFavorite(root.usage, key)
        root.saveUsage()
        root.rebuildResults()
    }

    function toggleFavoriteSelected() {
        root.toggleFavoriteIndex(root.selectedIndex)
    }

    function launchSelected() {
        root.activateIndex(root.selectedIndex)
    }

    function resetNavigation() {
        root.query = ""
        root.selectedIndex = 0
        root.activeMenu = "root"
        root.navStack = []
    }

    function open(payloadJson) {
        var payload = ({})
        try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
        var route = Model.resolveRoute(root.items, root.itemOrder, payload.initialMenu || payload.menu || "root")
        var entry = root.items[route]
        if (entry && entry.kind === "action" && entry.action) {
            if (root.opened) root.dismiss()
            Quickshell.execDetached(["bash", "-lc", entry.action])
            return
        }
        if (entry && entry.kind === "link" && entry.target) route = entry.target
        root.opened = true
        root.refreshClock()
        root.refreshAddress()
        root.query = ""
        root.selectedIndex = 0
        root.navStack = []
        root.activeMenu = root.items[route] ? route : "root"
        root.evaluateGuards()
        root.rebuildResults(false)
        root.invalidateVolatileProvider(root.activeMenu)
        root.loadProviderForMenu(root.activeMenu)
        if (String(root.query || "").trim()) root.loadProvidersForSearch()
        Qt.callLater(function () {
            searchInput.forceActiveFocus()
        })
    }

    function close() {
        root.opened = false
        root.resetNavigation()
    }

    function dismiss() {
        root.opened = false
        root.resetNavigation()
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId())
    }

    function toggle() {
        if (root.opened)
            root.dismiss()
        else
            root.open("{}")
    }

    onQueryChanged: {
        if (!root.opened) return
        if (String(root.query || "").trim()) root.loadProvidersForSearch()
        root.rebuildResults(false)
    }

    ListModel {
        id: resultModel
    }

    FileView {
        id: usageFile
        path: root.usagePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.restrictUsageFile()
            root.usage = Model.parseUsage(text())
            if (root.opened) root.rebuildResults()
        }
        onSaved: root.restrictUsageFile()
        onLoadFailed: root.usage = ({})
        onFileChanged: reload()
    }

    FileView {
        id: defaultMenuFile
        path: root.defaultMenuPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.defaultMenuItems = Model.parseMenuJsonc(text())
            root.rebuildMenuCatalog()
        }
        onLoadFailed: {
            root.defaultMenuItems = []
            root.rebuildMenuCatalog()
        }
        onFileChanged: reload()
    }

    FileView {
        id: userMenuFile
        path: root.userMenuPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.userMenuItems = Model.parseMenuJsonc(text())
            root.rebuildMenuCatalog()
        }
        onLoadFailed: {
            root.userMenuItems = []
            root.rebuildMenuCatalog()
        }
        onFileChanged: reload()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            if (root.providersLoaded["apps"]) root.mergeAppRows()
            else if (root.opened) root.rebuildResults()
        }
    }

    Process {
        id: providerProc
        property string menuId: ""
        property string providerKey: ""
        property string collected: ""
        property int revision: 0
        stdout: SplitParser {
            onRead: function (data) { providerProc.collected += data + "\n" }
        }
        onExited: {
            if (providerProc.revision === root.providerRevision)
                root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
            root.startNextProvider()
        }
    }

    Process {
        id: guardProc
        property string collected: ""
        stdout: SplitParser {
            onRead: function (data) { guardProc.collected += data + "\n" }
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0) {
                if (root.guardsPending) Qt.callLater(function () { root.evaluateGuards() })
                return
            }
            root.applyGuardOutput(guardProc.collected)
            if (root.guardsPending) Qt.callLater(function () { root.evaluateGuards() })
        }
    }

    Timer {
        id: clockTimer
        interval: 1000
        repeat: true
        running: root.opened
        triggeredOnStart: true
        onTriggered: root.refreshClock()
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        watchChanges: true
        printErrors: false
        onLoaded: root.hostname = String(text() || "").trim()
        onFileChanged: reload()
    }

    Process {
        id: ipProc
        property string collected: ""
        stdout: SplitParser {
            onRead: function (data) { ipProc.collected += data }
        }
        onExited: root.applyAddress(ipProc.collected)
    }

    Component.onCompleted: {
        root.refreshClock()
        root.refreshAddress()
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "lcars-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        Shortcut {
            sequences: ["Ctrl+F", "Ctrl+D", "Ctrl+P"]
            enabled: root.opened
            onActivated: root.toggleFavoriteSelected()
        }

        Rectangle {
            anchors.fill: parent
            color: root.bg
            visible: root.opened

            MouseArea {
                anchors.fill: parent
                onClicked: root.dismiss()
            }

            Item {
                id: frame
                anchors.fill: parent
                anchors.margins: root.frameMargin

                MouseArea {
                    anchors.fill: parent
                    onClicked: searchInput.forceActiveFocus()
                }

                Elbow {
                    id: topLeft
                    corner: "bl"
                    color: root.bluey
                    cutout: root.bg
                    radius: root.elbowRadius
                    innerRadius: root.innerRadius
                    armThickness: root.barHeight
                    innerCut: true
                    width: root.railWidth
                    height: 176
                    z: 1
                    anchors.top: parent.top
                    anchors.left: parent.left

                    FramePanel {
                        anchors.top: parent.top
                        width: parent.width
                        height: 108
                        color: root.africanViolet
                        fontFamily: root.lcarsFont
                        fontPixelSize: 15
                        label: "LCARS Launcher"
                        seamBottom: 4
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 12
                        anchors.bottomMargin: root.barHeight + 10
                        text: "02-ACCESS"
                        color: root.bg
                        font.family: root.lcarsFont
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                    }
                }

                Item {
                    id: topRight
                    anchors.left: topLeft.right
                    anchors.right: parent.right
                    anchors.top: topLeft.top
                    anchors.bottom: topLeft.bottom

                    Text {
                        id: clockLabel
                        anchors.top: parent.top
                        anchors.right: parent.right
                        text: root.clockText
                        color: root.orange
                        font.family: root.lcarsFont
                        font.pixelSize: 44
                        font.weight: Font.Normal
                        font.capitalization: Font.AllUppercase
                    }

                    Text {
                        id: bannerBullet
                        anchors.top: clockLabel.top
                        anchors.right: clockLabel.left
                        text: "  •  "
                        color: root.orange
                        font.family: root.lcarsFont
                        font.pixelSize: 44
                        font.weight: Font.Normal
                    }

                    Text {
                        id: banner
                        anchors.top: parent.top
                        anchors.right: bannerBullet.left
                        anchors.left: parent.left
                        anchors.leftMargin: root.contentPad
                        text: root.hostname.length ? root.hostname : "LCARS"
                        color: root.orange
                        font.family: root.lcarsFont
                        font.pixelSize: 44
                        font.weight: Font.Normal
                        font.capitalization: Font.AllUppercase
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }

                    Row {
                        id: ipRow
                        anchors.top: banner.bottom
                        anchors.topMargin: 6
                        anchors.right: parent.right
                        spacing: 22

                        Text {
                            width: 64
                            text: root.ip0
                            color: root.africanViolet
                            font.family: root.lcarsFont
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            width: 64
                            text: root.ip1
                            color: root.africanViolet
                            font.family: root.lcarsFont
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            width: 64
                            text: root.ip2
                            color: root.africanViolet
                            font.family: root.lcarsFont
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            width: 64
                            text: root.ip3
                            color: root.africanViolet
                            font.family: root.lcarsFont
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Row {
                        id: statRow
                        anchors.top: ipRow.bottom
                        anchors.topMargin: 2
                        anchors.right: parent.right
                        spacing: 22

                        Repeater {
                            model: [
                                ["93", "1853"],
                                ["7", "7024"],
                                ["05", "21509"],
                                ["80", "2048"]
                            ]
                            delegate: Column {
                                required property var modelData
                                spacing: 1
                                Repeater {
                                    model: modelData
                                    delegate: Text {
                                        required property string modelData
                                        width: 64
                                        text: modelData
                                        color: root.orange
                                        font.family: root.lcarsFont
                                        font.pixelSize: 18
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }

                    PillBar {
                        id: topBar
                        height: root.barHeight
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        fontFamily: root.lcarsFont
                        spacing: 5
                        segments: [
                            { width: Math.max(240, Math.round(topRight.width * 0.38)), color: root.bluey },
                            { width: 22, color: root.orange },
                            { width: 86, color: root.africanViolet },
                            { fill: true, color: root.africanViolet },
                            { width: 22, color: root.red }
                        ]
                    }


                }

                Rectangle {
                    id: bottomLeft
                    // Black behind the elbow so almond cannot leak through the outer curve.
                    color: root.bg
                    clip: false
                    width: root.railWidth
                    anchors.top: topLeft.bottom
                    anchors.topMargin: root.frameGap
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left

                    Elbow {
                        id: bottomElbow
                        corner: "tl"
                        color: root.red
                        cutout: root.bg
                        radius: root.elbowRadius
                        innerRadius: root.innerRadius
                        armThickness: root.barHeight
                        innerCut: true
                        width: parent.width
                        height: 180
                        z: 1
                        anchors.top: parent.top
                        anchors.left: parent.left

                        FramePanel {
                            anchors.fill: parent
                            color: "transparent"
                            fontFamily: root.lcarsFont
                            fontPixelSize: 16
                            hop: "03-"
                            label: "QUERY"
                            seamBottom: 4
                            padding: 12
                        }
                    }

                    FramePanel {
                        id: panelScan
                        anchors.top: bottomElbow.bottom
                        width: parent.width
                        height: 56
                        color: root.orange
                        fontFamily: root.lcarsFont
                        fontPixelSize: 16
                        hop: "04-"
                        label: "SCAN"
                    }

                    FramePanel {
                        id: panelPri
                        anchors.top: panelScan.bottom
                        width: parent.width
                        height: 40
                        color: root.butterscotch
                        fontFamily: root.lcarsFont
                        fontPixelSize: 16
                        hop: "05-"
                        label: "1701"
                    }

                    FramePanel {
                        id: panelReady
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 80
                        color: root.bluey
                        fontFamily: root.lcarsFont
                        fontPixelSize: 16
                        hop: "07-"
                        label: String(root.query || "").length ? "SCANNING" : "READY"
                        seamTop: 4
                        seamBottom: 0
                    }

                    Rectangle {
                        anchors.top: panelPri.bottom
                        anchors.bottom: panelReady.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        color: root.almond
                    }
                }

                Item {
                    id: bottomRight
                    anchors.left: bottomLeft.right
                    anchors.right: parent.right
                    anchors.top: bottomLeft.top
                    anchors.bottom: parent.bottom

                    StatusStrip {
                        id: bottomBar
                        height: root.barHeight
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        fontFamily: root.lcarsFont
                        capColor: root.red
                        tickColor: root.butterscotch
                        midColor: root.africanViolet
                        endColor: root.butterscotch
                    }

                    Item {
                        id: queryBar
                        height: 36
                        anchors.top: bottomBar.bottom
                        anchors.topMargin: root.innerRadius + 12
                        anchors.left: parent.left
                        anchors.leftMargin: root.contentPad
                        width: Math.min(root.contentWidth, Math.max(0, parent.width - root.contentPad))

                        PillBar {
                            anchors.fill: parent
                            fontFamily: root.lcarsFont
                            spacing: 0
                            segments: [
                                { width: 36, color: root.sienna, pillLeft: true },
                                { fill: true, color: root.butterscotch }
                            ]
                        }

                        Rectangle {
                            width: 10
                            height: parent.height
                            color: root.bg
                            x: 28
                        }

                        Text {
                            id: queryLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 52
                            text: "QUERY"
                            color: root.barley
                            font.family: root.lcarsFont
                            font.pixelSize: 32
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -12
                                anchors.rightMargin: -12
                                color: root.bg
                                z: -1
                            }
                        }

                        Item {
                            id: searchField
                            property bool cursorOn: true
                            anchors.left: queryLabel.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 0
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            z: 1

                            Rectangle {
                                anchors.fill: parent
                                color: root.bg
                            }

                            Timer {
                                interval: 530
                                running: searchInput.activeFocus
                                repeat: true
                                onTriggered: searchField.cursorOn = !searchField.cursorOn
                                onRunningChanged: searchField.cursorOn = true
                            }

                            Text {
                                id: queryPlaceholder
                                visible: root.query.length === 0
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ENTER SEARCH STRING"
                                color: root.trueMauve
                                opacity: 0.7
                                font.family: root.lcarsFont
                                font.pixelSize: 26
                                font.capitalization: Font.AllUppercase
                            }

                            TextInput {
                                id: searchInput
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28
                                color: root.almondCreme
                                font.family: root.lcarsFont
                                font.pixelSize: 26
                                font.weight: Font.Normal
                                font.capitalization: Font.AllUppercase
                                clip: true
                                cursorVisible: true
                                text: root.query
                                onTextChanged: root.query = text
                                cursorDelegate: Rectangle {
                                    width: 2
                                    height: 22
                                    color: root.almondCreme
                                    opacity: searchInput.activeFocus && searchField.cursorOn ? 1 : 0
                                }
                                Keys.priority: Keys.BeforeItem
                                Keys.onEscapePressed: root.handleEscape()
                                Keys.onUpPressed: root.selectDelta(-1)
                                Keys.onDownPressed: root.selectDelta(1)
                                Keys.onReturnPressed: root.launchSelected()
                                Keys.onEnterPressed: root.launchSelected()
                                Keys.onPressed: function (event) {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_F || event.key === Qt.Key_D || event.key === Qt.Key_P)) {
                                        root.toggleFavoriteSelected()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Right && !String(root.query || "").length) {
                                        root.launchSelected()
                                        event.accepted = true
                                    } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !String(root.query || "").length) {
                                        if (root.goBack()) event.accepted = true
                                    } else if (event.key === Qt.Key_PageUp) {
                                        root.selectDelta(-8)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_PageDown) {
                                        root.selectDelta(8)
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: resultsWell
                        anchors.top: queryBar.bottom
                        anchors.topMargin: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: root.contentPad
                        width: Math.min(root.contentWidth, Math.max(0, parent.width - root.contentPad))

                        Text {
                            id: resultsHeader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: {
                                if (String(root.query || "").length)
                                    return resultModel.count === 0
                                           ? "NO MATCHES"
                                           : (resultModel.count + (resultModel.count === 1 ? " MATCH" : " MATCHES"))
                                if (resultModel.count === 0) return "NO ENTRIES"
                                return root.currentTitle
                            }
                            color: root.africanViolet
                            font.family: root.lcarsFont
                            font.pixelSize: 18
                            font.weight: Font.Normal
                            font.capitalization: Font.AllUppercase
                        }

                        Text {
                            id: resultsPath
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: resultsHeader.bottom
                            anchors.topMargin: height > 0 ? 2 : 0
                            height: root.currentPath.length > 0 && String(root.query || "").length === 0 ? 16 : 0
                            text: root.currentPath
                            color: root.trueMauve
                            font.family: root.lcarsFont
                            font.pixelSize: 13
                            font.capitalization: Font.AllUppercase
                            elide: Text.ElideLeft
                            clip: true
                        }

                        ListView {
                            id: resultList
                            anchors.top: resultsPath.bottom
                            anchors.topMargin: 12
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            model: resultModel
                            clip: true
                            spacing: 5
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: ResultRow {
                                width: resultList.width
                                rowIndex: model.index
                                label: model.label
                                subtext: model.subtext
                                kind: model.kind
                                selected: root.selectedIndex === model.index
                                favorite: model.favorite
                                fontFamily: root.lcarsFont
                                onClicked: root.activateIndex(model.index)
                                onHovered: function (x, y) { root.hoverRow(model.index, x, y) }
                                onFavoriteClicked: root.toggleFavoriteIndex(model.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
