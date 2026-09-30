---
name: Bug report
about: Create a report to help us improve
title: "[BUG]"
labels: bug
assignees: t1nk333r

---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Your setup (please complete the following information):**
- Omarchy and Quickshell versions (`omarchy version`, `qs --version`):
- Installed plugins (`omarchy plugin list`):
- How you installed it: `omarchy plugin add <url>` from this repo / a hand-copied folder / other (say which)

**What the shell says about it**
If a widget is missing, drawing nothing, or a change did not take effect, paste
this, and the widget's type and id from
`omarchy-shell t1nk33r.nothing-glass listWidgets`:

```bash
journalctl --user -t omarchy-shell --since '-5min' | grep -i nothing-glass
```

**Additional context**
Add any other context about the problem here.
