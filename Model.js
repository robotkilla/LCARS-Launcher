// Pure JS search/ranking for LCARS Launcher. No QML imports.
// Testable with Node: `node Model.test.js`

function entryName(entry) {
    return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
    return String((entry && entry.genericName) || "")
}

function entryId(entry) {
    return String((entry && entry.id) || "")
}

function entryIcon(entry) {
    return String((entry && entry.icon) || "")
}

function keywordText(entry) {
    try {
        if (entry && entry.keywords && typeof entry.keywords.join === "function")
            return entry.keywords.join(" ")
        if (entry && entry.keywords && entry.keywords.length) {
            var parts = []
            for (var i = 0; i < entry.keywords.length; i++)
                parts.push(String(entry.keywords[i] || ""))
            return parts.join(" ")
        }
    } catch (e) {
    }
    return ""
}

function entrySearchText(entry) {
    if (!entry) return ""
    return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
    return String(value || "")
        .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
        .replace(/[._:/\\-]+/g, " ")
        .toLowerCase()
}

function words(value) {
    var values = wordText(value).split(/[^a-z0-9]+/)
    var result = []
    for (var i = 0; i < values.length; i++) {
        if (values[i]) result.push(values[i])
    }
    return result
}

function entryAcronym(entry) {
    var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
    var result = ""
    for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
    return result
}

function termMatches(entry, term) {
    if (!term) return true

    var name = entryName(entry).toLowerCase()
    var id = entryId(entry).toLowerCase()
    var haystack = entrySearchText(entry)

    if (name.indexOf(term) >= 0) return true
    if (id.indexOf(term) >= 0) return true
    if (haystack.indexOf(term) >= 0) return true

    return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && !termMatches(entry, terms[i])) return false
    }
    return true
}

function fuzzyScore(entry, query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return 0
    if (!allTermsMatch(entry, q)) return -1

    var name = entryName(entry).toLowerCase()
    var id = entryId(entry).toLowerCase()
    var haystack = entrySearchText(entry)
    var directName = name.indexOf(q)
    var directId = id.indexOf(q)
    if (directName === 0) return 10000 - name.length
    if (directId === 0) return 9500 - id.length
    if (directName > 0) return 8000 - directName * 10 - name.length
    if (directId > 0) return 7600 - directId * 10 - id.length

    var hayIndex = haystack.indexOf(q)
    if (hayIndex >= 0) return 6000 - hayIndex

    var acronym = entryAcronym(entry)
    var acronymIndex = acronym.indexOf(q)
    if (acronymIndex === 0) return 5000 - acronym.length
    if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

    return 4000 - name.length
}

function isFavorite(rec) {
    return !!(rec && rec.favorite)
}

function isUsed(rec) {
    if (!rec) return false
    return (Number(rec.count) || 0) > 0 || (Number(rec.last) || 0) > 0
}

function cloneUsageRecord(rec) {
    var src = rec || {}
    var out = {
        count: Math.max(0, Number(src.count) || 0),
        last: Math.max(0, Number(src.last) || 0)
    }
    if (src.favorite) out.favorite = true
    return out
}

// Half-life 72h: recent repeats outrank a stale high count.
function frecencyScore(rec, now) {
    if (!rec) return 0
    var count = Number(rec.count) || 0
    var last = Number(rec.last) || 0
    if (count <= 0 && last <= 0) return 0
    var stamp = Number(now) || Date.now()
    var hours = last > 0 ? Math.max(0, (stamp - last) / 3600000) : 9999
    var decay = Math.pow(0.5, hours / 72)
    var freq = Math.log(1 + Math.max(0, count)) / Math.LN2
    return Math.round(freq * 800 * decay + Math.max(0, 300 - hours))
}

function usageBoost(id, usage, now) {
    if (!usage || !id) return 0
    return frecencyScore(usage[id], now)
}

