/*
 * Settings page: which monitor to watch on, and what happens to the rest.
 * The monitor list comes from `nightwatch displays`, so it shows whatever is
 * connected right now. Monitors are stored by connector (HDMI-A-1, DP-3...),
 * which stays unique even with two identical models.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property string cfg_display
    property string cfg_displayDefault
    property bool   cfg_dimOthers
    property bool   cfg_dimOthersDefault
    // set from the popup, not here; declared so Plasma can hand them over
    property string cfg_cutoff
    property string cfg_cutoffDefault
    property int    cfg_temp
    property int    cfg_tempDefault
    property int    cfg_pct
    property int    cfg_pctDefault

    readonly property string script:
        decodeURIComponent(Qt.resolvedUrl("../code/nightwatch").toString().replace(/^file:\/\//, ""))

    property bool loaded: false
    property bool anyUncontrollable: false

    ListModel { id: displays }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            page.fill(data["stdout"])
            disconnectSource(source)
        }
    }
    Component.onCompleted: sh.connectSource("bash '" + script + "' displays")

    function fill(out) {
        displays.clear()
        displays.append({ value: "", label: i18n("Automatic (first connected monitor)") })
        var found = false, missing = false
        out.trim().split("\n").forEach(function (line) {
            var f = line.split("\t")
            if (f.length < 3) return
            var label = i18nc("monitor model (connector)", "%1 (%2)", f[2], f[0])
            if (f[1] !== "1") { label = i18n("%1 – no brightness control", label); missing = true }
            displays.append({ value: f[0], label: label })
            if (f[0] === cfg_display) found = true
        })
        // keep a saved choice visible even while that monitor is unplugged
        if (cfg_display !== "" && !found)
            displays.append({ value: cfg_display,
                              label: i18n("%1 (not connected)", cfg_display) })
        anyUncontrollable = missing
        displayBox.currentIndex = Math.max(0, displayBox.indexOfValue(cfg_display))
        loaded = true
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: displayBox
            Kirigami.FormData.label: i18n("Watch on:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            enabled: page.loaded
            model: displays
            textRole: "label"
            valueRole: "value"
            onActivated: page.cfg_display = currentValue
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Other screens:")
            text: i18n("Turn down to 0% while night viewing is on")
            checked: page.cfg_dimOthers
            onToggled: page.cfg_dimOthers = checked
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.anyUncontrollable
            type: Kirigami.MessageType.Information
            text: i18n("A monitor without brightness control is either not DDC/CI capable or was not registered by PowerDevil at login. Turning night viewing on restarts PowerDevil to retry, at most twice per login.")
        }
    }
}
