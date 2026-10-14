import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQml.Models

// One full-screen window per screen, over a snapshot of that screen that blurs in.
// Exit codes: 0 done, 1 start, 2 later, 3 skip (see RESULTS in pause.py).
QtObject {
    id: root

    required property string kind   // "eye" | "walk"
    required property int session   // walk 1 or 2
    required property int seconds   // eye break length, or walk setup time
    required property var week      // walked Mon..Fri this week

    readonly property bool eye: kind === "eye"
    readonly property bool ready: progress === 0  // walk: setup time is over
    readonly property int today: new Date().getDay() - 1
    property real shown: 0          // 0 → 1 drives blur, fade and rise
    property real progress: 1       // countdown, 1 → 0
    property real breath: 0
    property int code: 0

    function finish(c) {
        if (outro.running)
            return
        code = c
        countdown.stop()
        outro.start()
    }

    property var intro: NumberAnimation {
        target: root; property: "shown"; to: 1
        duration: 1000; easing.type: Easing.OutQuart; running: true
    }
    property var outro: SequentialAnimation {
        NumberAnimation { target: root; property: "shown"; to: 0; duration: 450; easing.type: Easing.InCubic }
        ScriptAction { script: Qt.exit(root.code) }
    }
    property var countdown: NumberAnimation {
        target: root; property: "progress"; from: 1; to: 0
        duration: root.seconds * 1000; running: true
        onFinished: if (root.eye) root.finish(0)
    }
    property var breathing: SequentialAnimation {
        running: true; loops: Animation.Infinite
        NumberAnimation { target: root; property: "breath"; to: 1; duration: 4000; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "breath"; to: 0; duration: 4000; easing.type: Easing.InOutSine }
    }

    component Pill: Rectangle {
        id: pill
        property string text
        property bool primary: false
        signal clicked
        implicitWidth: label.implicitWidth + 64
        implicitHeight: 54
        radius: height / 2
        color: primary ? Qt.rgba(1, 1, 1, area.containsMouse ? 1 : 0.92)
                       : Qt.rgba(1, 1, 1, area.containsMouse ? 0.26 : 0.18)
        border.width: primary ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        opacity: enabled ? 1 : 0.3
        scale: area.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Text {
            id: label
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? "#14171c" : "white"
            font { family: "Adwaita Sans"; pixelSize: 17; weight: Font.DemiBold }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    component Link: Text {
        id: link
        signal clicked
        color: "white"
        opacity: area.containsMouse ? 0.8 : 0.42
        font { family: "Adwaita Sans"; pixelSize: 14; weight: Font.Medium }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -10
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: link.clicked()
        }
    }

    property var windows: Instantiator {
        model: Qt.application.screens
        delegate: Window {
            id: win
            required property var modelData
            readonly property string screenName: modelData.name  // pause.py places and shows the window
            title: "Pause"
            color: "transparent"
            flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.finish(root.eye ? 3 : 2)
                Keys.onReturnPressed: if (!root.eye && root.ready) root.finish(1)

                // Backdrop: blurred snapshot, or a quiet gradient if the snapshot failed.
                Rectangle {
                    anchors.fill: parent
                    opacity: shot.status === Image.Ready ? 1 : root.shown
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#1d2735" }
                        GradientStop { position: 1; color: "#0b0e13" }
                    }
                }
                Image {
                    id: shot
                    anchors.fill: parent
                    source: "image://shot/" + win.modelData.name
                    visible: false
                    mipmap: true
                    cache: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: shot
                    visible: shot.status === Image.Ready
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 64
                    blur: root.shown
                    saturation: 0.3 * root.shown
                }
                Rectangle {
                    anchors.fill: parent
                    color: "#0a0d12"
                    opacity: 0.45 * root.shown
                }

                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 32 * (1 - root.shown)
                    opacity: root.shown
                    scale: 0.96 + 0.04 * root.shown
                    width: 560

                    // Orb: breathing halo, glass disc, countdown ring.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 230; height: 230
                        Rectangle {
                            anchors.centerIn: parent
                            width: 230; height: 230; radius: 115
                            color: "white"
                            opacity: 0.035 + 0.045 * root.breath
                            scale: 0.86 + 0.14 * root.breath
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 172; height: 172; radius: 86
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.color: Qt.rgba(1, 1, 1, 0.16)
                        }
                        Shape {
                            anchors.centerIn: parent
                            width: 172; height: 172
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: "white"
                                strokeWidth: 3
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 86; centerY: 86; radiusX: 84.5; radiusY: 84.5
                                    startAngle: -90; sweepAngle: 360 * root.progress
                                }
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.ready ? "✓" : Math.ceil(root.progress * root.seconds)
                                color: "white"
                                font { family: "Adwaita Sans"; pixelSize: 58; weight: Font.Light; features: { "tnum": 1 } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.eye ? "seconds" : root.ready ? "ready" : "seconds to set up"
                                color: "white"; opacity: 0.55
                                font { family: "Adwaita Sans"; pixelSize: 13; weight: Font.Medium }
                            }
                        }
                    }

                    Item { width: 1; height: 36 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.eye ? "EYE BREAK" : root.session === 2 ? "AFTERNOON WALK" : "MORNING WALK"
                        color: "white"; opacity: 0.55
                        font { family: "Adwaita Sans"; pixelSize: 13; weight: Font.DemiBold; letterSpacing: 2.2 }
                    }
                    Item { width: 1; height: 12 }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.eye ? "Look out the window" : "Time for a walk"
                        color: "white"
                        font { family: "Adwaita Sans"; pixelSize: 46; weight: Font.DemiBold; letterSpacing: -0.8 }
                    }
                    Item { width: 1; height: 14 }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        lineHeight: 1.3
                        text: root.eye ? "Find something far away and let your eyes rest on it."
                                       : "Setting up the pad takes " + root.seconds + " seconds.\nAfter that, you just keep working."
                        color: "white"; opacity: 0.72
                        font { family: "Adwaita Sans"; pixelSize: 19 }
                    }

                    // This week's walks, Mon–Fri.
                    Item { width: 1; height: 30; visible: !root.eye }
                    Row {
                        visible: !root.eye
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 20
                        Repeater {
                            model: ["M", "T", "W", "T", "F"]
                            Column {
                                required property string modelData
                                required property int index
                                spacing: 8
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 10; height: 10; radius: 5
                                    color: root.week[index] ? "white" : "transparent"
                                    border.width: 1.5
                                    border.color: Qt.rgba(1, 1, 1, root.week[index] ? 1 : 0.35)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData
                                    color: "white"
                                    opacity: index === root.today ? 0.95 : 0.4
                                    font { family: "Adwaita Sans"; pixelSize: 12; weight: Font.DemiBold }
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 40 }
                    Pill {
                        visible: root.eye
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Skip"
                        onClicked: root.finish(3)
                    }
                    Column {
                        visible: !root.eye
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12
                        Pill {
                            width: 300
                            primary: true
                            enabled: root.ready
                            text: "On the walking pad"
                            onClicked: root.finish(1)
                        }
                        Pill {
                            width: 300
                            text: "In 10 minutes"
                            onClicked: root.finish(2)
                        }
                        Item { width: 1; height: 4 }
                        Link {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Dismiss"
                            onClicked: root.finish(3)
                        }
                    }
                }
            }
        }
    }
}
