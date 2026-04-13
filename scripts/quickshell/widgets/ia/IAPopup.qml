import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    MatugenColors { id: _theme }

    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red
    readonly property color mauve: _theme.mauve
    readonly property color peach: _theme.peach
    readonly property color sapphire: _theme.sapphire
    readonly property color stateOnGreen: "#45d483"
    readonly property color stateWarnYellow: "#f4bf4f"
    readonly property color stateOffRed: "#f05f6b"
    readonly property int compactInputHeight: 42
    readonly property real uiTextScale: 1.38

    readonly property string helperScript: Quickshell.env("HOME") + "/.config/quickshell/widgets/ia/ia_services.sh"

    Settings {
        id: cfg

        property string opencodeHost: "0.0.0.0"
        property int opencodePort: 4096
        property string opencodeArgs: ""

        property string ollamaHost: "127.0.0.1"
        property int ollamaPort: 11434
        property string ollamaModel: "llama3.2:1b"
        property bool ollamaAutoPull: true

        property string openclawStartCmd: "openclaw gateway --port 18789"
        property string openclawMatch: "openclaw.*gateway"
        property string openclawStopCmd: ""
    }

    property bool vramDetected: false
    property real vramGiB: 0.0
    property string vramSource: "none"

    property var ollamaCandidates: ["llama3.2:1b"]

    property string opencodeState: "off"   // off | starting | running | failed
    property string ollamaState: "off"
    property string openclawState: "off"

    property string opencodeMessage: ""
    property string ollamaMessage: ""
    property string openclawMessage: ""

    property bool opencodeSwitch: false
    property bool ollamaSwitch: false
    property bool openclawSwitch: false

    property bool opencodeAvailable: false
    property bool ollamaAvailable: false
    property bool openclawAvailable: true
    property bool opencodeForeign: false
    property bool ollamaForeign: false
    property bool openclawForeign: false
    property string selectedService: ""
    property bool servicePopupOpen: false

    property bool _suspendSwitchHandlers: false
    property real globalOrbitAngle: 0

    readonly property int runningServicesCount: (opencodeState === "running" ? 1 : 0)
                                             + (ollamaState === "running" ? 1 : 0)
                                             + (openclawState === "running" ? 1 : 0)
    readonly property color aiAccent: runningServicesCount > 0 ? root.mauve : root.surface2
    readonly property color aiGradientSecondary: Qt.darker(aiAccent, 1.25)
    readonly property color radarDanger: root.stateWarnYellow

    component DarkFieldBg: Rectangle {
        radius: 10
        color: Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.88)
        border.width: 1
        border.color: root.surface1
    }

    NumberAnimation on globalOrbitAngle {
        from: 0
        to: Math.PI * 2
        duration: 200000
        loops: Animation.Infinite
        running: true
    }

    function sanitizePort(value, fallbackPort) {
        let p = parseInt(value);
        if (isNaN(p) || p < 1 || p > 65535) {
            return fallbackPort;
        }
        return p;
    }

    function stateColor(state, available, managed) {
        if (state === "running") return root.stateOnGreen;
        if (state === "starting" || state === "failed") return root.stateWarnYellow;
        if (!managed) return root.stateWarnYellow;
        return root.stateOffRed;
    }

    function stateLabel(state, available) {
        if (!available) return "Not installed";
        if (state === "running") return "Running";
        if (state === "starting") return "Starting";
        if (state === "failed") return "Failed";
        return "Stopped";
    }

    function statusDotText(state) {
        if (state === "starting") return "󱎴";
        return "";
    }

    function shortStateLabel(state, available) {
        if (!available) return "N/A";
        if (state === "running") return "On";
        if (state === "starting") return "...";
        if (state === "failed") return "Err";
        return "Off";
    }

    function serviceSwitchEnabled(available, state) {
        return available && state !== "starting";
    }

    function serviceManaged(service) {
        if (service === "opencode") return !root.opencodeForeign;
        if (service === "ollama") return !root.ollamaForeign;
        if (service === "openclaw") return !root.openclawForeign;
        return true;
    }

    function serviceAccent(service) {
        if (service === "opencode") return root.mauve;
        if (service === "ollama") return root.blue;
        return root.peach;
    }

    function serviceState(service) {
        if (service === "opencode") return root.opencodeState;
        if (service === "ollama") return root.ollamaState;
        return root.openclawState;
    }

    function serviceAvailable(service) {
        if (service === "opencode") return root.opencodeAvailable;
        if (service === "ollama") return root.ollamaAvailable;
        return root.openclawAvailable;
    }

    function serviceMessage(service) {
        if (service === "opencode") return root.opencodeMessage;
        if (service === "ollama") return root.ollamaMessage;
        return root.openclawMessage;
    }

    function serviceTitle(service) {
        if (service === "opencode") return "OpenCode";
        if (service === "ollama") return "Ollama";
        return "OpenClaw";
    }

    function serviceIcon(service) {
        if (service === "opencode") return "󰍹";
        if (service === "ollama") return "󰳆";
        return "🦞";
    }

    function openServicePopup(service) {
        selectedService = service;
        servicePopupOpen = true;
    }

    function closeServicePopup() {
        servicePopupOpen = false;
        selectedService = "";
    }

    function cardBackground(state, service) {
        let c = serviceAccent(service);
        if (state === "running") return Qt.rgba(c.r, c.g, c.b, 0.11);
        if (state === "starting") return Qt.rgba(root.yellow.r, root.yellow.g, root.yellow.b, 0.10);
        if (state === "failed") return Qt.rgba(root.red.r, root.red.g, root.red.b, 0.10);
        return Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.58);
    }

    function cardBorder(state, service) {
        if (state === "running") return Qt.lighter(serviceAccent(service), 1.05);
        if (state === "starting") return root.yellow;
        if (state === "failed") return root.red;
        return root.surface1;
    }

    function serviceHealthSummary() {
        let running = 0;
        if (root.opencodeState === "running") running += 1;
        if (root.ollamaState === "running") running += 1;
        if (root.openclawState === "running") running += 1;
        return String(running) + "/3 online";
    }

    function setSwitchByState(service, state) {
        let target = state === "running" || state === "starting";
        root._suspendSwitchHandlers = true;
        if (service === "opencode") root.opencodeSwitch = target;
        if (service === "ollama") root.ollamaSwitch = target;
        if (service === "openclaw") root.openclawSwitch = target;
        root._suspendSwitchHandlers = false;
    }

    function setState(service, state, message) {
        if (service === "opencode") {
            root.opencodeState = state;
            if (message !== undefined) root.opencodeMessage = message;
        }
        if (service === "ollama") {
            root.ollamaState = state;
            if (message !== undefined) root.ollamaMessage = message;
        }
        if (service === "openclaw") {
            root.openclawState = state;
            if (message !== undefined) root.openclawMessage = message;
        }
        root.setSwitchByState(service, state);
    }

    function statePriority(state) {
        if (state === "failed") return 3;
        if (state === "starting") return 2;
        if (state === "running") return 1;
        return 0;
    }

    function maybeSetPassiveState(service, state, message) {
        let current = "off";
        if (service === "opencode") current = root.opencodeState;
        if (service === "ollama") current = root.ollamaState;
        if (service === "openclaw") current = root.openclawState;
        if (root.statePriority(current) > root.statePriority(state)) return;
        root.setState(service, state, message);
    }

    function validateConfig() {
        cfg.opencodePort = sanitizePort(cfg.opencodePort, 4096);
        cfg.ollamaPort = sanitizePort(cfg.ollamaPort, 11434);

        if (!cfg.opencodeHost || cfg.opencodeHost.trim() === "") cfg.opencodeHost = "0.0.0.0";
        if (!cfg.ollamaHost || cfg.ollamaHost.trim() === "") cfg.ollamaHost = "127.0.0.1";
        if (!cfg.openclawStartCmd || cfg.openclawStartCmd.trim() === "") cfg.openclawStartCmd = "openclaw gateway --port 18789";
        if (!cfg.openclawMatch || cfg.openclawMatch.trim() === "") cfg.openclawMatch = "openclaw.*gateway";
    }

    function refreshAll() {
        validateConfig();
        root.opencodeMessage = "Checking service status...";
        root.ollamaMessage = "Checking service status...";
        root.openclawMessage = "Checking service status...";
        vramProc.running = true;
        statusProc.running = true;
    }

    function parseResult(text) {
        let obj = null;
        try {
            obj = JSON.parse((text || "").trim());
        } catch (e) {
            obj = null;
        }
        return obj;
    }

    function startService(service) {
        if (service === "opencode") {
            if (!root.opencodeAvailable) {
                setState("opencode", "failed", "OpenCode binary not found");
                return;
            }
            setState("opencode", "starting", "Starting OpenCode...");
            opencodeAction.command = [
                "bash", root.helperScript,
                "opencode-start",
                cfg.opencodeHost,
                String(cfg.opencodePort),
                cfg.opencodeArgs
            ];
            opencodeAction.running = true;
            return;
        }

        if (service === "ollama") {
            if (!root.ollamaAvailable) {
                setState("ollama", "failed", "Ollama binary not found");
                return;
            }
            setState("ollama", "starting", "Starting Ollama...");
            let pullFlag = cfg.ollamaAutoPull ? "1" : "0";
            ollamaAction.command = [
                "bash", root.helperScript,
                "ollama-start",
                cfg.ollamaHost,
                String(cfg.ollamaPort),
                cfg.ollamaModel,
                pullFlag
            ];
            ollamaAction.running = true;
            return;
        }

        if (service === "openclaw") {
            setState("openclaw", "starting", "Starting OpenClaw...");
            openclawAction.command = [
                "bash", root.helperScript,
                "openclaw-start",
                cfg.openclawStartCmd,
                cfg.openclawMatch
            ];
            openclawAction.running = true;
        }
    }

    function stopService(service) {
        if (service === "opencode") {
            setState("opencode", "starting", "Stopping OpenCode...");
            opencodeAction.command = [
                "bash", root.helperScript,
                "opencode-stop",
                cfg.opencodeHost,
                String(cfg.opencodePort)
            ];
            opencodeAction.running = true;
            return;
        }

        if (service === "ollama") {
            setState("ollama", "starting", "Stopping Ollama...");
            ollamaAction.command = [
                "bash", root.helperScript,
                "ollama-stop",
                cfg.ollamaHost,
                String(cfg.ollamaPort)
            ];
            ollamaAction.running = true;
            return;
        }

        if (service === "openclaw") {
            setState("openclaw", "starting", "Stopping OpenClaw...");
            openclawAction.command = [
                "bash", root.helperScript,
                "openclaw-stop",
                cfg.openclawMatch,
                cfg.openclawStopCmd
            ];
            openclawAction.running = true;
        }
    }

    Component.onCompleted: refreshAll()

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: statusProc.running = true
    }

    Timer {
        id: settleRefresh
        interval: 600
        repeat: false
        onTriggered: statusProc.running = true
    }

    Process {
        id: vramProc
        command: ["bash", root.helperScript, "detect-vram"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = root.parseResult(this.text);
                if (!v) return;
                root.vramDetected = !!v.detected;
                root.vramGiB = Number(v.gib || 0);
                root.vramSource = String(v.source || "none");

                ollamaModelsProc.command = ["bash", root.helperScript, "ollama-models", root.vramGiB.toFixed(1)];
                ollamaModelsProc.running = true;
            }
        }
    }

    Process {
        id: ollamaModelsProc
        command: ["bash", root.helperScript, "ollama-models", "0.0"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = root.parseResult(this.text);
                if (!data) return;
                if (Array.isArray(data.candidates) && data.candidates.length > 0) {
                    root.ollamaCandidates = data.candidates;
                    if (root.ollamaCandidates.indexOf(cfg.ollamaModel) === -1) {
                        cfg.ollamaModel = root.ollamaCandidates[0];
                    }
                }
            }
        }
    }

    Process {
        id: statusProc
        command: [
            "bash", root.helperScript,
            "status",
            cfg.opencodeHost,
            String(cfg.opencodePort),
            cfg.ollamaHost,
            String(cfg.ollamaPort),
            cfg.openclawMatch,
            cfg.openclawStartCmd
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = root.parseResult(this.text);
                if (!s) return;

                root.opencodeAvailable = !!(s.opencode && s.opencode.available);
                root.ollamaAvailable = !!(s.ollama && s.ollama.available);
                root.openclawAvailable = !!(s.openclaw && s.openclaw.available);
                root.opencodeForeign = !!(s.ownership && s.ownership.opencode_foreign);
                root.ollamaForeign = !!(s.ownership && s.ownership.ollama_foreign);
                root.openclawForeign = !!(s.ownership && s.ownership.openclaw_foreign);

                if (s.opencode && s.opencode.running) root.maybeSetPassiveState("opencode", "running", "OpenCode is running");
                else root.maybeSetPassiveState("opencode", "off", "OpenCode is stopped");

                if (s.ollama && s.ollama.running) root.maybeSetPassiveState("ollama", "running", "Ollama is running");
                else root.maybeSetPassiveState("ollama", "off", "Ollama is stopped");

                if (s.openclaw && s.openclaw.running) root.maybeSetPassiveState("openclaw", "running", "OpenClaw gateway is running");
                else root.maybeSetPassiveState("openclaw", "off", "OpenClaw gateway is stopped");

                if (!root.opencodeAvailable) root.setState("opencode", "failed", "OpenCode binary not found");
                if (!root.ollamaAvailable) root.setState("ollama", "failed", "Ollama binary not found");

                if (!root.openclawAvailable) {
                    root.setState("openclaw", "failed", "OpenClaw checker unavailable");
                }
            }
        }
    }

    Process {
        id: opencodeAction
        property string resultPayload: ""
        command: ["bash", "-lc", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                opencodeAction.resultPayload = this.text;
            }
        }
        onExited: {
            let r = root.parseResult(resultPayload);
            if (!r || !r.ok) {
                root.setState("opencode", "failed", r && r.message ? r.message : "OpenCode action failed");
            } else {
                root.setState("opencode", r.running ? "running" : "off", r.message || "OpenCode updated");
            }
            resultPayload = "";
            settleRefresh.restart();
        }
    }

    Process {
        id: ollamaAction
        property string resultPayload: ""
        command: ["bash", "-lc", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                ollamaAction.resultPayload = this.text;
            }
        }
        onExited: {
            let r = root.parseResult(resultPayload);
            if (!r || !r.ok) {
                root.setState("ollama", "failed", r && r.message ? r.message : "Ollama action failed");
            } else {
                root.setState("ollama", r.running ? "running" : "off", r.message || "Ollama updated");
            }
            resultPayload = "";
            settleRefresh.restart();
        }
    }

    Process {
        id: openclawAction
        property string resultPayload: ""
        command: ["bash", "-lc", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                openclawAction.resultPayload = this.text;
            }
        }
        onExited: {
            let r = root.parseResult(resultPayload);
            if (!r || !r.ok) {
                root.setState("openclaw", "failed", r && r.message ? r.message : "OpenClaw action failed");
            } else {
                root.setState("openclaw", r.running ? "running" : "off", r.message || "OpenClaw updated");
            }
            resultPayload = "";
            settleRefresh.restart();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.base
        border.width: 1
        border.color: root.surface0

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.06) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Rectangle {
            width: parent.width * 0.85
            height: width
            radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.cos(root.globalOrbitAngle * 2) * 140
            y: (parent.height / 2 - height / 2) + Math.sin(root.globalOrbitAngle * 2) * 90
            opacity: 0.08
            color: root.aiAccent
            Behavior on color { ColorAnimation { duration: 900 } }
        }

        Rectangle {
            width: parent.width * 0.95
            height: width
            radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.sin(root.globalOrbitAngle * 1.5) * -130
            y: (parent.height / 2 - height / 2) + Math.cos(root.globalOrbitAngle * 1.5) * -80
            opacity: 0.06
            color: root.aiGradientSecondary
            Behavior on color { ColorAnimation { duration: 900 } }
        }

        Item {
            id: radarBackdrop
            anchors.fill: parent
            anchors.bottomMargin: 60

            Repeater {
                model: 3
                Rectangle {
                    anchors.centerIn: parent
                    width: 260 + (index * 150)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.aiAccent.r, root.aiAccent.g, root.aiAccent.b, 0.35)
                    opacity: 0.07 - (index * 0.015)
                    Behavior on border.color { ColorAnimation { duration: 800 } }
                }
            }

            Rectangle {
                id: centerCoreGlow
                anchors.centerIn: parent
                width: 220
                height: 220
                radius: 110
                color: root.aiAccent
                opacity: 0.08
                scale: 1.0
                Behavior on color { ColorAnimation { duration: 800 } }

                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "󰚩"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: Math.round(22 * root.uiTextScale)
                    color: root.mauve
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "IA Services"
                        font.family: "Michroma"
                        font.pixelSize: Math.round(16 * root.uiTextScale)
                        font.weight: Font.Black
                        color: root.text
                    }
                    Text {
                        text: root.vramDetected
                              ? ("VRAM: " + root.vramGiB.toFixed(1) + " GiB (" + root.vramSource + ")")
                              : "VRAM: N/A"
                        font.family: "Michroma"
                        font.pixelSize: Math.round(10 * root.uiTextScale)
                        color: root.subtext0
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    radius: 10
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 120
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.72)
                    border.width: 1
                    border.color: root.surface2
                    Text {
                        anchors.centerIn: parent
                        text: root.serviceHealthSummary()
                        font.family: "Michroma"
                        font.pixelSize: Math.round(9 * root.uiTextScale)
                        font.weight: Font.Bold
                        color: root.subtext0
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)
                    border.width: 1
                    border.color: root.surface2
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: Math.round(16 * root.uiTextScale)
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.5)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 190

                Repeater {
                    model: 3
                    Rectangle {
                        anchors.centerIn: parent
                        width: 150 + (index * 95)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(root.aiAccent.r, root.aiAccent.g, root.aiAccent.b, 0.34)
                        opacity: 0.14 - (index * 0.03)
                    }
                }

                Rectangle {
                    id: aiCore
                    anchors.centerIn: parent
                    width: 122
                    height: 122
                    radius: 61
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.lighter(root.aiAccent, 1.2) }
                        GradientStop { position: 1.0; color: root.aiAccent }
                    }
                    border.width: 2
                    border.color: runningServicesCount > 0 ? Qt.lighter(root.aiAccent, 1.15) : root.surface2
                    opacity: 0.95

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.06; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰚩"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: Math.round(28 * root.uiTextScale)
                            color: root.base
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.serviceHealthSummary()
                            font.family: "Michroma"
                            font.pixelSize: Math.round(9 * root.uiTextScale)
                            font.weight: Font.Bold
                            color: root.base
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170
                    height: 36
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.65)
                    border.width: 1
                    border.color: root.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text { text: "󰆦"; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(14 * root.uiTextScale); color: root.sapphire }
                        Text { text: "VRAM"; font.family: "Michroma"; font.pixelSize: Math.round(10 * root.uiTextScale); color: root.subtext0 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.vramDetected ? (root.vramGiB.toFixed(1) + " GiB") : "N/A"; font.family: "Michroma"; font.pixelSize: Math.round(11 * root.uiTextScale); color: root.text }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170
                    height: 36
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.65)
                    border.width: 1
                    border.color: root.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text { text: "󱐋"; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(14 * root.uiTextScale); color: root.green }
                        Text { text: "Models"; font.family: "Michroma"; font.pixelSize: Math.round(10 * root.uiTextScale); color: root.subtext0 }
                        Item { Layout.fillWidth: true }
                        Text { text: String(root.ollamaCandidates.length); font.family: "Michroma"; font.pixelSize: Math.round(12 * root.uiTextScale); color: root.text }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                property var serviceNodes: [
                    { service: "opencode", label: "OpenCode", icon: "󰍹", angle: -1.57 },
                    { service: "ollama", label: "Ollama", icon: "󰳆", angle: 0.52 },
                    { service: "openclaw", label: "OpenClaw", icon: "🦞", angle: 2.62 }
                ]

                Repeater {
                    id: serviceNodesRepeater
                    model: parent.serviceNodes
                    delegate: Rectangle {
                        property string svc: modelData.service
                        property real orbitRadiusX: Math.max(130, parent.width * 0.30)
                        property real orbitRadiusY: Math.max(82, parent.height * 0.26)
                        property real orbitAngle: modelData.angle + root.globalOrbitAngle * 0.22
                        width: 112
                        height: 112
                        radius: width / 2
                        x: (parent.width / 2 - width / 2) + Math.cos(orbitAngle) * orbitRadiusX
                        y: (parent.height / 2 - height / 2) + Math.sin(orbitAngle) * orbitRadiusY
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.86) }
                            GradientStop { position: 1.0; color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.9) }
                        }
                        border.width: 2
                        border.color: root.stateColor(root.serviceState(svc), root.serviceAvailable(svc), root.serviceManaged(svc))
                        scale: nodeHover.containsMouse ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.round(24 * root.uiTextScale)
                                color: root.stateColor(root.serviceState(svc), root.serviceAvailable(svc), root.serviceManaged(svc))
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.family: "Michroma"
                                font.pixelSize: Math.round(8 * root.uiTextScale)
                                color: root.text
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.stateLabel(root.serviceState(svc), root.serviceAvailable(svc))
                                font.family: "Michroma"
                                font.pixelSize: Math.round(7 * root.uiTextScale)
                                color: root.subtext0
                            }
                        }

                        MouseArea {
                            id: nodeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openServicePopup(svc)
                        }
                    }
                }

                Canvas {
                    id: serviceLightningCanvas
                    anchors.fill: parent
                    anchors.topMargin: -220
                    z: 2
                    opacity: 0.9

                    Timer {
                        interval: 70
                        running: true
                        repeat: true
                        onTriggered: serviceLightningCanvas.requestPaint()
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        if (!aiCore)
                            return;

                        var center = aiCore.mapToItem(serviceLightningCanvas, aiCore.width / 2, aiCore.height / 2);
                        var time = Date.now() / 1000;

                        for (var i = 0; i < serviceNodesRepeater.count; i++) {
                            var node = serviceNodesRepeater.itemAt(i);
                            if (!node)
                                continue;

                            if (root.serviceState(node.svc) !== "running")
                                continue;

                            var nodeCenter = node.mapToItem(serviceLightningCanvas, node.width / 2, node.height / 2);
                            var dx = center.x - nodeCenter.x;
                            var dy = center.y - nodeCenter.y;
                            var dist = Math.sqrt(dx * dx + dy * dy);
                            if (dist < 8)
                                continue;

                            var alpha = Math.atan2(dy, dx);
                            var cosA = Math.cos(alpha);
                            var sinA = Math.sin(alpha);
                            var perpX = -sinA;
                            var perpY = cosA;

                            var nodeRadius = node.width / 2;
                            var startX = nodeCenter.x + cosA * nodeRadius;
                            var startY = nodeCenter.y + sinA * nodeRadius;
                            // Route connectors to the lower side of the online core
                            // so the lightning stays visually beneath the center circle.
                            var targetX = center.x;
                            var targetY = center.y + (aiCore.height * 0.58);

                            var linkDx = targetX - startX;
                            var linkDy = targetY - startY;
                            var linkDist = Math.sqrt(linkDx * linkDx + linkDy * linkDy);
                            if (linkDist <= 4)
                                continue;

                            var steps = 10;
                            var c = root.stateColor("running", true, true);
                            var waveA = time * 2.8 + i;
                            var waveB = time * -1.8 + i * 0.7;

                            function strokeStrand(widthCore, widthGlow, alphaCore, alphaGlow, ampMul, phase, colorCore, colorGlow) {
                                ctx.beginPath();
                                ctx.moveTo(startX, startY);
                                for (var s = 1; s <= steps; s++) {
                                    var t = s / steps;
                                    var px = startX + linkDx * t;
                                    var py = startY + linkDy * t;
                                    var envelope = Math.sin(Math.PI * t);
                                    var jitter = Math.sin(phase + t * 8.0) * (6.5 * ampMul) * envelope;
                                    ctx.lineTo(px + perpX * jitter, py + perpY * jitter);
                                }
                                ctx.lineWidth = widthGlow;
                                ctx.strokeStyle = colorGlow;
                                ctx.globalAlpha = alphaGlow;
                                ctx.stroke();

                                ctx.lineWidth = widthCore;
                                ctx.strokeStyle = colorCore;
                                ctx.globalAlpha = alphaCore;
                                ctx.stroke();
                            }

                            strokeStrand(1.3, 4.6, 0.82, 0.20, 1.0, waveA, "#ffffff", c);
                            strokeStrand(1.0, 3.4, 0.58, 0.14, 0.8, waveB, c, c);

                            ctx.beginPath();
                            ctx.arc(targetX, targetY, 2.6, 0, Math.PI * 2);
                            ctx.fillStyle = c;
                            ctx.globalAlpha = 0.9;
                            ctx.fill();
                            ctx.globalAlpha = 1.0;
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.44)
                    visible: root.servicePopupOpen
                    z: 10
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.closeServicePopup()
                    }
                }

                Rectangle {
                    id: servicePopup
                    visible: root.servicePopupOpen
                    z: 11
                    width: Math.min(parent.width - 30, 560)
                    height: Math.min(parent.height - 20, 420)
                    anchors.centerIn: parent
                    radius: 16
                    color: root.base
                    border.width: 1
                    border.color: root.surface1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: root.serviceIcon(root.selectedService)
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.round(22 * root.uiTextScale)
                                color: root.stateColor(root.serviceState(root.selectedService), root.serviceAvailable(root.selectedService), root.serviceManaged(root.selectedService))
                            }
                            Text {
                                text: root.serviceTitle(root.selectedService)
                                font.family: "Michroma"
                                font.pixelSize: Math.round(13 * root.uiTextScale)
                                font.weight: Font.Black
                                color: root.text
                            }
                            Item { Layout.fillWidth: true }
                            Switch {
                                visible: root.selectedService === "opencode"
                                checked: root.opencodeSwitch
                                enabled: root.serviceSwitchEnabled(root.opencodeAvailable, root.opencodeState) && root.serviceManaged("opencode")
                                onToggled: {
                                    if (root._suspendSwitchHandlers) return;
                                    if (checked) root.startService("opencode"); else root.stopService("opencode");
                                }
                            }
                            Switch {
                                visible: root.selectedService === "ollama"
                                checked: root.ollamaSwitch
                                enabled: root.serviceSwitchEnabled(root.ollamaAvailable, root.ollamaState) && root.serviceManaged("ollama")
                                onToggled: {
                                    if (root._suspendSwitchHandlers) return;
                                    if (checked) root.startService("ollama"); else root.stopService("ollama");
                                }
                            }
                            Switch {
                                visible: root.selectedService === "openclaw"
                                checked: root.openclawSwitch
                                enabled: root.serviceSwitchEnabled(root.openclawAvailable, root.openclawState) && root.serviceManaged("openclaw")
                                onToggled: {
                                    if (root._suspendSwitchHandlers) return;
                                    if (checked) root.startService("openclaw"); else root.stopService("openclaw");
                                }
                            }
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 8
                                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)
                                border.width: 1
                                border.color: root.surface2
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: Math.round(13 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeServicePopup()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.5)
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ColumnLayout {
                                width: servicePopup.width - 44
                                spacing: 8

                                Text {
                                    visible: root.selectedService === "opencode"
                                    text: "Host"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "opencode"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Host"
                                    text: cfg.opencodeHost
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.opencodeHost = text.trim() === "" ? "0.0.0.0" : text.trim()
                                }
                                Text {
                                    visible: root.selectedService === "opencode"
                                    text: "Port"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "opencode"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Port"
                                    text: String(cfg.opencodePort)
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.opencodePort = root.sanitizePort(text, 4096)
                                }
                                Text {
                                    visible: root.selectedService === "opencode"
                                    text: "Extra arguments"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "opencode"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Extra args"
                                    text: cfg.opencodeArgs
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.opencodeArgs = text
                                }

                                Text {
                                    visible: root.selectedService === "ollama"
                                    text: "Host"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "ollama"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Host"
                                    text: cfg.ollamaHost
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.ollamaHost = text.trim() === "" ? "127.0.0.1" : text.trim()
                                }
                                Text {
                                    visible: root.selectedService === "ollama"
                                    text: "Port"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "ollama"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Port"
                                    text: String(cfg.ollamaPort)
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.ollamaPort = root.sanitizePort(text, 11434)
                                }
                                ComboBox {
                                    id: ollamaModelCombo
                                    visible: root.selectedService === "ollama"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    model: root.ollamaCandidates
                                    currentIndex: Math.max(0, root.ollamaCandidates.indexOf(cfg.ollamaModel))
                                    background: DarkFieldBg {}
                                    contentItem: Text {
                                        text: ollamaModelCombo.currentText
                                        color: root.text
                                        font.family: "Michroma"
                                        font.pixelSize: Math.round(11 * root.uiTextScale)
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 10
                                        rightPadding: 10
                                    }
                                    popup: Popup {
                                        y: ollamaModelCombo.height + 2
                                        width: ollamaModelCombo.width
                                        padding: 4
                                        background: Rectangle {
                                            radius: 10
                                            color: Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.95)
                                            border.width: 1
                                            border.color: root.surface1
                                        }
                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: ollamaModelCombo.popup.visible ? ollamaModelCombo.delegateModel : null
                                            currentIndex: ollamaModelCombo.highlightedIndex
                                        }
                                    }
                                    delegate: ItemDelegate {
                                        width: ollamaModelCombo.width - 8
                                        contentItem: Text {
                                            text: modelData
                                            color: root.text
                                            font.family: "Michroma"
                                            font.pixelSize: Math.round(11 * root.uiTextScale)
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            radius: 8
                                            color: highlighted ? Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.9) : "transparent"
                                        }
                                    }
                                    onActivated: cfg.ollamaModel = currentText
                                }
                                Text {
                                    visible: root.selectedService === "ollama"
                                    text: "Model"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                CheckBox {
                                    visible: root.selectedService === "ollama"
                                    text: "Auto pull model when enabling"
                                    checked: cfg.ollamaAutoPull
                                    palette.text: root.text
                                    onToggled: cfg.ollamaAutoPull = checked
                                }
                                Text {
                                    visible: root.selectedService === "ollama"
                                    text: "Auto pull"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }

                                Text {
                                    visible: root.selectedService === "openclaw"
                                    text: "Start command"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "openclaw"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Start command"
                                    text: cfg.openclawStartCmd
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.openclawStartCmd = text.trim() === "" ? "openclaw gateway --port 18789" : text
                                }
                                Text {
                                    visible: root.selectedService === "openclaw"
                                    text: "Process match regex"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "openclaw"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Process match regex"
                                    text: cfg.openclawMatch
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.openclawMatch = text.trim() === "" ? "openclaw.*gateway" : text
                                }
                                Text {
                                    visible: root.selectedService === "openclaw"
                                    text: "Stop command"
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(10 * root.uiTextScale)
                                    color: root.subtext0
                                }
                                TextField {
                                    visible: root.selectedService === "openclaw"
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    placeholderText: "Stop command (optional)"
                                    text: cfg.openclawStopCmd
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    selectionColor: Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.45)
                                    selectedTextColor: root.text
                                    background: DarkFieldBg {}
                                    onEditingFinished: cfg.openclawStopCmd = text
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: root.selectedService === "" ? "" : (!root.serviceManaged(root.selectedService)
                                          ? "Managed by another user/session (not controllable here)."
                                          : root.serviceMessage(root.selectedService))
                                    font.family: "Michroma"
                                    font.pixelSize: Math.round(11 * root.uiTextScale)
                                    color: root.text
                                    visible: root.selectedService !== ""
                                }
                            }
                        }
                    }

                }
            }
        }
    }
}
