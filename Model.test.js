var M = require("./Model.js")
var fails = 0

function assert(cond, msg) {
    if (!cond) {
        fails++
        console.error("FAIL:", msg)
    }
}

var apps = [
    { id: "firefox", name: "Firefox", genericName: "Web Browser", comment: "Browse the web", keywords: ["browser", "web"] },
    { id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", noDisplay: false },
    { id: "hidden.App", name: "Hidden", noDisplay: true },
    { id: "kitty", name: "Kitty", genericName: "Terminal" },
    { id: "org.kde.konsole", name: "Konsole", genericName: "Terminal" }
]

var fox = apps[0]
assert(M.fuzzyScore(fox, "fire") > M.fuzzyScore(fox, "web"), "prefix beats comment match")
assert(M.fuzzyScore(fox, "wb") > 0, "acronym wb matches Web Browser")
assert(M.fuzzyScore(fox, "zzz") < 0, "non-match is negative")

var empty = M.search(apps, "", {}, 50, 0)
assert(empty.length === 4, "empty query skips noDisplay, got " + empty.length)
assert(empty[0].name === "Files", "empty query is alphabetical, got " + empty[0].name)

var fired = M.search(apps, "fire", {}, 50, 0)
assert(fired.length === 1 && fired[0].id === "firefox", "fire finds Firefox")

var acro = M.search(apps, "fm", {}, 50, 0)
assert(acro.some(function (r) { return r.id === "org.gnome.Nautilus" }), "acronym fm finds Files")

var usage = M.recordUsage({}, "kitty", 1000)
usage = M.recordUsage(usage, "kitty", 2000)
assert(usage.kitty.count === 2 && usage.kitty.last === 2000, "usage increments")

var ranked = M.search(apps, "", usage, 50, 2000)
assert(ranked[0].id === "kitty", "usage boost ranks Kitty first, got " + ranked[0].id)

var parsed = M.parseUsage('{"firefox":{"count":3,"last":9}}')
assert(parsed.firefox.count === 3, "parseUsage reads counts")
assert(M.parseUsage("not-json").firefox === undefined, "parseUsage survives junk")

var jsonc = M.parseMenuJsonc('{\n  // comment\n  "system": {"label":"System"},\n  "system.lock": {"label":"Lock","action":"omarchy-system-lock","aliases":["lock"]},\n  "apps": {"label":"Apps","provider":"apps"},\n  "about": {"label":"About","action":"omarchy-launch-about"},\n}\n')
assert(jsonc.length === 4, "parseMenuJsonc strips comments and trailing commas, got " + jsonc.length)
var lock = null
for (var i = 0; i < jsonc.length; i++) if (jsonc[i].id === "system.lock") lock = jsonc[i]
assert(lock && lock.kind === "action" && lock.parent === "system", "dotted ids infer parent and action kind")

var merged = M.mergeMenuSources(jsonc, [{ id: "about", label: "About Omarchy", action: "omarchy-launch-about" }])
assert(merged.items.about.label === "About Omarchy", "user JSONC overrides default label")
var actions = M.flattenMenuActions(merged.items, merged.itemOrder)
assert(actions.length === 2, "flatten keeps leaf actions only, got " + actions.length)
assert(actions.some(function (r) { return r.id === "menu:system.lock" && r.genericName === "System" }), "lock path is System")
assert(!actions.some(function (r) { return r.id.indexOf("apps") >= 0 }), "provider rows are not flattened")

var mixed = apps.concat(actions)
var emptyMenu = M.search(mixed, "", {}, 50, 0)
assert(!emptyMenu.some(function (r) { return r.id.indexOf("menu:") === 0 }), "empty query skips unused menu actions")

var now = 1000000000000
var stale = { oldie: { count: 10, last: now - 30 * 24 * 3600000 }, fresh: { count: 2, last: now - 3600000 } }
var freqApps = [
    { id: "oldie", name: "Oldie" },
    { id: "fresh", name: "Fresh" }
]
var freq = M.search(freqApps, "", stale, 50, now)
assert(freq[0].id === "fresh", "frecency prefers recent uses over stale count, got " + freq[0].id)

var fav = M.toggleFavorite({}, "menu:system.lock")
assert(fav["menu:system.lock"].favorite === true, "toggleFavorite pins")
var emptyFav = M.search(mixed, "", fav, 50, 0)
assert(emptyFav[0].id === "menu:system.lock" && emptyFav[0].favorite, "favorited menu action leads empty query")
var unfav = M.toggleFavorite(fav, "menu:system.lock")
assert(unfav["menu:system.lock"] === undefined, "unfavorite drops unused record")

var foundLock = M.search(mixed, "lock", {}, 50, 0)
assert(foundLock.some(function (r) { return r.id === "menu:system.lock" }), "query lock finds menu action")

var round = M.parseUsage(M.serializeUsage(M.toggleFavorite(M.recordUsage({}, "kitty", 9), "kitty")))
assert(round.kitty.count === 1 && round.kitty.favorite === true, "usage json keeps favorite")

var tree = M.mergeMenuSources(jsonc, [])
var rootRows = M.browseRows(tree.items, tree.itemOrder, "root", "", {}, {}, {}, 0)
assert(rootRows.some(function (r) { return r.itemId === "system" && (r.kind === "menu" || r.kind === "link") }), "root lists System submenu")
assert(rootRows.some(function (r) { return r.itemId === "about" && r.kind === "action" }), "root lists About action")
assert(!rootRows.some(function (r) { return r.itemId === "system.lock" }), "root empty does not list nested Lock")

var sysRows = M.browseRows(tree.items, tree.itemOrder, "system", "", {}, {}, {}, 0)
assert(sysRows.length === 1 && sysRows[0].itemId === "system.lock", "System drills to Lock")

var guardedJson = M.parseMenuJsonc('{\n'
    + '  "system": {"label":"System"},\n'
    + '  "system.hibernate": {"label":"Hibernate","when":"false","action":"systemctl hibernate"},\n'
    + '  "system.lock": {"label":"Lock","when":"true","checked":"true","action":"loginctl lock-session"},\n'
    + '  "system.browser": {"label":"Browser","when":"true","checked":"[[ \\"$(omarchy-default-browser)\\" == \\"firefox\\" ]]","action":"true"}\n'
    + '}\n')
var guarded = M.mergeMenuSources(guardedJson, [])
var guardText = M.guardScript(guarded.items, guarded.itemOrder)
assert(guardText.indexOf("omarchy-pkg-present") >= 0, "guard script includes package helpers")
assert(guardText.indexOf("system.hibernate:w:") >= 0, "when guard is emitted")
assert(guardText.indexOf("system.lock:c:") >= 0, "checked guard is emitted")
assert(guardText.indexOf('${__omarchy_read_2}') >= 0, "default browser is read through a slot")
var browserCaptures = guardText.split("__omarchy_read_2=$(omarchy-default-browser ").length - 1
assert(browserCaptures === 1, "default browser is captured once, got " + browserCaptures)
assert(guardText.indexOf("$(omarchy-default-browser)") < 0, "plain reader call is substituted out of the guards")
var guardOut = require("child_process").execFileSync("bash", ["-lc", guardText], { encoding: "utf8" })
var guardParsed = M.parseGuardOutput(guardOut)
assert(guardParsed.whenResults["system.hibernate"] === false, "false when hides")
assert(guardParsed.whenResults["system.lock"] === true, "true when shows")
assert(guardParsed.checkedResults["system.lock"] === true, "true checked marks")
var guardedRows = M.browseRows(guarded.items, guarded.itemOrder, "system", "", guardParsed.whenResults, guardParsed.checkedResults, {}, 0)
assert(!guardedRows.some(function (r) { return r.itemId === "system.hibernate" }), "browse hides a failed when")
assert(guardedRows.some(function (r) { return r.itemId === "system.lock" && r.label.indexOf("✓") >= 0 }), "browse marks a true checked")
var unanswered = M.browseRows(guarded.items, guarded.itemOrder, "system", "", {}, {}, {}, 0)
assert(unanswered.some(function (r) { return r.itemId === "system.hibernate" }), "unanswered when still shows")

var searchRows = M.browseRows(tree.items, tree.itemOrder, "root", "lock", {}, {}, {}, 0)
assert(searchRows.some(function (r) { return r.itemId === "system.lock" && r.section === "drilldown" }), "root search lock is a drilldown hit")
assert(M.resolveRoute(tree.items, tree.itemOrder, "lock") === "system.lock", "alias lock routes to system.lock")

if (fails) {
    console.error(fails + " failed")
    process.exit(1)
}
console.log("ok")