function search(values, query, usage, limit, now) {
    var q = String(query || "").trim()
    var cap = Number(limit) > 0 ? Number(limit) : 50
    var stamp = Number(now) || Date.now()
    var rows = []
    var list = values || []
    var stats = usage || {}

    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (!entry || entry.noDisplay === true) continue
        var name = entryName(entry)
        if (!name) continue
        var id = entryId(entry)
        var rec = stats[id]
        var favorited = isFavorite(rec)
        var kind = String(entry.kind || "app")
        if (!q && kind !== "app" && !favorited && !isUsed(rec)) continue
        var score = fuzzyScore(entry, q)
        if (score < 0) continue
        score += frecencyScore(rec, stamp)
        rows.push({
            id: id,
            name: name,
            genericName: entrySubtext(entry),
            icon: entryIcon(entry),
            kind: kind,
            action: String(entry.action || ""),
            favorite: favorited,
            score: score,
            key: name.toLowerCase()
        })
    }

    rows.sort(function (a, b) {
        if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
        if (a.score !== b.score) return b.score - a.score
        if (a.key < b.key) return -1
        if (a.key > b.key) return 1
        return 0
    })

    if (rows.length > cap) rows.length = cap
    return rows
}

function parseUsage(raw) {
    var out = {}
    try {
        var parsed = JSON.parse(String(raw || "{}"))
        if (!parsed || typeof parsed !== "object" || parsed.length) return out
        for (var id in parsed) {
            if (!Object.prototype.hasOwnProperty.call(parsed, id)) continue
            var rec = parsed[id]
            if (!rec || typeof rec !== "object") continue
            out[String(id)] = cloneUsageRecord(rec)
        }
    } catch (e) {
    }
    return out
}

function serializeUsage(usage) {
    return JSON.stringify(usage || {}, null, 2) + "\n"
}

function copyUsage(usage) {
    var next = {}
    var src = usage || {}
    for (var k in src) {
        if (!Object.prototype.hasOwnProperty.call(src, k)) continue
        next[k] = cloneUsageRecord(src[k])
    }
    return next
}

function pruneUsage(next) {
    var ids = []
    for (var n in next) ids.push(n)
    if (ids.length <= 200) return next
    ids.sort(function (a, b) {
        var af = next[a] && next[a].favorite ? 1 : 0
        var bf = next[b] && next[b].favorite ? 1 : 0
        if (af !== bf) return af - bf
        return (next[a].last || 0) - (next[b].last || 0)
    })
    for (var i = 0; i < ids.length - 200; i++)
        delete next[ids[i]]
    return next
}

function recordUsage(usage, id, now) {
    var key = String(id || "")
    var next = copyUsage(usage)
    if (!key) return next
    var rec = next[key] || { count: 0, last: 0 }
    rec.count = (rec.count || 0) + 1
    rec.last = Number(now) || Date.now()
    next[key] = rec
    return pruneUsage(next)
}

function toggleFavorite(usage, id) {
    var key = String(id || "")
    var next = copyUsage(usage)
    if (!key) return next
    var rec = next[key] || { count: 0, last: 0 }
    rec.favorite = !rec.favorite
    if (!rec.favorite) {
        delete rec.favorite
        if ((rec.count || 0) <= 0 && (rec.last || 0) <= 0) {
            delete next[key]
            return next
        }
    }
    next[key] = rec
    return pruneUsage(next)
}

function stripJsonc(raw) {
    return String(raw || "")
        .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
        .replace(/,(\s*[}\]])/g, "$1")
}

function normalizeAliases(value) {
    if (Object.prototype.toString.call(value) === "[object Array]") {
        var list = []
        for (var i = 0; i < value.length; i++) {
            if (value[i]) list.push(String(value[i]))
        }
        return list
    }
    if (typeof value === "string" && value) return [value]
    return []
}

function normalizeMenuItem(id, raw) {
    var value = raw || {}
    var parent = value.parent
    if (parent === undefined)
        parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root"
    if (id === "root") parent = ""
    var kind = value.action ? "action" : (value.target ? "link" : "menu")
    return {
        id: id,
        parent: parent,
        kind: kind,
        icon: value.icon || "",
        label: value.label || id,
        title: value.title || "",
        target: value.target || "",
        description: value.description || "",
        action: value.action || "",
        provider: value.provider || "",
        aliases: normalizeAliases(value.aliases),
        when: value.when || "",
        checked: value.checked || ""
    }
}

function parseMenuJsonc(raw) {
    var stripped = stripJsonc(raw)
    if (!stripped.trim()) return []
    var parsed
    try {
        parsed = JSON.parse(stripped)
    } catch (e) {
        return []
    }
    if (typeof parsed !== "object" || parsed === null) return []
    var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items))
        ? parsed.items
        : parsed
    var out = []
    for (var id in source) {
        if (!Object.prototype.hasOwnProperty.call(source, id)) continue
        var entry = source[id]
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
        out.push(normalizeMenuItem(id, entry))
    }
    return out
}

