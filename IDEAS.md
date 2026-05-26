# TOPIC: Internal Representation

* Investigation - existing formatting languages and engines

Most existing formatting engines are build with the idea of text flowing from one page to the next.
This is incompatible with a slide deck.

nb. The KP Line Breaking Algorithm is considered world class and [not really supported by web](https://medium.com/@glitterliu617/on-typesetting-engines-a-programmers-perspective-58f537a353d7)

Some existing things have potential:

* LaTeX - The "beamer" documentclass can create slides

Beamer -> pandoc -> html is supported
absolute positioning in beamer is [difficult](https://tex.stackexchange.com/questions/682694/simple-way-to-position-a-text-anywhere-on-a-beamer-frame)

* fodp - "Flat" odp - an xml representation of the open document format

XML is verbose, but I think I read the llms are good at XML? investigate
ODP -> PDF is supported, but to get to html we need to go through beamer and pandoc

* pandoc supports [slidess]( https://pandoc.org/MANUAL.html#slide-shows)

[filters](https://daveho.github.io/2024/01/24/pandoc-for-presentations.html) - raw markdown conversion
pandoc supports LaTeX math syntax

We could also work directly on the pandoc AST

Pandoc makePDF internally uses LaTeX or HTML
