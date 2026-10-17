/*
 * Night Viewing - a front end for the nightwatch script in contents/code/.
 *
 * Left click opens the popup, middle click toggles straight away.
 * Every control re-runs `nightwatch on ...`, which is safe to call while
 * already on: the script keeps the original restore point.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property bool nwActive: false
    property int  secsLeft: -1

    readonly property string cutoff: Plasmoid.configuration.cutoff
    readonly property int    temp:   Plasmoid.configuration.temp
    readonly property int    pct:    Plasmoid.configuration.pct

    Plasmoid.icon: nwActive ? "redshift-status-on" : "redshift-status-off"
    toolTipMainText: i18n("Night viewing")
    toolTipSubText: !nwActive ? i18n("Off")
        : secsLeft >= 0 ? i18np("On – cutoff in %1 min", "On – cutoff in %1 min",
                                Math.ceil(secsLeft / 60))
                        : i18n("On – no cutoff")

    // ---- running nightwatch ------------------------------------------------
    // The script ships inside this package, so resolve it relative to this
    // file rather than relying on PATH (plasmashell gets the systemd user PATH,
    // which has no ~/.local/bin). It runs through bash because the executable
    // bit may not survive a .plasmoid (zip) install.
    readonly property string script:
        decodeURIComponent(Qt.resolvedUrl("../code/nightwatch").toString().replace(/^file:\/\//, ""))
    // The monitor setting is a connector name (HDMI-A-1...) or empty for
    // automatic; it is quoted anyway since it comes from the config file.
    readonly property string exe: "bash '" + script + "'"
        + " --display '" + Plasmoid.configuration.display.replace(/'/g, "") + "'"
        + " --others " + (Plasmoid.configuration.dimOthers ? "dim" : "leave")
    readonly property string pollCmd: exe + " state"

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            if (source === root.pollCmd) {
                root.parseState(data["stdout"])
            }
            disconnectSource(source)
        }
        // the trailing comment keeps each invocation a distinct source key
        function run(args) { connectSource(root.exe + " " + args + " #" + Date.now()) }
        function poll()    { connectSource(root.pollCmd) }
    }

    function parseState(out) {
        var m = {}
        out.trim().split(/\s+/).forEach(function (kv) {
            var p = kv.split("="); m[p[0]] = p[1]
        })
        nwActive = (m["active"] === "1")
        secsLeft = parseInt(m["left"])
    }

    function apply()   { sh.run("on " + cutoff + " " + temp + " " + pct); soon.restart() }
    function stop()    { sh.run("off"); soon.restart() }
    function toggle()  { nwActive ? stop() : apply() }

    Timer { id: poll; interval: 5000; running: true; repeat: true; onTriggered: sh.poll() }
    Timer { id: soon; interval: 700;  onTriggered: sh.poll() }
    Component.onCompleted: sh.poll()

    // ---- panel icon --------------------------------------------------------
    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.fill: parent
            source: root.Plasmoid.icon
            active: mouse.containsMouse
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function (e) {
                if (e.button === Qt.MiddleButton) root.toggle()
                else root.expanded = !root.expanded
            }
        }
    }

    // ---- popup -------------------------------------------------------------
    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth:  Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 15
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                width: parent.width
                Kirigami.Heading {
                    level: 4
                    text: i18n("Night viewing")
                    Layout.fillWidth: true
                }
                QQC2.Switch {
                    checked: root.nwActive
                    onToggled: root.nwActive !== checked && root.toggle()
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true

                PlasmaComponents.Label { text: i18n("Sleep timer") }
                QQC2.ComboBox {
                    id: cutoffBox
                    Layout.fillWidth: true
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: i18n("30 minutes"), value: "30m" },
                        { label: i18n("1 hour"),     value: "1h"  },
                        { label: i18n("1½ hours"),   value: "90m" },
                        { label: i18n("2 hours"),    value: "2h"  },
                        { label: i18n("3 hours"),    value: "3h"  },
                        { label: i18n("No cutoff"),  value: "none"}
                    ]
                    Component.onCompleted: currentIndex = indexOfValue(root.cutoff)
                    onActivated: {
                        Plasmoid.configuration.cutoff = currentValue
                        if (root.nwActive) root.apply()
                    }
                }

                PlasmaComponents.Label { text: i18n("Warmth") }
                QQC2.ComboBox {
                    id: tempBox
                    Layout.fillWidth: true
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: i18n("2500 K – warm"),       value: 2500 },
                        { label: i18n("2000 K – candlelit"),  value: 2000 },
                        { label: i18n("1500 K – ember"),      value: 1500 },
                        { label: i18n("1000 K – as low as it goes"), value: 1000 }
                    ]
                    Component.onCompleted: currentIndex = indexOfValue(root.temp)
                    onActivated: {
                        Plasmoid.configuration.temp = currentValue
                        if (root.nwActive) root.apply()
                    }
                }

                PlasmaComponents.Label { text: i18n("Brightness") }
                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Slider {
                        id: pctSlider
                        Layout.fillWidth: true
                        from: 1; to: 25; stepSize: 1
                        value: root.pct
                        onMoved: Plasmoid.configuration.pct = Math.round(value)
                        onPressedChanged: if (!pressed && root.nwActive) root.apply()
                    }
                    PlasmaComponents.Label {
                        text: i18nc("brightness percentage", "%1%", Math.round(pctSlider.value))
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                    }
                }
            }

            Item { Layout.fillHeight: true }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                text: !root.nwActive
                    ? i18n("Players keep the screens awake while they play – the sleep timer is what ends the night.")
                    : root.secsLeft >= 0
                        ? i18np("Pausing playback and blanking in %1 min.",
                                "Pausing playback and blanking in %1 min.",
                                Math.ceil(root.secsLeft / 60))
                        : i18n("On, with no cutoff armed.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    Layout.fillWidth: true
                    enabled: root.nwActive
                    icon.name: "chronometer"
                    text: i18n("+30 min")
                    // extends the existing deadline, so taps accumulate
                    onClicked: { sh.run("extend 30m"); soon.restart() }
                }
                QQC2.Button {
                    Layout.fillWidth: true
                    icon.name: "system-shutdown"
                    text: i18n("Sleep now")
                    onClicked: { sh.run("now"); root.expanded = false }
                }
            }
        }
    }
}
