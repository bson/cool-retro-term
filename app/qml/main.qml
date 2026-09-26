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

import "menus"

QtObject {
    id: appRoot

    property ApplicationSettings appSettings: ApplicationSettings {
        onInitializedSettings: appRoot.createWindow()
    }

    property TimeManager timeManager: TimeManager {
        enableTimer: windowsModel.count > 0
    }

    property SettingsWindow settingsWindow: SettingsWindow {
        visible: false
    }

    property AboutDialog aboutDialog: AboutDialog {
        visible: false
    }

    property Component windowComponent: Component {
        TerminalWindow { }
    }

    property ListModel windowsModel: ListModel { }

    // --fullscreen applies only to the first window, not to later "New Window" ones.
    property bool pendingFullscreen: startupFullscreen

    // The terminal that runs the --geom font scaling search; see PreprocessedTerminal.
    property var geometryFitOwner: null

    function createWindow() {
        // TerminalWindow shows itself once complete, in the state given here. Calling show()
        // afterwards would reset it to normal state.
        var window = windowComponent.createObject(null, { fullscreen: pendingFullscreen })
        if (!window)
            return
        pendingFullscreen = false

        windowsModel.append({ window: window })
        window.requestActivate()
    }

    function closeWindow(window) {
        for (var i = 0; i < windowsModel.count; i++) {
            if (windowsModel.get(i).window === window) {
                windowsModel.remove(i)
                break
            }
        }

        window.destroy()

        if (windowsModel.count === 0) {
            appSettings.close()
        }
    }
}
