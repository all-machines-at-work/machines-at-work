# Intent notes

Drop a note here — any shape, any filename — describing what you want built or changed.
`/intentpipe:plan` turns notes into tasks and commits your words to git history; that history
is the record of intent. There is no living spec document to maintain.

A good note carries, in whatever form fits:
- **What it is / what changes** — the product, or the delta.
- **Requirements** as testable statements — prefer "WHEN <condition> THE SYSTEM SHALL <behavior>".
- **Out of scope** — explicit non-goals; agents treat these as forbidden.
- **How it's proven** — the commands or flows that show a finished result works end-to-end.

A note can carry **images**: a photo texted into the project's Telegram topic is saved under
`intentpipe/resources/` and its caption becomes a note referencing it (`[image: …]`).
`/intentpipe:plan` reads the image itself — a mockup, a screenshot of a bug, a sketch —
and the tasks it spawns record the path (`Resources:`) so the implementer and reviewer see the
same picture. Dropping a file into `resources/` by hand and referencing it from a note works
identically. Unlike notes, resource files are never deleted.

A note can also amend work sitting in a **still-open PR** — name the PR or feature and the new
tasks land on its branch, so the same PR picks them up. Once that PR merges, the window closes
automatically; the note becomes a fresh task instead.

Notes are consumed by `/intentpipe:plan` and removed from this folder once planned; recover any
past note from git history. This folder and its README stay; `/intentpipe:plan` ignores the README.
