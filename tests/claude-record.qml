import QtQuick
import Quickshell
import "components"

QtObject {
  property ClaudeUsageData data: ClaudeUsageData {}
  property Timer check: Timer {
    interval: 100
    running: true
    repeat: true
    property int ticks: 0
    property int step: 0
    onTriggered: {
      ticks++
      if (Quickshell.env("LIVE_UPDATES") === "1" && data.sourceName === "Live" + (step + 1)) {
        step++
        console.log("CLAUDE_STEP_" + step)
        if (step === 3) { console.log("CLAUDE_PASS"); Qt.quit() }
      } else if (Quickshell.env("LIVE_UPDATES") !== "1" && data.sourceName === Quickshell.env("EXPECTED_SOURCE")) {
        console.log("CLAUDE_PASS")
        Qt.quit()
      } else if (ticks >= 25) {
        console.log("CLAUDE_FAIL: selected the wrong record")
        Qt.quit()
      }
    }
  }
}
