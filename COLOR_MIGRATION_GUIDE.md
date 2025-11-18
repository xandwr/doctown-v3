# Color Migration Guide

## Old to New Color Mappings

### Background Colors
- `bg-void` → `bg-bg-primary` (#0a0a0a)
- `bg-concrete` → `bg-bg-secondary` (#121212) or `bg-bg-tertiary` (#1a1a1a)
- `bg-fog` → `bg-bg-elevated` (#1e1e1e)
- `bg-ash` → `bg-hover-bg` (#252525)

### Border Colors
- `border-fog` → `border-border-subtle` (#282828) or `border-border-default` (#333333)
- `border-ash` → `border-border-strong` (#404040)
- `border-corpse` → (context dependent - use semantic status colors)
- `border-rust` → (use language colors or warning)

### Text Colors
- `text-whisper` → `text-text-primary` (#e8e8e8)
- `text-echo` → `text-text-secondary` (#a8a8a8)
- `text-shadow` → `text-text-tertiary` (#707070)
- `text-corpse` → (context dependent - use primary action or status colors)
- `text-rust` → (use warning or language colors)
- `text-decay` → `text-danger` or `text-status-failed`

### Action/Interactive Colors
- `bg-corpse/20 text-corpse border-corpse/40` → `bg-primary/10 text-primary border-primary/30`
- `hover:text-corpse` → `hover:text-primary`
- `hover:border-ash` → `hover:border-border-strong`

### Status Colors (Direct replacement)
- Use semantic: `status-building`, `status-valid`, `status-public`, `status-failed`

### Language Colors
- All languages now have dedicated `lang-*` colors
- e.g., `text-rust` for Rust → `text-lang-rust`

## Conversion Pattern
```
Old: bg-concrete/30 border border-fog hover:border-ash
New: bg-bg-secondary border border-border-default hover:border-border-strong
```
