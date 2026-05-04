import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.PimCalendars
import org.kde.kitemmodels
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.ScrollViewKCM {
    id: root

    signal configurationChanged

    function saveConfig() {
        calendarModel.saveConfig();
    }

    PimCalendarsModel {
        id: calendarModel
    }

    KDescendantsProxyModel {
        id: flatModel
        expandsByDefault: false
        model: calendarModel
    }

    property int _refreshCounter: 0

    // Role number cache — probed once from first available row
    property int _collectionIdRole: -1
    property int _enabledRole: -1
    property int _checkedRole: -1
    property bool _rolesResolved: false

    function _resolveRoles() {
        if (_rolesResolved) return;
        // Probe: try Qt.UserRole+1..+10 on the source model's first row
        if (calendarModel.rowCount() === 0) return;
        for (var r = 256; r < 270; r++) {
            var idx = calendarModel.index(0, 0);
            var val = calendarModel.data(idx, r);
            if (typeof val === "number" && val > 0 && _collectionIdRole < 0) {
                _collectionIdRole = r;
            } else if (typeof val === "string" && val.length > 0 && _collectionIdRole >= 0) {
                // name role — skip
            } else if (typeof val === "boolean" && _collectionIdRole >= 0 && _enabledRole < 0) {
                _enabledRole = r;
            } else if (typeof val === "boolean" && _enabledRole >= 0 && _checkedRole < 0) {
                _checkedRole = r;
                break;
            }
        }
        _rolesResolved = (_collectionIdRole >= 0 && _enabledRole >= 0 && _checkedRole >= 0);
    }

    function _forEachDescendant(srcParentIdx, callback) {
        var count = calendarModel.rowCount(srcParentIdx);
        for (var i = 0; i < count; i++) {
            var childIdx = calendarModel.index(i, 0, srcParentIdx);
            var childId = calendarModel.data(childIdx, _collectionIdRole);
            var childEnabled = calendarModel.data(childIdx, _enabledRole);
            var childChecked = calendarModel.data(childIdx, _checkedRole);
            callback(childId, childEnabled, childChecked);
            _forEachDescendant(childIdx, callback);
        }
    }

    function _childrenState(parentRow) {
        _resolveRoles();
        if (!_rolesResolved) return { total: 0, checked: 0 };
        var srcIdx = flatModel.mapToSource(flatModel.index(parentRow, 0));
        var total = 0;
        var on = 0;
        _forEachDescendant(srcIdx, function(id, enabled, checked) {
            if (!enabled) return;
            total++;
            if (checked) on++;
        });
        return { total: total, checked: on };
    }

    function _setAllChildren(parentRow, targetState) {
        _resolveRoles();
        if (!_rolesResolved) return;
        var srcIdx = flatModel.mapToSource(flatModel.index(parentRow, 0));
        _forEachDescendant(srcIdx, function(id, enabled, checked) {
            if (!enabled) return;
            calendarModel.setChecked(id, targetState);
        });
        root.configurationChanged();
        root._refreshCounter++;
    }

    view: ListView {
        currentIndex: -1
        clip: true
        focus: true
        activeFocusOnTab: true
        model: flatModel

        delegate: QQC2.ItemDelegate {
            id: del
            width: ListView.view.width

            required property int index
            required property int collectionId
            required property string name
            required property string iconName
            required property bool isChecked
            required property bool isEnabled
            required property int kDescendantLevel
            required property bool kDescendantExpandable
            required property bool kDescendantExpanded

            readonly property bool isParent: kDescendantExpandable

            readonly property bool _isDuplicateLeaf: {
                if (!isEnabled || isParent || kDescendantLevel < 2) return false;
                var srcIdx = flatModel.mapToSource(flatModel.index(index, 0));
                var parentSrcIdx = srcIdx.parent;
                if (!parentSrcIdx.valid) return false;
                var parentName = calendarModel.data(parentSrcIdx, Qt.DisplayRole);
                // Check grandparent too — the account root name
                var gpIdx = parentSrcIdx.parent;
                var gpName = gpIdx && gpIdx.valid ? calendarModel.data(gpIdx, Qt.DisplayRole) : "";
                return (name === parentName || name === gpName);
            }
            readonly property string _displayName: _isDuplicateLeaf ? i18n("Uncategorized Events") : name

            leftPadding: Kirigami.Units.largeSpacing * kDescendantLevel + Kirigami.Units.smallSpacing

            onClicked: {
                if (isParent && !isEnabled) {
                    flatModel.toggleChildren(index);
                }
            }

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    visible: del.isParent
                    source: del.kDescendantExpanded ? "arrow-down" : "arrow-right"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    MouseArea {
                        anchors.fill: parent
                        onClicked: flatModel.toggleChildren(del.index)
                    }
                }

                QQC2.CheckBox {
                    id: checkbox

                    checkState: {
                        var _ = root._refreshCounter;
                        if (del.isEnabled) {
                            return del.isChecked ? Qt.Checked : Qt.Unchecked;
                        }
                        if (!del.isParent) return Qt.Unchecked;
                        var st = root._childrenState(del.index);
                        if (st.total === 0) return Qt.Unchecked;
                        if (st.checked === st.total) return Qt.Checked;
                        if (st.checked === 0) return Qt.Unchecked;
                        return Qt.PartiallyChecked;
                    }
                    tristate: del.isParent && !del.isEnabled
                    nextCheckState: function() {
                        return checkState;
                    }

                    onClicked: {
                        if (del.isEnabled) {
                            calendarModel.setChecked(del.collectionId, !del.isChecked);
                            root.configurationChanged();
                            root._refreshCounter++;
                        } else if (del.isParent) {
                            var st = root._childrenState(del.index);
                            root._setAllChildren(del.index, st.checked < st.total);
                        }
                    }
                }

                Kirigami.Icon {
                    source: del.iconName
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    visible: del.iconName.length > 0
                }

                QQC2.Label {
                    text: del._displayName
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.bold: (del.isParent && !del.isEnabled) || del._isDuplicateLeaf
                }
            }
        }
    }
}
