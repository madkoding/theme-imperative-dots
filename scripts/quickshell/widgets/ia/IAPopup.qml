import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    MatugenColors { id: _theme }

    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green
    readonly property color mauve: _theme.mauve
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    property bool opencodeEnabled: false
    property bool ollamaEnabled: false
    property bool openclawEnabled: false
    property real vramGiB: 0.0
    property var ollamaCandidates: []
    property string selectedOllamaModel: ""

    function modelsForVram(vram) {
        if (vram >= 24) return ["qwen2.5:14b", "llama3.1:8b", "gemma2:9b", "phi4:14b"];
        if (vram >= 16) return ["llama3.1:8b", "qwen2.5:7b", "mistral:7b", "gemma2:9b"];
        if (vram >= 12) return ["qwen2.5:7b", "llama3.2:3b", "mistral:7b", "phi3.5:3.8b"];
        if (vram >= 8) return ["llama3.2:3b", "qwen2.5:3b", "phi3:mini", "gemma2:2b"];
        if (vram >= 6) return ["qwen2.5:1.5b", "llama3.2:1b", "gemma2:2b", "phi3:mini"];
        return ["llama3.2:1b", "qwen2.5:0.5b", "tinyllama:1.1b", "gemma2:2b"];
    }

    function refreshCandidates() {
        let next = modelsForVram(vramGiB);
        ollamaCandidates = next;
        if (next.length > 0 && (selectedOllamaModel === "" || next.indexOf(selectedOllamaModel) === -1)) {
            selectedOllamaModel = next[0];
        }
    }

    function refreshStatus() {
        statusProc.running = true;
    }

    function toggleOpenCode(enabled) {
        if (enabled) {
            Quickshell.execDetached(["bash", "-lc", "nohup opencode serve --hostname 0.0.0.0 >/tmp/opencode-serve.log 2>&1 &"]);
        } else {
            Quickshell.execDetached(["bash", "-lc", "pkill -f 'opencode serve --hostname 0.0.0.0' >/dev/null 2>&1 || true"]);
        }
        statusFastRefresh.start();
    }

    function toggleOllama(enabled) {
        if (enabled) {
            let model = selectedOllamaModel;
            Quickshell.execDetached(["bash", "-lc", "mkdir -p ~/.cache && printf '%s' '" + model + "' > ~/.cache/qs_ollama_model && nohup ollama serve >/tmp/ollama-serve.log 2>&1 & nohup ollama pull '" + model + "' >/tmp/ollama-pull.log 2>&1 &"]);
        } else {
            Quickshell.execDetached(["bash", "-lc", "pkill -f 'ollama serve' >/dev/null 2>&1 || true"]);
        }
        statusFastRefresh.start();
    }

    function toggleOpenClaw(enabled) {
        if (enabled) {
            Quickshell.execDetached(["bash", "-lc", "systemctl --user start openclaw.service >/dev/null 2>&1 || nohup openclaw serve --host 0.0.0.0 >/tmp/openclaw-serve.log 2>&1 &"]);
        } else {
            Quickshell.execDetached(["bash", "-lc", "systemctl --user stop openclaw.service >/dev/null 2>&1 || pkill -f 'openclaw serve' >/dev/null 2>&1 || true"]);
        }
        statusFastRefresh.start();
    }

    Component.onCompleted: {
        vramProc.running = true;
        refreshStatus();
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: refreshStatus()
    }

    Timer {
        id: statusFastRefresh
        interval: 350
        repeat: false
        onTriggered: refreshStatus()
    }

    Process {
        id: vramProc
        command: ["bash", "-lc", "vram_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1); if [ -z \"$vram_mib\" ]; then echo 0; else awk \"BEGIN { printf \\\"%.1f\\\", $vram_mib/1024 }\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let value = parseFloat(this.text.trim());
                if (!isNaN(value)) root.vramGiB = value;
                root.refreshCandidates();
            }
        }
    }

    Process {
        id: statusProc
        command: ["bash", "-lc", "op=0; ol=0; oc=0; pgrep -f 'opencode serve --hostname 0.0.0.0' >/dev/null && op=1; pgrep -f 'ollama serve' >/dev/null && ol=1; (systemctl --user is-active --quiet openclaw.service || pgrep -f 'openclaw serve' >/dev/null) && oc=1; printf 'op=%s\\nol=%s\\noc=%s\\n' \"$op\" \"$ol\" \"$oc\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                root.opencodeEnabled = out.indexOf("op=1") !== -1;
                root.ollamaEnabled = out.indexOf("ol=1") !== -1;
                root.openclawEnabled = out.indexOf("oc=1") !== -1;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.9)
        border.width: 1
        border.color: root.surface1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 44
                    height: 44
                    radius: 12
                    color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.2)
                    border.width: 1
                    border.color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: "󰚩"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: 22
                        color: root.mauve
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "IA Services"
                        font.family: "Michroma"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: root.text
                    }
                    Text {
                        text: "VRAM detectada: " + root.vramGiB.toFixed(1) + " GiB"
                        font.family: "Michroma"
                        font.pixelSize: 11
                        color: root.subtext0
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.6)
                    border.width: 1
                    border.color: root.surface2
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: 16
                        color: root.subtext0
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"])
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.5) }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 14

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 98
                        radius: 12
                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.5)
                        border.width: 1
                        border.color: root.surface1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "OpenCode"; font.family: "Michroma"; font.pixelSize: 14; font.weight: Font.Bold; color: root.text }
                                Text { text: "opencode serve --hostname 0.0.0.0"; font.family: "Iosevka Nerd Font"; font.pixelSize: 11; color: root.subtext0 }
                            }

                            Switch {
                                checked: root.opencodeEnabled
                                onToggled: root.toggleOpenCode(checked)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 165
                        radius: 12
                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.5)
                        border.width: 1
                        border.color: root.surface1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Ollama local"; font.family: "Michroma"; font.pixelSize: 14; font.weight: Font.Bold; color: root.text }
                                Item { Layout.fillWidth: true }
                                Switch {
                                    checked: root.ollamaEnabled
                                    onToggled: root.toggleOllama(checked)
                                }
                            }

                            Text {
                                text: "Modelos sugeridos segun VRAM"
                                font.family: "Michroma"
                                font.pixelSize: 11
                                color: root.subtext0
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                model: root.ollamaCandidates
                                currentIndex: Math.max(0, root.ollamaCandidates.indexOf(root.selectedOllamaModel))
                                onActivated: root.selectedOllamaModel = currentText
                            }

                            Text {
                                text: root.selectedOllamaModel === "" ? "" : ("Modelo seleccionado: " + root.selectedOllamaModel)
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: 11
                                color: root.yellow
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 98
                        radius: 12
                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.5)
                        border.width: 1
                        border.color: root.surface1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "OpenClaw"; font.family: "Michroma"; font.pixelSize: 14; font.weight: Font.Bold; color: root.text }
                                Text { text: "Activa openclaw.service o openclaw serve"; font.family: "Michroma"; font.pixelSize: 11; color: root.subtext0 }
                            }

                            Switch {
                                checked: root.openclawEnabled
                                onToggled: root.toggleOpenClaw(checked)
                            }
                        }
                    }
                }
            }
        }
    }
}
