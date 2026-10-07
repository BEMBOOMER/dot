# DOT design system (v2, replaces the brutalist direction in CONCEPT.md)

Reference feel: mouse.ly, Apple utility apps. Clean, quiet, lots of air, one accent. DOT has its own identity; it does NOT use the RJH "Golven" house style and NOT the paper/ink brutalism (no hard offset shadows, no thick borders, no noise).

## Principles
- Whitespace does the work. One primary action per screen, everything else is quiet text or ghost buttons.
- One accent color, used only for the primary action, the selected state and the dots.
- Depth comes from soft shadows and the dots, never from outlines.
- Motion is short and springy (200-350 ms, easeOutCubic / gentle spring). Ambient loops are slow and subtle and stop when inactive or reduced motion.

## Color tokens
| token | light | dark |
|---|---|---|
| bg | #F7F7F8 | #0B0B0D |
| surface (cards, sheets) | #FFFFFF | #16161A |
| surfaceMuted (inputs, chips, secondary buttons) | #EFEFF2 | #222228 |
| hairline (dividers only) | #E6E6EA | #2A2A31 |
| text | #0E0E10 | #F4F4F6 |
| textSecondary | #6E6E76 | #9A9AA3 |
| accent ("DOT blue") | #3D5AFE | #6C83FF |
| onAccent | #FFFFFF | #FFFFFF |
| success (connected, received) | #1DB954 | #34D27A |
| warning (waiting) | #F5A524 | #F7B84B |
| danger (failed, delete) | #E5484D | #FF6369 |

Status is always a small 8px dot + text (never color alone).

## Typography
Single family: **Inter** (variable, bundled at assets/fonts/Inter.ttf, family name `Inter`). No other fonts.
- Display (welcome headline): 34/40, weight 650, letter-spacing -0.8
- Title (screen titles, AppBar): 22/28, weight 650, letter-spacing -0.4
- Headline (card title): 16/22, weight 600, -0.2
- Body: 15/22, weight 400
- Caption/meta (origin, time, status): 13/18, weight 500, textSecondary
- Button: 15, weight 600
No all-caps labels, no wide tracking.

## Shape & elevation
- Radius: cards 18, sheets 24 (top), inputs 12, chips & buttons fully rounded (pill), QR card 20.
- Shadow (light): `0 1px 2px rgba(0,0,0,0.04), 0 6px 20px rgba(0,0,0,0.06)`. Dark: no shadow, surface contrast only.
- Borders: none, except 1px hairline dividers in lists/settings.
- Spacing scale: 4, 8, 12, 16, 24, 32, 48. Screen padding 20 (phone), 32 (desktop). Max content width 640 on desktop single-column screens.

## Components
- **Primary button**: pill, accent fill, onAccent text, height 52 (phone) / 44 (desktop). Pressed: scale 0.98 + slightly darker, 120 ms.
- **Secondary button**: pill, surfaceMuted fill, text color. **Ghost**: text only, accent.
- **Card (item)**: surface, radius 18, soft shadow, padding 16. Row 1: small type icon (outlined, 18px, textSecondary) + type label (caption) ... status (8px dot + caption) right. Row 2: title (headline, max 2 lines). Row 3: origin and relative time (caption). File items: thin 3px progress bar in accent at the bottom while sending.
- **Chips (filters)**: pill, surfaceMuted; selected = accent fill + onAccent text. No checkmark.
- **Search**: surfaceMuted fill, radius 12, no border, leading search icon in textSecondary.
- **Add button**: 60px accent circle with a plus (phone, bottom right, soft accent glow shadow). On desktop: a "Toevoegen" pill button in the header plus Cmd+N.
- **Sheets/dialogs**: surface, radius 24, drag handle on phone.
- **Settings**: grouped inset list (iOS-like), hairline dividers, switches in accent.
- Icons: Material Symbols Rounded / outlined style, 20-22px, textSecondary unless active.

## The dots (signature)
- Smooth glossy spheres: radial gradient from a lighter tint at top-left (30%,25%) to the base color, a soft specular highlight, and a very soft blurred contact shadow below. No outlines.
- Colors: local device dot = accent; peer dot = text color at 90% (ink in light, near white in dark). Connected: both dots get a subtle success-tinted rim glow for 600 ms then settle. Failed: peer dot desaturates to textSecondary.
- Sizes: welcome hero 140; workspace stage height 150 (phone) / 190 (desktop), dot diameter 64 / 84; travelling "send" dot 14.
- Status behaviour as in CONCEPT.md (searching drift, pairing pull together, connected short bounce, syncing travelling dot, offline further apart, failed stops).

## App icon
Accent sphere (same shading as the dots) centered on a white rounded square (macOS) / white adaptive background (Android). No text, no logo.

## Copy tone
Dutch, short, friendly, plain. No em-dashes, no emoji, no exclamation marks.
