# Markdown Syntax Cheatsheet

An incomplete list of markdown syntax that includes most of the syntax helpful in my case.

## Table of Contents

*   [Text Formatting](#text-formatting)
*   [Headings](#headings)
*   [Lists](#lists)
*   [Links](#links)
*   [Images](#images)
*   [Code](#code)
*   [Tables](#tables)
*   [Blockquotes](#blockquotes)
*   [Horizontal Rule](#horizontal-rule)
*   [Line Breaks](#line-breaks)
*   [Task Lists](#task-lists)
*   [Strikethrough](#strikethrough)
*   [Highlighting](#highlighting)
*   [Escape Characters](#escape-characters)
*   [Further Reading](#further-reading)

---

## Text Formatting

| Style       | Syntax           | Example                    |
| :---------- | :--------------- | :------------------------- |
| Bold        | `**text**`       | **BoldTextHere**           |
| Italic      | `*text*` or `_text_` | *ItalicTextHere*           |
| Strikethrough| `~~text~~`      | ~~Strikethrough~~          |

## Headings

```markdown
# Heading L1
## Heading L2
### Heading L3
#### Heading L4
##### Heading L5
###### Heading L6
```

## Lists

### Ordered List

```markdown
1. First item
2. Second item
3. Third item
    - Indented item
    - Indented item
4. Fourth item
```

### Unordered List

```markdown
- First item
- Second item
- Third item
```

## Links

```markdown
This repo is hosted by [GitHub](https://www.github.com).
```

To quickly insert links to sites and email use `<>`

```markdown
<https://www.github.com>
<email@example.com>
```

## Images

To insert an image:

```markdown
![Title Image](/path/images/image.png)
```

## Code

### Inline Code

To insert code inline use `` `code` ``.

### Code Blocks

To create a code block, use triple backticks:

````markdown
```
Put the code here
```
````

You can also specify the language for syntax highlighting:

````markdown
```python
def hello_world():
    print("Hello, world!")
```
````

## Tables

```markdown
| Header 1 | Header 2 | Header 3 |
| :       | :------: | -------: |
| Align    |  Center  |    Right |
| Left     |          |          |
```

| Header 1 | Header 2 | Header 3 |
| :       | :------: | -------: |
| Align    |  Center  |    Right |
| Left     |          |          |

## Blockquotes

```markdown
> This is a blockquote.
```

> This is a blockquote.

## Horizontal Rule

To create a separation line, do one of the following:

```markdown
---
___
***
```

---

## Line Breaks

To create a line break or new line, end a line with two or more spaces, and then type return.
A variant could be to use `<br>` at the end of the line.

## Task Lists

```markdown
- [x] Task 1
- [ ] Task 2
- [ ] Task 3
```

- [x] Task 1
- [ ] Task 2
- [ ] Task 3

## Strikethrough

```markdown
~~This text is strikethrough~~
```

~~This text is strikethrough~~

## Highlighting

```markdown
`This text is highlighted`
```

`This text is highlighted`

## Escape Characters

To display a literal character that has a special meaning in Markdown, use a backslash (`\`) before the character.

```markdown
\*This is not italic\*
```

\*This is not italic\*

## Further Reading

For a more comprehensive guide to Markdown, please visit the [Markdown Guide](https://www.markdownguide.org).