function mergeMenuSources(defaultItems, userItems) {
    var nextItems = {}
    var nextOrder = []
    var sources = [defaultItems || [], userItems || []]
    for (var s = 0; s < sources.length; s++) {
        var src = sources[s]
        for (var i = 0; i < src.length; i++) {
            var entry = src[i]
            if (!entry || !entry.id) continue
            if (!nextItems[entry.id]) nextOrder.push(entry.id)
            var prior = nextItems[entry.id] || {}
            var merged = {}
            for (var k in prior) merged[k] = prior[k]
            for (var k2 in entry) merged[k2] = entry[k2]
            merged.id = entry.id
            nextItems[entry.id] = merged
        }
    }
    if (!nextItems.root) {
        nextItems.root = {
            id: "root",
            parent: "",
            kind: "menu",
            icon: "",
            label: "Go",
            title: "",
            target: "",
            description: "",
            action: "",
            provider: "",
            aliases: [],
            when: "",
            checked: ""
        }
        nextOrder.unshift("root")
    }
    for (var k3 = 0; k3 < nextOrder.length; k3++)
        nextItems[nextOrder[k3]].order = k3
    return { items: nextItems, itemOrder: nextOrder }
}

function mergeAppRows(items, itemOrder, appRows) {
    var source = items || {}
    var order = Array.isArray(itemOrder) ? itemOrder : []
    var rows = Array.isArray(appRows) ? appRows : []
    var nextItems = {}
    var nextOrder = []
    for (var i = 0; i < order.length; i++) {
        var id = order[i]
        var existing = source[id]
        if (!existing || existing.kind === "app") continue
        nextItems[id] = existing
        nextOrder.push(id)
    }
    for (var j = 0; j < rows.length; j++) {
        var row = rows[j]
        if (!row || !row.id || nextItems[row.id]) continue
        row.order = nextOrder.length
        nextItems[row.id] = row
        nextOrder.push(row.id)
    }
    return { items: nextItems, itemOrder: nextOrder }
}

function swapProviderRows(items, itemOrder, menuId, rows) {
    var source = items || {}
    var order = Array.isArray(itemOrder) ? itemOrder : []
    var incoming = Array.isArray(rows) ? rows : []
    var nextItems = {}
    var nextOrder = []
    for (var i = 0; i < order.length; i++) {
        var id = order[i]
        var existing = source[id]
        if (!existing || existing.providerMenu === menuId) continue
        nextItems[id] = existing
        nextOrder.push(id)
    }
    for (var j = 0; j < incoming.length; j++) {
        var row = incoming[j]
        if (!row || !row.id || nextItems[row.id]) continue
        row.providerMenu = menuId
        row.order = nextOrder.length
        nextItems[row.id] = row
        nextOrder.push(row.id)
    }
    return { items: nextItems, itemOrder: nextOrder }
}

function resolveRoute(items, itemOrder, input) {
    var raw = String(input || "").toLowerCase().replace(/_/g, "-")
    if (!raw || raw === "go" || raw === "menu") return "root"
    if (menuItem(items, raw)) return raw
    var order = Array.isArray(itemOrder) ? itemOrder : []
    for (var i = 0; i < order.length; i++) {
        var entry = menuItem(items, order[i])
        if (!entry || entry.kind === "app" || !entry.aliases) continue
        for (var j = 0; j < entry.aliases.length; j++) {
            var alias = String(entry.aliases[j] || "").toLowerCase().replace(/_/g, "-")
            if (alias === raw) return entry.id
        }
    }
    return raw
}

function slugify(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item"
}

function depthFor(items, id) {
    var depth = 0
    var current = menuItem(items, id)
    var guard = 0
    while (current && current.parent && current.parent !== "root" && guard < 32) {
        depth += 1
        current = menuItem(items, current.parent)
        guard += 1
    }
    return depth
}

function pathFor(items, id) {
    return menuPath(items, id)
}

function parentPathFor(items, id) {
    return menuParentPath(items, id)
}

function isDescendantOf(items, id, ancestorId) {
    if (ancestorId === "root") return id !== "root"
    var current = menuItem(items, id)
    var guard = 0
    while (current && current.parent && guard < 32) {
        if (current.parent === ancestorId) return true
        current = menuItem(items, current.parent)
        guard += 1
    }
    return false
}

function childCount(items, itemOrder, id) {
    var count = 0
    var order = Array.isArray(itemOrder) ? itemOrder : []
    for (var i = 0; i < order.length; i++) {
        var entry = menuItem(items, order[i])
        if (entry && entry.parent === id) count += 1
    }
    return count
}

