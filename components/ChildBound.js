// A deadline for a data source's child process.
//
// `df` on a dead NFS server, `khal` on a wedged vdir, `find` in a folder on a
// hung FUSE mount, `codeburn` on a huge corpus: each of these can run for as
// long as the thing it waits on, and every source here steps around a child
// that is still running - so one that never ends freezes its tile, or a latch
// such as CodeburnData's `recomputing`, for the rest of the session.
//
// coreutils `timeout` is the bound: TERM at `timeoutSec`, KILL `killGraceSec`
// later, sent to its whole process group, so a pipeline (`find | head | sort`)
// and anything the command forked go with it. Two gaps in `timeout` alone are
// closed by the one line of `sh` that runs it:
//  - Its KILL is only sent while the command ITSELF is still running. When
//    the command obeys TERM but something it started does not (a pipeline
//    stage, a forked helper), `timeout` exits 124 and leaves that straggler
//    orphaned and unbounded. `timeout` leads its own process group, so a
//    guardian subshell KILLs that group once `timeout` has returned 124.
//  - A Process that is destroyed while running - a tile removed, the shell
//    reloading - has its direct child SIGKILLed, with no TERM first, and a
//    SIGKILLed `timeout` would signal nobody. So the direct child is a plain
//    `sh` that only waits: when it is killed, the guardian and `timeout` live
//    on as orphans and still end everything at the bound. A cancelled run
//    therefore ends at its bound rather than at once - bounded either way.
//
// Exit codes the caller sees: the command's own, or 124 (bound expired, the
// command obeyed TERM), 137 (it had to be KILLed), 126/127 (`timeout` or the
// command could not be executed).
//
// Imported the way JsonRead.js is: a relative `import "ChildBound.js" as
// ChildBound` beside the component; a .js file needs no qmldir entry.

var _script = "g=$1; t=$2; shift 2; " +
  "( timeout -k \"$g\" \"$t\" \"$@\" & q=$!; wait $q; rc=$?; " +
  "[ $rc -eq 124 ] && kill -s KILL -- \"-$q\" 2>/dev/null; exit $rc ) & wait $!"

// The argv that runs `command` (an argv list) under the bound.
function argv(timeoutSec, killGraceSec, command) {
  return ["sh", "-c", _script, "sh", String(killGraceSec), String(timeoutSec)].concat(command)
}

// True when a run ended at the bound rather than on its own: `timeout`'s two
// codes, or the wrapper itself killed by a signal (QProcess.CrashExit).
function timedOut(exitCode, exitStatus) {
  return exitCode === 124 || exitCode === 137 || exitStatus === 1
}

// True when the command could not be executed at all.
function notRunnable(exitCode) {
  return exitCode === 126 || exitCode === 127
}
