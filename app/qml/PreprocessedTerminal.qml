/*******************************************************************************
* Copyright (c) 2013-2021 "Filippo Scognamiglio"
* https://github.com/Swordfish90/cool-retro-term
*
* This file is part of cool-retro-term.
*
* cool-retro-term is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/

import QtQuick 2.2
import QtQuick.Controls 2.0

import QMLTermWidget 2.0

import "menus"
import "utils.js" as Utils

Item{
    id: terminalContainer
    signal sessionFinished()

    property size virtualResolution: Qt.size(kterminal.totalWidth, kterminal.totalHeight)
    property alias mainTerminal: kterminal

    property ShaderEffectSource mainSource: kterminalSource
    property BurnInEffect burnInEffect: burnInEffect
    property real fontWidth: 1.0
    property real screenScaling: 1.0
    property real scaleTexture: 1.0
    property alias title: ksession.title
    property alias kterminal: kterminal
    property bool isActive: false

    property size terminalSize: kterminal.terminalSize
    property size fontMetrics: kterminal.fontMetrics

    // Manage copy and paste
    Connections {
        target: copyAction

        onTriggered: {
            if (terminalContainer.isActive) {
                kterminal.copyClipboard()
            }
        }
    }
    Connections {
        target: pasteAction

        onTriggered: {
            if (terminalContainer.isActive) {
                kterminal.pasteClipboard()
            }
        }
    }

    //When settings are updated sources need to be redrawn.
    Connections {
        target: appSettings

        onFontScalingChanged: {
            terminalContainer.updateSources()
        }

        onFontWidthChanged: {
            terminalContainer.updateSources()
        }
    }
    Connections {
        target: terminalContainer

        onWidthChanged: {
            terminalContainer.updateSources()
            terminalContainer.restartGeometryFit()
        }

        onHeightChanged: {
            terminalContainer.updateSources()
            terminalContainer.restartGeometryFit()
        }
    }

    function updateSources() {
        kterminal.update()
    }

    // --geom: find the largest font scaling that still shows the requested lines and columns,
    // then widen the margins until exactly that many are shown. The cell count depends on the
    // margins, bitmap font scaling and the widget's own rounding, so this measures the result
    // after each change rather than trying to compute it.
    property size targetGeometry: startupGeometry
    property bool geometryScaleFitted: false
    property int geometryFitSteps: 0
    // Largest scaling seen to fit and smallest seen not to; once both are known, bisect.
    property real geometryFitLow: 0
    property real geometryFitHigh: Infinity

    function restartGeometryFit() {
        if (targetGeometry.width <= 0)
            return
        geometryScaleFitted = false
        geometryFitSteps = 0
        geometryFitLow = 0
        geometryFitHigh = Infinity
        kterminal.extraMargin = 0
        kterminal.extraVerticalMargin = 0
        geometryFitTimer.restart()
    }

    function fitGeometry() {
        // QMLTermWidget reports terminalSize as QSize(lines, columns), the reverse of targetGeometry.
        var cols = kterminal.terminalSize.height
        var rows = kterminal.terminalSize.width
        if (appSettings.verbose)
            console.log("geom fit:", cols + "x" + rows, "cells, scaling", appSettings.fontScaling.toFixed(3),
                        "area", width + "x" + height, "texture", kterminal.totalWidth + "x" + kterminal.totalHeight,
                        "extra margins", kterminal.extraMargin, kterminal.extraVerticalMargin)
        // The cap guards against settling into a loop between two sizes.
        if (cols <= 0 || rows <= 0 || ++geometryFitSteps > 40)
            return

        if (!geometryScaleFitted) {
            var scaling = appSettings.fontScaling
            var ratio = Math.min(cols / targetGeometry.width, rows / targetGeometry.height)
            if (ratio >= 1)
                geometryFitLow = Math.max(geometryFitLow, scaling)
            else
                geometryFitHigh = Math.min(geometryFitHigh, scaling)

            var next
            if (ratio >= 1 && ratio < 1.03) {
                // Within a few percent is as close as whole cells allow; the margins pad the rest.
                next = scaling
            } else if (geometryFitLow > 0 && geometryFitHigh < Infinity) {
                // Proportional guesses overshoot because the line count doesn't scale exactly
                // inversely (line spacing is rounded per scaling), so bisect once bracketed.
                next = geometryFitHigh - geometryFitLow < 0.01 * geometryFitLow
                    ? geometryFitLow : (geometryFitLow + geometryFitHigh) / 2
            } else {
                // Cell counts scale roughly inversely with the font scaling.
                next = scaling * ratio * (ratio >= 1 ? 0.995 : 0.98)
            }
            // No upper clamp: maximumFontScaling limits manual zoom, but on a large screen the
            // requested geometry can need more. Shrinking below the minimum is still refused.
            next = Math.max(appSettings.minimumFontScaling, next)
            if (Math.abs(next - scaling) > 0.001) {
                appSettings.fontScaling = next
                geometryFitTimer.restart()
                return
            }
            geometryScaleFitted = true
        }

        var margin = Math.max(0, kterminal.extraMargin + marginStep(cols - targetGeometry.width, kterminal.width / cols))
        var verticalMargin = Math.max(0, kterminal.extraVerticalMargin + marginStep(rows - targetGeometry.height, kterminal.height / rows))
        if (margin !== kterminal.extraMargin || verticalMargin !== kterminal.extraVerticalMargin) {
            kterminal.extraMargin = margin
            kterminal.extraVerticalMargin = verticalMargin
            geometryFitTimer.restart()
        }
    }

    // cellSize is measured as size / count, which slightly overestimates the real cell size.
    // So the first jump never removes too many cells, and single pixels settle the rest.
    function marginStep(excessCells, cellSize) {
        if (excessCells > 0)
            return Math.max(1, Math.floor(excessCells * cellSize / 2))
        return excessCells < 0 ? -1 : 0
    }

    Timer {
        id: geometryFitTimer
        // A font or window change arrives as several relayouts; measure once they settle.
        interval: 100
        onTriggered: terminalContainer.fitGeometry()
    }

    QMLTermWidget {
        id: kterminal

        property int textureResolutionScale: appSettings.lowResolutionFont ? Screen.devicePixelRatio : 1
        // Padding added by the --geom fit, in terminal pixels.
        property int extraMargin: 0
        property int extraVerticalMargin: 0
        property int margin: appSettings.margin / screenScaling + extraMargin
        property int verticalMargin: appSettings.verticalMargin / screenScaling + extraVerticalMargin
        property int totalWidth: Math.floor(parent.width / (screenScaling * fontWidth))
        property int totalHeight: Math.floor(parent.height / screenScaling)

        property int rawWidth: totalWidth - 2 * margin
        property int rawHeight: totalHeight - 2 * verticalMargin

        textureSize: Qt.size(width / textureResolutionScale, height / textureResolutionScale)

        width: ensureMultiple(rawWidth, Screen.devicePixelRatio)
        height: ensureMultiple(rawHeight, Screen.devicePixelRatio)

        /** Ensure size is a multiple of factor. This is needed for pixel perfect scaling on highdpi screens. */
        function ensureMultiple(size, factor) {
            return Math.round(size / factor) * factor;
        }

        fullCursorHeight: true
        blinkingCursor: appSettings.blinkingCursor

        // The keytab maps plain Backspace to ^H, so send DEL (ASCII 127) ahead of
        // the widget. Accepting the event skips the widget's own key handling,
        // which only restarts the cursor blink timer. Modified Backspace keeps its
        // keytab mapping.
        Keys.onPressed: function(event) {
            if (appSettings.backspaceSendsDelete && event.key === Qt.Key_Backspace
                    && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                ksession.sendText("\x7f")
                event.accepted = true
            }
        }

        colorScheme: "cool-retro-term"

        session: QMLTermSession {
            id: ksession

            onFinished: {
                terminalContainer.sessionFinished()
            }
        }

        QMLTermScrollbar {
            id: kterminalScrollbar
            terminal: kterminal
            anchors.margins: width * 0.5
            width: terminal.fontMetrics.width * 0.75
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                color: "white"
                opacity: 0.7
            }
        }

        function handleFontChanged(fontFamily, pixelSize, lineSpacing, screenScaling, fontWidth, fallbackFontFamily, lowResolutionFont) {
            kterminal.lineSpacing = lineSpacing;
            kterminal.antialiasText = !lowResolutionFont;
            kterminal.smooth = !lowResolutionFont;
            kterminal.enableBold = !lowResolutionFont;
            kterminal.enableItalic = !lowResolutionFont;

            kterminal.font = Qt.font({
                family: fontFamily,
                pixelSize: pixelSize
            });

            terminalContainer.fontWidth = fontWidth;
            terminalContainer.screenScaling = screenScaling;
            scaleTexture = Math.max(1.0, Math.floor(screenScaling * appSettings.windowScaling));
        }

        Connections {
            target: appSettings

            onWindowScalingChanged: {
                scaleTexture = Math.max(1.0, Math.floor(terminalContainer.screenScaling * appSettings.windowScaling));
            }
        }

        function startSession() {
            // Retrieve the variable set in main.cpp if arguments are passed.
            if (defaultCmd) {
                ksession.setShellProgram(defaultCmd);
                ksession.setArgs(defaultCmdArgs);
            } else if (appSettings.useCustomCommand) {
                var args = Utils.tokenizeCommandLine(appSettings.customCommand);
                ksession.setShellProgram(args[0]);
                ksession.setArgs(args.slice(1));
            } else if (!defaultCmd && appSettings.isMacOS) {
                // OSX Requires the following default parameters for auto login.
                ksession.setArgs(["-i", "-l"]);
            }

            if (workdir)
                ksession.initialWorkingDirectory = workdir;

            ksession.startShellProgram();
            forceActiveFocus();
        }
        Component.onCompleted: {
            appSettings.fontManager.terminalFontChanged.connect(handleFontChanged);
            appSettings.fontManager.refresh()
            startSession();
            terminalContainer.restartGeometryFit()
        }
        Component.onDestruction: {
            appSettings.fontManager.terminalFontChanged.disconnect(handleFontChanged);
        }
    }

    Component {
        id: shortContextMenu
        ShortContextMenu { }
    }

    Component {
        id: fullContextMenu
        FullContextMenu { }
    }

    Loader {
        id: menuLoader
        sourceComponent: (appSettings.isMacOS || (appSettings.showMenubar && !terminalWindow.fullscreen) ? shortContextMenu : fullContextMenu)
    }
    property alias contextmenu: menuLoader.item

    MouseArea {
        // Window pixels; the --geom padding is in terminal pixels, which are scaled up on screen.
        property real margin: appSettings.margin + kterminal.extraMargin * screenScaling * fontWidth
        property real verticalMargin: appSettings.verticalMargin + kterminal.extraVerticalMargin * screenScaling
        property real frameSize: appSettings.frameSize * terminalWindow.normalizedWindowScale

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        anchors.fill: parent
        cursorShape: kterminal.terminalUsesMouse ? Qt.ArrowCursor : Qt.IBeamCursor
        onWheel: function(wheel) {
            if (wheel.modifiers & Qt.ControlModifier) {
               wheel.angleDelta.y > 0 ? zoomIn.trigger() : zoomOut.trigger();
            } else {
                var coord = correctDistortion(wheel.x, wheel.y);
                kterminal.simulateWheel(coord.x, coord.y, wheel.buttons, wheel.modifiers, wheel.angleDelta);
            }
        }
        onDoubleClicked: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseDoubleClick(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }
        onPressed: function(mouse) {
            kterminal.forceActiveFocus()
            if ((!kterminal.terminalUsesMouse || mouse.modifiers & Qt.ShiftModifier) && mouse.button == Qt.RightButton) {
                contextmenu.popup();
            } else {
                var coord = correctDistortion(mouse.x, mouse.y);
                kterminal.simulateMousePress(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers)
            }
        }
        onReleased: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseRelease(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }
        onPositionChanged: function(mouse) {
            var coord = correctDistortion(mouse.x, mouse.y);
            kterminal.simulateMouseMove(coord.x, coord.y, mouse.button, mouse.buttons, mouse.modifiers);
        }

        function correctDistortion(x, y) {
            x = (x - margin) / width;
            y = (y - verticalMargin) / height;

            x = x * (1 + frameSize * 2) - frameSize;
            y = y * (1 + frameSize * 2) - frameSize;

            var cc = Qt.size(0.5 - x, 0.5 - y);
            var distortion = (cc.height * cc.height + cc.width * cc.width)
                    * appSettings.screenCurvature * appSettings.screenCurvatureSize
                    * terminalWindow.normalizedWindowScale;

            return Qt.point((x - cc.width  * (1+distortion) * distortion) * (kterminal.totalWidth),
                           (y - cc.height * (1+distortion) * distortion) * (kterminal.totalHeight))
        }
    }
    ShaderEffectSource{
        id: kterminalSource
        sourceItem: kterminal
        hideSource: true
        wrapMode: ShaderEffectSource.Repeat
        visible: false
        textureSize: Qt.size(kterminal.totalWidth * scaleTexture, kterminal.totalHeight * scaleTexture)
        sourceRect: Qt.rect(-kterminal.margin, -kterminal.verticalMargin, kterminal.totalWidth, kterminal.totalHeight)
    }

    Item {
        id: burnInContainer

        property int burnInScaling: scaleTexture * appSettings.burnInQuality

        width: Math.round(appSettings.lowResolutionFont
               ? kterminal.totalWidth * Math.max(1, burnInScaling)
               : kterminal.totalWidth * scaleTexture * appSettings.burnInQuality)

        height: Math.round(appSettings.lowResolutionFont
                ? kterminal.totalHeight * Math.max(1, burnInScaling)
                : kterminal.totalHeight * scaleTexture * appSettings.burnInQuality)


        BurnInEffect {
            id: burnInEffect
        }
    }
}