function isVisible(items, itemOrder, whenResults, entry, depth) {
    if (!entry) return false
    if (entry.when && whenResults && whenResults[entry.id] === false) return false
    if (entry.kind !== "menu" && entry.kind !== "link") return true
    if (entry.provider) return true
    var guard = depth || 0
    if (guard >= 32) return false
    var target = entry.kind === "link" ? entry.target : entry.id
    var order = Array.isArray(itemOrder) ? itemOrder : []
    for (var i = 0; i < order.length; i++) {
        var child = menuItem(items, order[i])
        if (child && child.parent === target && isVisible(items, itemOrder, whenResults, child, guard + 1))
            return true
    }
    return false
}

function labelFor(entry, checkedResults) {
    if (!entry) return ""
    if (entry.checked && checkedResults && checkedResults[entry.id]) return entry.label + " ✓"
    return entry.label
}

function searchableToken(value) {
    return String(value || "").replace(/[._-]+/g, " ")
}

function leafIdFor(id) {
    var parts = String(id || "").split(".")
    return parts.length > 0 ? parts[parts.length - 1] : id
}

function nameSearchText(entry) {
    if (!entry) return ""
    var aliases = []
    var values = Array.isArray(entry.aliases) ? entry.aliases : []
    for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
    return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase()
}

function termInSearchWords(term, text) {
    var list = String(text || "").toLowerCase().split(/\s+/)
    for (var i = 0; i < list.length; i++) {
        if (list[i] === term) return true
    }
    return false
}

function descriptionTextMatches(query, text) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && !termInSearchWords(terms[i], text)) return false
    }
    return true
}

function matchesQuery(entry, query, visible) {
    if (!entry || entry.id === "root") return false
    if (!visible) return false
    var nameText = nameSearchText(entry)
    var descriptionText = String(entry.description || "").toLowerCase()
    var terms = String(query || "").toLowerCase().trim().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
        if (!terms[i]) continue
        if (nameText.indexOf(terms[i]) >= 0) continue
        if (termInSearchWords(terms[i], descriptionText)) continue
        return false
    }
    return true
}

function menuSearchScore(items, entry, query) {
    var needle = String(query || "").toLowerCase().trim()
    var label = String(entry.label || "").toLowerCase()
    var nameText = nameSearchText(entry)
    var descriptionText = String(entry.description || "").toLowerCase()
    var score = 80
    if (label === needle) score = entry.parent === "root" ? 2 : 0
    else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) score = 0
    else if (label.indexOf(needle) === 0) score = 10
    else if (label.indexOf(needle) >= 0) score = 30
    else if (nameText.indexOf(needle) >= 0) score = 40
    else if (descriptionTextMatches(needle, descriptionText)) score = 60
    if (entry.kind === "menu" || entry.kind === "link") score -= 2
    if (entry.kind === "app") score -= 5
    return score * 1000 + depthFor(items, entry.id) * 25 + (entry.order || 0)
}

function usageKeyFor(entry) {
    if (!entry) return ""
    if (entry.kind === "app") return String(entry.appId || "").replace(/\.desktop$/, "")
    return "menu:" + entry.id
}

function browseSubtext(items, itemOrder, entry, query, childN) {
    var q = String(query || "").trim()
    if (q) return parentPathFor(items, entry.id)
    if (entry.kind === "menu" || entry.kind === "link") {
        if (childN > 0) return childN === 1 ? "1 ITEM" : (childN + " ITEMS")
        return entry.provider ? "DIRECTORY" : "SUBMENU"
    }
    return String(entry.description || "")
}

function toBrowseRow(items, itemOrder, checkedResults, usage, entry, detail, score, section) {
    var target = entry.kind === "link" ? entry.target : entry.id
    var kids = (entry.kind === "menu" || entry.kind === "link") ? childCount(items, itemOrder, target) : 0
    var key = usageKeyFor(entry)
    return {
        itemId: entry.id,
        kind: entry.kind,
        appId: entry.appId || "",
        label: labelFor(entry, checkedResults),
        target: target || "",
        subtext: detail || "",
        path: pathFor(items, entry.id),
        childCount: kids,
        action: entry.action || "",
        provider: entry.provider || "",
        usageKey: key,
        favorite: isFavorite(usage && usage[key]),
        score: score || 0,
        section: section || ""
    }
}

