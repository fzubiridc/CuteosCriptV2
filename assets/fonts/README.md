# Font Index

| ID | Display name | Font | Atlas | Best use |
| --- | --- | --- | --- | --- |
| `tower_gold` | Tower Gold Bitmap | `res://assets/fonts/tower_gold_font.fnt` | `res://assets/fonts/tower_gold_font.png` | HUD fantasy titles and readable gold UI text on dark backgrounds |
| `tower_shadow` | Tower Shadow Bitmap | `res://assets/fonts/tower_shadow_font.fnt` | `res://assets/fonts/tower_shadow_font.png` | Dark engraved text for light panels/parchment backgrounds |
| `cinzel` | Cinzel Variable | `res://assets/fonts/Cinzel_Variable.ttf` | - | Titles, section headers, screen titles, location names, boss names and dramatic short labels |
| `eb_garamond` | EB Garamond Variable | `res://assets/fonts/EB_Garamond_Variable.ttf` | - | Narrative text, dialogue, books, lore, item descriptions and quest descriptions |

Previews live in `res://assets/fonts/previews/`.

Typography roles are centralized in `res://scripts/ui_theme.gd`.

- `FontTitle` / `DisplayTitle` / `FontSectionHeader`: Cinzel.
- `FontNarrativeBody` / `FontDialogue` / `FontBookText` / `FontItemDescription`: EB Garamond.
- `FontSmallUI`: existing readable compact UI font.

Reusable LabelSettings live next to the fonts:

- `title_label_settings.tres`
- `section_header_label_settings.tres`
- `narrative_label_settings.tres`
- `dialogue_label_settings.tres`
- `book_text_label_settings.tres`
