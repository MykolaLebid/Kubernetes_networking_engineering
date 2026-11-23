// PDF table styles — injected after pandoc's default typst template
// Overrides the default stroke:none and minimal inset

// --- Table body ---
#set table(
  inset: (x: 9pt, y: 6pt),
  stroke: (x, y) => (
    top:    if y == 1 { 0.6pt + rgb("2d6a9f") } else { none },
    bottom: 0.4pt + rgb("c8d8ea"),
    left:   none,
    right:  none,
  ),
  fill: (x, y) =>
    if y == 0        { rgb("1a3a6b") }        // header row — dark navy
    else if calc.rem(y, 2) == 1 { rgb("f2f6fb") }  // odd data rows — light blue tint
    else             { white },
)

// --- Header cells: white bold text ---
#show table.cell.where(y: 0): set text(fill: white, weight: "bold", size: 8.5pt)

// --- Body cells: slightly smaller to fit wide tables ---
#show table.cell: set text(size: 8.5pt, hyphenate: true)

// --- Inline code inside table cells: smaller mono ---
#show table.cell: it => {
  show raw.where(block: false): set text(size: 7.5pt)
  it
}

// --- Page & typography ---
#set page(margin: (top: 18mm, bottom: 18mm, left: 18mm, right: 18mm))
#set text(size: 10.5pt, hyphenate: true, lang: "en")
#set par(leading: 0.65em)

// --- Code blocks: slightly smaller and boxed ---
#show raw.where(block: true): it => block(
  fill: rgb("f8f8f8"),
  inset: 10pt,
  radius: 4pt,
  stroke: 0.5pt + rgb("dddddd"),
  width: 100%,
  text(size: 8pt, it),
)