function browseRows(items, itemOrder, activeId, query, whenResults, checkedResults, usage, now) {
    var active = menuItem(items, activeId) ? activeId : "root"
    var q = String(query || "").trim()
    var order = Array.isArray(itemOrder) ? itemOrder : []
    var stamp = Number(now) || Date.now()
    var stats = usage || {}
    var rows = []

    function decorate(entry, detail, score, section) {
        var row = toBrowseRow(items, itemOrder, checkedResults, stats, entry, detail, score, section)
        if (q) row.score = (row.favorite ? -1000000 : 0) + score - frecencyScore(stats[row.usageKey], stamp)
        return row
    }

    if (q) {
        var currentRows = []
        var drillRows = []
        for (var i = 0; i < order.length; i++) {
            var entry = menuItem(items, order[i])
            if (!entry || entry.id === "root") continue
            if (!isDescendantOf(items, entry.id, active)) continue
            if (!matchesQuery(entry, q, isVisible(items, itemOrder, whenResults, entry))) continue
            var detail = String(entry.description || "")
            if (!detail) detail = parentPathFor(items, entry.id)
            var scored = menuSearchScore(items, entry, q)
            var row = decorate(entry, detail, scored, "")
            if (entry.parent === active) currentRows.push(row)
            else {
                row.section = "drilldown"
                drillRows.push(row)
            }
        }
        var byScore = function (a, b) {
            if (a.score !== b.score) return a.score - b.score
            var ap = String(a.path || "")
            var bp = String(b.path || "")
            if (ap < bp) return -1
            if (ap > bp) return 1
            return 0
        }
        currentRows.sort(byScore)
        drillRows.sort(byScore)
        rows = currentRows.concat(drillRows)
    } else {
        for (var j = 0; j < order.length; j++) {
            var child = menuItem(items, order[j])
            if (!child || child.parent !== active) continue
            if (!isVisible(items, itemOrder, whenResults, child)) continue
            var kids = (child.kind === "menu" || child.kind === "link") ? childCount(items, itemOrder, child.kind === "link" ? child.target : child.id) : 0
            rows.push(decorate(child, browseSubtext(items, itemOrder, child, "", kids), child.order || 0, ""))
        }
        if (active === "apps") {
            rows.sort(function (a, b) {
                var aLabel = String(a.label || "").toLowerCase()
                var bLabel = String(b.label || "").toLowerCase()
                if (aLabel < bLabel) return -1
                if (aLabel > bLabel) return 1
                if (a.itemId < b.itemId) return -1
                if (a.itemId > b.itemId) return 1
                return 0
            })
        }
    }
    return rows
}

function menuItem(items, id) {
    return items && items[id] ? items[id] : null
}

function menuPath(items, id) {
    var labels = []
    var current = menuItem(items, id)
    var guard = 0
    while (current && current.id !== "root" && guard < 32) {
        labels.unshift(current.label)
        current = menuItem(items, current.parent)
        guard += 1
    }
    return labels.join(" › ")
}

function menuParentPath(items, id) {
    var entry = menuItem(items, id)
    if (!entry || !entry.parent || entry.parent === "root") return ""
    return menuPath(items, entry.parent)
}

// `when:` hides a row and `checked:` marks it. Both are bash. Sibling rows
// often read the same command inside $(...), and a value captured in one
// subshell is invisible to the next, so those readers run once up front.
var GUARD_READERS = [
    "omarchy-channel-current",
    "omarchy-default-agent",
    "omarchy-default-browser",
    "omarchy-default-editor",
    "omarchy-default-terminal",
    "omarchy-dns"
]

function guardHelpers() {
    return "declare -A __omarchy_pkgs=()\n"
        + "mapfile -t __omarchy_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi"
        + " | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, \"\") }"
        + " provides && $0 != \"None\" { n = split($0, p, \" \");"
        + " for (i = 1; i <= n; i++) { sub(/[<>=].*/, \"\", p[i]); print p[i] } }'; } 2>/dev/null)\n"
        + "for __omarchy_pkg in \"${__omarchy_pkg_names[@]}\"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n"
        + "__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; "
        + "[[ $1 == *[\\<\\>=]* ]] && { pacman -Q \"$1\" &>/dev/null; return; }; return 1; }\n"
        + "omarchy-pkg-present() { local p; for p in \"$@\"; do __omarchy_pkg_has \"$p\" || return 1; done; return 0; }\n"
        + "omarchy-pkg-missing() { local p; for p in \"$@\"; do __omarchy_pkg_has \"$p\" || return 0; done; return 1; }\n"
        + "omarchy-cmd-present() { local c; for c in \"$@\"; do command -v \"$c\" &>/dev/null || return 1; done; return 0; }\n"
        + "omarchy-cmd-missing() { local c; for c in \"$@\"; do command -v \"$c\" &>/dev/null || return 0; done; return 1; }\n"
}

