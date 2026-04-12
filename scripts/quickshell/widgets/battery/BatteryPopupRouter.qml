import QtQuick
import Quickshell
import Quickshell.Io

Item {
    property int batCapacity: 0
    property string batStatus: "Unknown"
    readonly property bool noBatteryHardware: batCapacity === 0 && batStatus.toLowerCase() === "unknown"

    Process {
        id: batteryStatePoller
        command: ["bash", "-c", "percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1); echo \"${percent:-0}\"; status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1); echo \"${status:-Unknown}\";"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 2) {
                    batCapacity = parseInt(lines[0]) || 0;
                    batStatus = lines[1] || "Unknown";
                }
            }
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryStatePoller.running = true
    }

    Loader {
        anchors.fill: parent
        source: noBatteryHardware ? "BatteryPopupAlt.qml" : "BatteryPopup.qml"
    }
}
