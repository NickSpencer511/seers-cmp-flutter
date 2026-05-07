## 2.0.5
- Banner layout and preference center fixes
- Consistent font sizes across all display styles

## 2.0.4
- Font size clamped to 10–16px range matching dashboard dropdown
- Preference panel: 92% height sheet with rounded top corners
- prefFs = max(fs, 12) for readable preference center text
- Typeface support: arial/inter/spezia → sans-serif, serif, monospace, cursive
- padScale fixed to 1.0 for CSS-like spacing consistency

## 2.0.3
- Fixed CDN URL from cdn.consents.dev to cdn.seersco.com
- Fixed regionSelection string/int type mismatch from API
## 2.0.2\n- Latest banner updates
## 2.0.0
- Complete redesign: pixel-perfect match to frontend MobileDefaultBanner
- All colors, font sizes, paddings, border radii exactly mirror the Vue preview
- Font size system: titleFs=fs+2, catNameFs=fs+1, catBodyFs=fs-1, arrowFs=fs*0.75
- All container paddings: 12px on all sides
- Preference panel: correct order, sticky footer, accordion categories with toggle
- Button shapes: default(4px), flat(0), rounded(20px), stroke(transparent+border)
- stk-btn last-of-type margin-bottom:0
- pref-body uses bodyFs (fs), not fs-1
