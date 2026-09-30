---
name: New widget request
about: Suggest a new widget for the set
title: "[NEW]"
labels: widget request
assignees: t1nk333r

---

**Widget name**:

**Group**: Time / World / Weather / Date / Timer / Media / System

**Drawing(s)**: Liquid Glass, Nothing, or both — the set draws two styles from one
runtime, and a type that ships only one is the exception, so say which and why.

**What it shows, and where the numbers come from**: every widget in this set reads
a file, a socket or an IPC verb — a plugin cannot reach another plugin's service,
so a source that lives in another plugin is not one (PORTING.md item 25). Name the
source, and if it does not exist yet, say what would write it.

**Sizes it must hold up at**: 1:1 and 2:1 (wide) are the two shapes in play; the
grid presets are 192x192, 400x400 and 400x192. Say which ones matter most.

**References**
Images for the design, and API documentation if the data comes from a service.

**Resources**
Anything that can be used inside the widget — icons, fonts, and their licences.

**Is it per-instance configurable?** If a value should differ between two tiles of
this type (a city, a folder, a host), say which, so it can be a per-instance field
rather than a plugin-wide setting.
