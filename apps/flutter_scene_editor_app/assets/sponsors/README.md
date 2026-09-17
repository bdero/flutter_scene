# Sponsors manifest

`sponsors.json` is the list of sponsors baked into each editor build. The
start screen shows logos from Gold, the About dialog names sponsors from
Silver and lists backers. Placement follows the sponsorship program, so an
entry is added when a term starts and removed when it ends; a known end date
can be set as `until` instead.

Logos go in `logos/` as PNG (light and an optional dark variant) and are
referenced by asset key, `assets/sponsors/logos/<name>.png`. Add
`assets/sponsors/logos/` to the app pubspec's assets when the first logo
lands. Logos are the property of their owners, used with permission for the
placements the program describes.

TODO(sponsors): the fscene.dev sponsors page and the README section should
be generated from this same file so every surface stays in step.
