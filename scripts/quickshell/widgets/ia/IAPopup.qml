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
    readonly property int compactInputHeight: 30

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

    property bool _suspendSwitchHandlers: false

    function sanitizePort(value, fallbackPort) {
        let p = parseInt(value);
        if (isNaN(p) || p < 1 || p > 65535) {
            return fallbackPort;
        }
        return p;
    }

    function stateColor(state) {
        if (state === "running") return root.green;
        if (state === "starting") return root.yellow;
        return root.red;
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

    function cardBackground(state, service) {
        let c = serviceAccent(service);
        if (state === "running") return Qt.rgba(c.r, c.g, c.b, 0.14);
        if (state === "starting") return Qt.rgba(root.yellow.r, root.yellow.g, root.yellow.b, 0.10);
        if (state === "failed") return Qt.rgba(root.red.r, root.red.g, root.red.b, 0.10);
        return Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.52);
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
        radius: 18
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.92)
        border.width: 1
        border.color: root.surface1

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
            width: 220
            height: 220
            radius: 110
            x: -80
            y: -120
            color: Qt.rgba(root.sapphire.r, root.sapphire.g, root.sapphire.b, 0.10)
        }

        Rectangle {
            width: 200
            height: 200
            radius: 100
            x: parent.width - 120
            y: -90
            color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.08)
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
                    font.pixelSize: 22
                    color: root.mauve
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "IA Services"
                        font.family: "Michroma"
                        font.pixelSize: 16
                        font.weight: Font.Black
                        color: root.text
                    }
                    Text {
                        text: root.vramDetected
                              ? ("VRAM: " + root.vramGiB.toFixed(1) + " GiB (" + root.vramSource + ")")
                              : "VRAM: N/A"
                        font.family: "Michroma"
                        font.pixelSize: 10
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
                        font.pixelSize: 9
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(root.surface2.r, root.surface2.g, root.surface2.b, 0.5)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.55)
                    border.width: 1
                    border.color: root.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text { text: "󰆦"; font.family: "Iosevka Nerd Font"; font.pixelSize: 14; color: root.sapphire }
                        Text { text: "Detected VRAM"; font.family: "Michroma"; font.pixelSize: 10; color: root.subtext0 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.vramDetected ? (root.vramGiB.toFixed(1) + " GiB") : "N/A"; font.family: "Michroma"; font.pixelSize: 12; color: root.text }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.55)
                    border.width: 1
                    border.color: root.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text { text: "󱐋"; font.family: "Iosevka Nerd Font"; font.pixelSize: 14; color: root.green }
                        Text { text: "Profiles"; font.family: "Michroma"; font.pixelSize: 10; color: root.subtext0 }
                        Item { Layout.fillWidth: true }
                        Text { text: String(root.ollamaCandidates.length) + " models"; font.family: "Michroma"; font.pixelSize: 12; color: root.text }
                    }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Item {
                    id: scrollContent
                    width: (parent && parent.width > 0) ? Math.max(0, parent.width - 8) : (root.width - 48)
                    implicitHeight: cardsGrid.implicitHeight + 8

                    Grid {
                        id: cardsGrid
                        x: 4
                        width: Math.max(0, parent.width - 8)
                        columns: 2
                        spacing: 14

                        Rectangle {
                            id: opencodeCard
                            width: Math.floor((cardsGrid.width - cardsGrid.spacing) / 2)
                            implicitHeight: opencodeCardContent.implicitHeight + 28
                            clip: true
                            radius: 14
                            color: root.cardBackground(root.opencodeState, "opencode")
                            border.width: 1
                            border.color: root.cardBorder(root.opencodeState, "opencode")

                            ColumnLayout {
                                id: opencodeCardContent
                                width: parent.width - 34
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: "OpenCode"; font.family: "Michroma"; font.pixelSize: 15; font.weight: Font.Black; color: root.text }
                                        Text { text: "opencode serve --hostname <host> --port <port>"; font.family: "Iosevka Nerd Font"; font.pixelSize: 11; color: Qt.lighter(root.subtext0, 1.2) }
                                    }

                                    Item { Layout.fillWidth: true }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        Layout.preferredWidth: 132
                                        Layout.fillWidth: false
                                        spacing: 8
                                        Text { text: root.statusDotText(root.opencodeState); font.family: "Iosevka Nerd Font"; font.pixelSize: 13; color: root.stateColor(root.opencodeState) }
                                        Text { text: root.shortStateLabel(root.opencodeState, root.opencodeAvailable); font.family: "Michroma"; font.pixelSize: 10; color: root.text }
                                        Switch {
                                            checked: root.opencodeSwitch
                                            enabled: root.serviceSwitchEnabled(root.opencodeAvailable, root.opencodeState) && root.serviceManaged("opencode")
                                            onToggled: {
                                                if (root._suspendSwitchHandlers) return;
                                                if (checked) root.startService("opencode"); else root.stopService("opencode");
                                            }
                                        }
                                    }
                                }

                                GridLayout {
                                    id: opencodeGrid
                                    columns: 1
                                    columnSpacing: 8
                                    rowSpacing: 8
                                    Layout.fillWidth: true

                                    TextField {
                                        Layout.fillWidth: true
                                        implicitHeight: root.compactInputHeight
                                        font.family: "Michroma"
                                        font.pixelSize: 11
                                        placeholderText: "Host"
                                        text: cfg.opencodeHost
                                        color: root.text
                                        placeholderTextColor: root.subtext0
                                        leftPadding: 8
                                        rightPadding: 8
                                        background: Rectangle {
                                            radius: 8
                                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                            border.width: 1
                                            border.color: root.surface2
                                        }
                                        onEditingFinished: cfg.opencodeHost = text.trim() === "" ? "0.0.0.0" : text.trim()
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        implicitHeight: root.compactInputHeight
                                        font.family: "Michroma"
                                        font.pixelSize: 11
                                        placeholderText: "Port"
                                        text: String(cfg.opencodePort)
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        color: root.text
                                        placeholderTextColor: root.subtext0
                                        leftPadding: 8
                                        rightPadding: 8
                                        background: Rectangle {
                                            radius: 8
                                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                            border.width: 1
                                            border.color: root.surface2
                                        }
                                        onEditingFinished: cfg.opencodePort = root.sanitizePort(text, 4096)
                                    }
                                }

                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    placeholderText: "Extra args (optional)"
                                    text: cfg.opencodeArgs
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    leftPadding: 8
                                    rightPadding: 8
                                    background: Rectangle {
                                        radius: 8
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                        border.width: 1
                                        border.color: root.surface2
                                    }
                                    onEditingFinished: cfg.opencodeArgs = text
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: !root.serviceManaged("opencode")
                                          ? "Managed by another user/session (not controllable here)."
                                          : root.opencodeMessage
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    color: root.text
                                    visible: !root.serviceManaged("opencode") || root.opencodeState === "failed" || root.opencodeState === "starting"
                                }
                            }
                        }

                        Rectangle {
                            id: ollamaCard
                            width: Math.floor((cardsGrid.width - cardsGrid.spacing) / 2)
                            implicitHeight: ollamaCardContent.implicitHeight + 28
                            clip: true
                            radius: 14
                            color: root.cardBackground(root.ollamaState, "ollama")
                            border.width: 1
                            border.color: root.cardBorder(root.ollamaState, "ollama")

                            ColumnLayout {
                                id: ollamaCardContent
                                width: parent.width - 34
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: "Ollama"; font.family: "Michroma"; font.pixelSize: 15; font.weight: Font.Black; color: root.text }
                                        Text { text: "Model selection adapts to detected VRAM"; font.family: "Michroma"; font.pixelSize: 11; color: Qt.lighter(root.subtext0, 1.2) }
                                    }

                                    Item { Layout.fillWidth: true }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        Layout.preferredWidth: 132
                                        Layout.fillWidth: false
                                        spacing: 8
                                        Text { text: root.statusDotText(root.ollamaState); font.family: "Iosevka Nerd Font"; font.pixelSize: 13; color: root.stateColor(root.ollamaState) }
                                        Text { text: root.shortStateLabel(root.ollamaState, root.ollamaAvailable); font.family: "Michroma"; font.pixelSize: 10; color: root.text }
                                        Switch {
                                            checked: root.ollamaSwitch
                                            enabled: root.serviceSwitchEnabled(root.ollamaAvailable, root.ollamaState) && root.serviceManaged("ollama")
                                            onToggled: {
                                                if (root._suspendSwitchHandlers) return;
                                                if (checked) root.startService("ollama"); else root.stopService("ollama");
                                            }
                                        }
                                    }
                                }

                                GridLayout {
                                    id: ollamaGrid
                                    columns: 1
                                    columnSpacing: 8
                                    rowSpacing: 8
                                    Layout.fillWidth: true

                                    TextField {
                                        Layout.fillWidth: true
                                        implicitHeight: root.compactInputHeight
                                        font.family: "Michroma"
                                        font.pixelSize: 11
                                        placeholderText: "Host"
                                        text: cfg.ollamaHost
                                        color: root.text
                                        placeholderTextColor: root.subtext0
                                        leftPadding: 8
                                        rightPadding: 8
                                        background: Rectangle {
                                            radius: 8
                                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                            border.width: 1
                                            border.color: root.surface2
                                        }
                                        onEditingFinished: cfg.ollamaHost = text.trim() === "" ? "127.0.0.1" : text.trim()
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        implicitHeight: root.compactInputHeight
                                        font.family: "Michroma"
                                        font.pixelSize: 11
                                        placeholderText: "Port"
                                        text: String(cfg.ollamaPort)
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        color: root.text
                                        placeholderTextColor: root.subtext0
                                        leftPadding: 8
                                        rightPadding: 8
                                        background: Rectangle {
                                            radius: 8
                                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                            border.width: 1
                                            border.color: root.surface2
                                        }
                                        onEditingFinished: cfg.ollamaPort = root.sanitizePort(text, 11434)
                                    }
                                }

                                ComboBox {
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    model: root.ollamaCandidates
                                    currentIndex: Math.max(0, root.ollamaCandidates.indexOf(cfg.ollamaModel))
                                    background: Rectangle {
                                        radius: 8
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                        border.width: 1
                                        border.color: root.surface2
                                    }
                                    onActivated: cfg.ollamaModel = currentText
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    CheckBox {
                                        checked: cfg.ollamaAutoPull
                                        onToggled: cfg.ollamaAutoPull = checked
                                    }
                                    Text {
                                        text: "Auto pull model when enabling"
                                        font.family: "Michroma"
                                        font.pixelSize: 11
                                        color: root.text
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: !root.serviceManaged("ollama")
                                          ? "Managed by another user/session (not controllable here)."
                                          : root.ollamaMessage
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    color: root.text
                                    visible: !root.serviceManaged("ollama") || root.ollamaState === "failed" || root.ollamaState === "starting"
                                }
                            }
                        }

                        Rectangle {
                            id: openclawCard
                            width: Math.floor((cardsGrid.width - cardsGrid.spacing) / 2)
                            implicitHeight: openclawCardContent.implicitHeight + 28
                            clip: true
                            radius: 14
                            color: root.cardBackground(root.openclawState, "openclaw")
                            border.width: 1
                            border.color: root.cardBorder(root.openclawState, "openclaw")

                            ColumnLayout {
                                id: openclawCardContent
                                width: parent.width - 34
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: "OpenClaw"; font.family: "Michroma"; font.pixelSize: 15; font.weight: Font.Black; color: root.text }
                                        Text { text: "Manual command mode"; font.family: "Michroma"; font.pixelSize: 11; color: Qt.lighter(root.subtext0, 1.2) }
                                    }

                                    Item { Layout.fillWidth: true }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        Layout.preferredWidth: 132
                                        Layout.fillWidth: false
                                        spacing: 8
                                        Text { text: root.statusDotText(root.openclawState); font.family: "Iosevka Nerd Font"; font.pixelSize: 13; color: root.stateColor(root.openclawState) }
                                        Text { text: root.shortStateLabel(root.openclawState, root.openclawAvailable); font.family: "Michroma"; font.pixelSize: 10; color: root.text }
                                        Switch {
                                            checked: root.openclawSwitch
                                            enabled: root.serviceSwitchEnabled(root.openclawAvailable, root.openclawState) && root.serviceManaged("openclaw")
                                            onToggled: {
                                                if (root._suspendSwitchHandlers) return;
                                                if (checked) root.startService("openclaw"); else root.stopService("openclaw");
                                            }
                                        }
                                    }
                                }

                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    placeholderText: "Start command"
                                    text: cfg.openclawStartCmd
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    leftPadding: 8
                                    rightPadding: 8
                                    background: Rectangle {
                                        radius: 8
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                        border.width: 1
                                        border.color: root.surface2
                                    }
                                    onEditingFinished: cfg.openclawStartCmd = text.trim() === "" ? "openclaw gateway --port 18789" : text
                                }

                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    placeholderText: "Process match regex"
                                    text: cfg.openclawMatch
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    leftPadding: 8
                                    rightPadding: 8
                                    background: Rectangle {
                                        radius: 8
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                        border.width: 1
                                        border.color: root.surface2
                                    }
                                    onEditingFinished: cfg.openclawMatch = text.trim() === "" ? "openclaw.*gateway" : text
                                }

                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: root.compactInputHeight
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    placeholderText: "Stop command (optional)"
                                    text: cfg.openclawStopCmd
                                    color: root.text
                                    placeholderTextColor: root.subtext0
                                    leftPadding: 8
                                    rightPadding: 8
                                    background: Rectangle {
                                        radius: 8
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.82)
                                        border.width: 1
                                        border.color: root.surface2
                                    }
                                    onEditingFinished: cfg.openclawStopCmd = text
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: !root.serviceManaged("openclaw")
                                          ? "Managed by another user/session (not controllable here)."
                                          : root.openclawMessage
                                    font.family: "Michroma"
                                    font.pixelSize: 11
                                    color: root.text
                                    visible: !root.serviceManaged("openclaw") || root.openclawState === "failed" || root.openclawState === "starting"
                                }
                            }
                        }

                    }
                }
            }
        }
    }
}