function guardReaderSlot(index) {
    return "${__omarchy_read_" + index + "}"
}

function substituteGuardReaders(expression) {
    var next = String(expression || "")
    for (var i = 0; i < GUARD_READERS.length; i++)
        next = next.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i))
    return next
}

function guardPrelude(guards) {
    var prelude = guardHelpers()
    for (var i = 0; i < GUARD_READERS.length; i++) {
        if (String(guards || "").indexOf(guardReaderSlot(i)) < 0) continue
        prelude += "__omarchy_read_" + i + "=$(" + GUARD_READERS[i] + " 2>/dev/null) || :\n"
    }
    return prelude
}

function guardLine(id, tag, expression) {
    return "if { " + substituteGuardReaders(expression) + "; } >/dev/null 2>&1; then echo "
        + id + ":" + tag + ":1; else echo " + id + ":" + tag + ":0; fi\n"
}

function guardIds(items, itemOrder) {
    var seen = {}
    var ids = []
    function add(id) {
        if (!id || seen[id]) return
        seen[id] = true
        ids.push(id)
    }
    var order = Array.isArray(itemOrder) ? itemOrder : []
    for (var i = 0; i < order.length; i++) add(order[i])
    var map = items || {}
    for (var key in map) {
        if (Object.prototype.hasOwnProperty.call(map, key)) add(key)
    }
    return ids
}

// One bash script for every guard. Each line is `<id>:<w|c>:<0|1>`.
function guardScript(items, itemOrder) {
    var guards = ""
    var ids = guardIds(items, itemOrder)
    var map = items || {}
    for (var i = 0; i < ids.length; i++) {
        var entry = map[ids[i]]
        if (!entry) continue
        if (entry.when) guards += guardLine(ids[i], "w", entry.when)
        if (entry.checked) guards += guardLine(ids[i], "c", entry.checked)
    }
    return guards ? guardPrelude(guards) + guards : ""
}

function parseGuardOutput(raw) {
    var whenResults = {}
    var checkedResults = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") whenResults[id] = value
        else if (tag === "c") checkedResults[id] = value
    }
    return { whenResults: whenResults, checkedResults: checkedResults }
}

function flattenMenuActions(items, itemOrder) {
    var order = itemOrder || []
    var map = items || {}
    var out = []
    for (var i = 0; i < order.length; i++) {
        var entry = map[order[i]]
        if (!entry || !entry.id || entry.id === "root") continue
        if (entry.kind !== "action" || !entry.action) continue
        if (entry.provider) continue
        out.push({
            id: "menu:" + entry.id,
            name: entry.label || entry.id,
            genericName: menuParentPath(map, entry.id),
            comment: entry.description || "",
            keywords: entry.aliases || [],
            icon: "",
            kind: "action",
            action: entry.action,
            noDisplay: false
        })
    }
    return out
}

if (typeof module !== "undefined") {
    module.exports = {
        entryName: entryName,
        entrySubtext: entrySubtext,
        entryId: entryId,
        entryAcronym: entryAcronym,
        fuzzyScore: fuzzyScore,
        frecencyScore: frecencyScore,
        usageBoost: usageBoost,
        search: search,
        parseUsage: parseUsage,
        serializeUsage: serializeUsage,
        recordUsage: recordUsage,
        toggleFavorite: toggleFavorite,
        stripJsonc: stripJsonc,
        parseMenuJsonc: parseMenuJsonc,
        mergeMenuSources: mergeMenuSources,
        flattenMenuActions: flattenMenuActions,
        mergeAppRows: mergeAppRows,
        swapProviderRows: swapProviderRows,
        resolveRoute: resolveRoute,
        slugify: slugify,
        pathFor: pathFor,
        parentPathFor: parentPathFor,
        isDescendantOf: isDescendantOf,
        childCount: childCount,
        isVisible: isVisible,
        guardScript: guardScript,
        parseGuardOutput: parseGuardOutput,
        matchesQuery: matchesQuery,
        usageKeyFor: usageKeyFor,
        browseRows: browseRows
    }
}
