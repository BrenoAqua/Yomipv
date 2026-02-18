## Yomitan markers

These are the markers from Yomitan:

`glossary`
`glossary-brief`
`glossary-no-dictionary`
`glossary-plain`
`glossary-plain-no-dictionary`
`glossary-first`
`glossary-first-brief`
`glossary-first-no-dictionary`
`single-glossary-DICT-NAME`
`single-glossary-DICT-NAME-brief`
`single-glossary-DICT-NAME-no-dictionary`
`popup-selection-text`

Multiple markers can be specified as a comma-separated list

Example:

```
glossary_handlebar=single-glossary-DICT-NAME-1,single-glossary-DICT-NAME-2,single-glossary-DICT-NAME-3
```

---

## Basic usage

```
definition_handlebar=popup-selection-text
definition_handlebar=single-glossary-DICT-NAME
definition_handlebar=glossary
```

### Behavior

* Same as when creating a card from Yomitan’s popup
* If a dictionary is selected for `selected-dict`, `popup-selection-text` is disabled

---

## Yomipv-specific marker

`selected-dict`

When using the lookup app, clicking a dictionary title marks it as the **selected dictionary**
This marker inserts content from that dictionary

### Behavior

* If a dictionary is selected, its content is inserted into the field it's configured
* If no dictionary is selected, the next fallback marker is used
* Text selected inside the dictionary entry is highlighted

---

## Usage with fallback

```
definition_handlebar=selected-dict,single-glossary-DICT-NAME
```

### Behavior

* If a dictionary is selected in the lookup app, its content is used.
* If no dictionary is selected, the fallback (`single-glossary-DICT-NAME`) is used

---

## Custom handlebars

Custom handlebars are also supported, including those from
[AuroraWright’s dictionary handlebars](https://gist.github.com/AuroraWright/8f529e7ec5a47bfa5d979821541562a5).

Example:

```
definition_handlebar=selected-dict,primary-definition
definition_handlebar=selected-dict,secondary-definition
```

---

## Applicable fields

The same selection and fallback logic applies to the following fields:

```
definition_handlebar
selection_text_handlebar
glossary_handlebar
```

All of these fields support:

* multiple comma-separated markers
* left-to-right fallback resolution
* the `selected-dict` marker
* custom handlebars