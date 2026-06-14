# Translating the widgets

These widgets use the standard `i18n()` translation system. Every user-facing
string is already marked translatable, so contributing a language is mostly a
matter of filling in the blanks.

## How it works

```
template.pot  ->  your_language.po  ->  compiled .mo  ->  bundled in the widget
  (source)         (you translate)       (build.sh)        (install/package)
```

Each widget has a `template.pot` listing its strings. You copy it to a `.po`
file for your language, translate the entries, and `build.sh` compiles them into
`.mo` files that ship with the widget.

## Contributing a translation

### 1. Copy the template

```bash
cd translate/<package>/
cp template.pot <language_code>.po
```

For a Dutch translation of the weather widget:

```bash
cd translate/weather/
cp template.pot nl.po
```

Language codes follow [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes):

| Language | Code |
|----------|------|
| Dutch | `nl` |
| French | `fr` |
| German | `de` |
| Spanish | `es` |
| Portuguese (Brazil) | `pt_BR` |
| Japanese | `ja` |
| Korean | `ko` |
| Chinese (Simplified) | `zh_CN` |

### 2. Translate

Open the `.po` file in a translation editor — [Lokalize](https://apps.kde.org/lokalize/),
[Poedit](https://poedit.net/), or any text editor. Each entry looks like:

```po
#: packages/weather/contents/ui/config/ConfigGeneral.qml:143
msgid "Temperature unit:"
msgstr ""
```

Fill in `msgstr`:

```po
msgid "Temperature unit:"
msgstr "Temperatuureenheid:"
```

Some strings carry a placeholder (`%1`) or a plural form — keep the placeholder
and translate both forms:

```po
msgid "No precipitation for %1 day"
msgid_plural "No precipitation for %1 days"
msgstr[0] "Geen neerslag voor %1 dag"
msgstr[1] "Geen neerslag voor %1 dagen"
```

Also update the header at the top: set `Language:` to your code, leave the
charset as `UTF-8`, and put your name in `Last-Translator`.

### 3. Open a pull request

Commit the `.po` file and open a PR. The compiled `.mo` is generated on the
maintainer's side, so you only need to send the `.po`.

## Available widgets

| Package | Strings |
|---|---|
| `calendar` | 46 |
| `city-1` | 32 |
| `city-2` | 32 |
| `city-3` | 32 |
| `city-digital` | 30 |
| `clock-analog` | 28 |
| `clock-analog-2` | 28 |
| `clock-analog-3` | 26 |
| `clock-digital` | 26 |
| `music` | 38 |
| `timer` | 29 |
| `weather` | 70 |
| `weather-panel` | 42 |

(Widget names and descriptions in `metadata.json` are not part of this pipeline
and stay in English.)

## For maintainers

### Regenerate templates after changing strings

If you add or change an `i18n()` string in any QML file, refresh the templates.
This also merges the changes into existing `.po` files so nothing is lost.

```bash
./translate/merge.sh              # all widgets
./translate/merge.sh weather      # one widget
```

### Build the translations

Translations compile automatically during `./install.sh` and `./package.sh`.
To do it by hand:

```bash
./translate/build.sh
```

Output lands at:

```
packages/<widget>/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<id>.mo
```

### Requirements

Both scripts need `gettext`:

```bash
sudo apt install gettext      # Debian/Ubuntu
sudo dnf install gettext      # Fedora
sudo pacman -S gettext        # Arch
```
