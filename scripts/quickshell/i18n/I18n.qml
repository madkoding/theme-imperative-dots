pragma Singleton
import QtQuick
import "../lib" as QsLib

QtObject {
    function s(text) {
        return QsLib.I18n.s(text)
    }

    function currentLanguage() {
        return QsLib.I18n.currentLanguage()
    }

    function setLanguage(languageCode) {
        QsLib.I18n.setLanguage(languageCode)
    }
}
