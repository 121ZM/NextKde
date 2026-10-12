pragma Singleton
import QtQuick
import "Translations.mjs" as Translations

QtObject {
    readonly property bool chinese: Translations.isChinese(Qt.locale().uiLanguages)
    readonly property var locale: Qt.locale(chinese ? "zh_CN" : "en_US")
    function text(source) { return chinese ? source : (Translations.english[source] ?? source) }
    function formatDate(date, format) { return date.toLocaleDateString(locale, format) }
    function formatTime(date, format) { return date.toLocaleTimeString(locale, format) }
    function formatDateTime(date, format) { return date.toLocaleString(locale, format) }
}
