import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kholidays as KHolidays
import org.kde.kirigami as Kirigami
import org.kde.kirigami.delegates as KD
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.private.holidayevents as Private

KCMUtils.SimpleKCM {
    id: root

    property var oldSelectedRegions
    property bool unsavedChanges

    function saveConfig() {
        configHelper.saveConfig();
        root.oldSelectedRegions = [...configHelper.selectedRegions];
        root.unsavedChanges = false;
    }

    function checkUnsavedChanges() {
        root.unsavedChanges = !(configHelper.selectedRegions.every(function(e) { return root.oldSelectedRegions.includes(e); })
                                && root.oldSelectedRegions.every(function(e) { return configHelper.selectedRegions.includes(e); }));
    }

    Private.HolidayRegionsConfig {
        id: configHelper
        Component.onCompleted: root.oldSelectedRegions = [...configHelper.selectedRegions]
    }

    property int _selectionVersion: 0

    KHolidays.HolidayRegionsModel { id: allRegions }

    property int _regionRole: 0
    property int _nameRole: 0
    property int _descRole: 0

    Component.onCompleted: {
        var rn = allRegions.roleNames();
        for (var role in rn) {
            var n = String(rn[role]);
            if (n === "region") _regionRole = parseInt(role);
            else if (n === "name") _nameRole = parseInt(role);
            else if (n === "description") _descRole = parseInt(role);
        }
    }

    function _rebuildLists() {
        var en = [];
        var av = [];
        var ft = filter.text.toLowerCase();
        for (var i = 0; i < allRegions.rowCount(); i++) {
            var idx = allRegions.index(i, 0);
            var region = allRegions.data(idx, _regionRole);
            var name = allRegions.data(idx, _nameRole);
            var desc = allRegions.data(idx, _descRole) || "";
            var entry = { region: region, name: name, description: desc };
            if (configHelper.selectedRegions.includes(region)) {
                en.push(entry);
            } else {
                if (ft.length === 0 || name.toLowerCase().indexOf(ft) !== -1)
                    av.push(entry);
            }
        }
        enabledList = en;
        availableList = av;
    }

    property var enabledList: []
    property var availableList: []

    Timer {
        id: rebuildTimer
        interval: 50
        onTriggered: root._rebuildLists()
    }

    on_selectionVersionChanged: rebuildTimer.restart()
    Component.onCompleted: Qt.callLater(_rebuildLists)

    Kirigami.SearchField {
        id: filter
        anchors { left: parent.left; right: parent.right }
        placeholderText: i18n("Search holiday regions…")
        onTextChanged: root._rebuildLists()
    }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: filter.bottom; topMargin: Kirigami.Units.smallSpacing }
        spacing: 0

        QQC2.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            text: i18n("Enabled")
            font.bold: true
            opacity: 0.7
            visible: enabledRepeater.count > 0
        }

        Repeater {
            id: enabledRepeater
            model: root.enabledList
            delegate: QQC2.CheckDelegate {
                Layout.fillWidth: true
                text: modelData.name
                checked: true
                icon.width: 0

                contentItem: KD.IconTitleSubtitle {
                    title: modelData.name
                    subtitle: modelData.description
                    selected: parent.highlighted || parent.down
                    font: parent.font
                    reserveSpaceForSubtitle: true
                    wrapMode: Text.Wrap
                }

                onClicked: {
                    configHelper.removeRegion(modelData.region);
                    root._selectionVersion++;
                    root.checkUnsavedChanges();
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            text: i18n("Available")
            font.bold: true
            opacity: 0.7
            visible: availableRepeater.count > 0
        }

        Repeater {
            id: availableRepeater
            model: root.availableList
            delegate: QQC2.CheckDelegate {
                Layout.fillWidth: true
                text: modelData.name
                checked: false
                icon.width: 0

                contentItem: KD.IconTitleSubtitle {
                    title: modelData.name
                    subtitle: modelData.description
                    selected: parent.highlighted || parent.down
                    font: parent.font
                    reserveSpaceForSubtitle: true
                    wrapMode: Text.Wrap
                }

                onClicked: {
                    configHelper.addRegion(modelData.region);
                    root._selectionVersion++;
                    root.checkUnsavedChanges();
                }
            }
        }
    }
}
