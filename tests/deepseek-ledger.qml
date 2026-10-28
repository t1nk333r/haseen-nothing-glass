import QtQuick
import Quickshell
import "components"

// Driven by tests/deepseek-ledger.sh: which of the two DeepSpend ledgers
// DeepSeekData shows. EXPECTED_TOTAL is the balance of the ledger that should
// win, "none" when neither file exists; with LIVE_UPDATES=1 the script swaps
// the haseen ledger twice and each new balance has to arrive.
QtObject {
  property DeepSeekData data: DeepSeekData {}
  property Timer check: Timer {
    interval: 100
    running: true
    repeat: true
    property int ticks: 0
    property int step: 0
    onTriggered: {
      ticks++
      var want = Quickshell.env("EXPECTED_TOTAL")
      var got = data.hasBalance ? data.total.toFixed(2) : (data.loaded && !data.ledgerFound ? "none" : "")
      if (Quickshell.env("LIVE_UPDATES") === "1") {
        if (got === (step + 1).toFixed(2) + "") {
          step++
          console.log("DEEPSEEK_STEP_" + step)
          if (step === 3) { console.log("DEEPSEEK_PASS"); Qt.quit() }
        }
      } else if (got === want && (want === "none") === (data.ledgerPath === "")) {
        console.log("DEEPSEEK_PASS " + data.ledgerPath)
        Qt.quit()
      }
      if (ticks >= 40) {
        console.log("DEEPSEEK_FAIL: showed '" + got + "' from '" + data.ledgerPath + "', expected '" + want + "'")
        Qt.quit()
      }
    }
  }
}
