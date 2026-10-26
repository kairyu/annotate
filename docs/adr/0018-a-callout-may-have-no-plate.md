# 18. A callout may have no plate, when its words are being recorded

- Status: Accepted
- Date: 2026-10-19

## Context

ADR 0007 made the callout plate a real macOS material, and turned down "no
plate, outlined text only" because per-glyph outlining is unreadable for a
sentence. Both of those still hold.

What 0007 did not have was a use case where the plate's best quality is its
defect. Narration burned into a screen recording is that case: a plate that
reads as native chrome reads, on video, as a piece of the product's own UI that
happens to contain words, and a viewer takes it for part of the app being
demonstrated.

Recolouring the plate cannot fix this, and the three attempts are measured
rather than assumed. A dark hex cannot darken `Tokens.calloutTintAlpha` over a
live blur; the label was the constant `Tokens.chalk`, so a light plate rendered
near-white on near-white; and the `ink` role inverts with the system appearance,
so one call recorded differently on two machines. The plate was the problem, not
its colour.

## Decision

`CalloutStyle` travels on the wire with two values: `card` — ADR 0007's material
plate, still the default — and `caption`, which has no plate. Every command that
carries words offers it: `text`, and a **labelled** `circle` or `arrow`.

A caption keeps its `NSVisualEffectView` and removes only the material, with a
transparent `maskImage`. The view is how the rest of the overlay knows where a
label is — ADR 0007's own consequence, that the interaction monitor and the wipe
union the callout's *view frame*, is the reason. Deleting the view would mean
teaching `OverlayEngine`'s hit area, obstacle set and wipe, plus
`relayoutCallout`, a second way to answer that question in order to draw less.

Legibility moves into the **casing**: an outline text layer behind the fill, with
a shadow in the same casing colour. That is the pen's own halo mechanism
(DESIGN.md §2) applied to type, so a caption carries its contrast the way every
other primitive does.

## Consequences

- 0007's rejected alternative is now reachable, and its reasoning survives as
  guidance rather than prohibition: `card` remains the default, and DESIGN.md §6
  and the tool descriptions both say to keep it for anything that wraps to a
  paragraph. A caption is for one line.
- The overlay's "single exception that blurs" **narrows** rather than widens. A
  caption samples nothing behind it, which returns the callout to the rule 0007
  carved itself out of.
- Two Core Animation facts are load-bearing, and both were measured on screen.
  `maskImage` hides the material *only* — sublayers go on drawing, verified by
  diffing captures of the same region. And one text layer cannot carry fill and
  outline together: Core Text strokes *after* filling, so `strokeWidth: -12`
  rendered the phrase with zero fill pixels. CSS says `paint-order: stroke fill`;
  Core Animation has no equivalent, so paint order is expressed as two layers.
- `ink` is pinned against the appearance flip for a STANDALONE caption, so a
  recording does not depend on the machine's light/dark setting — but not for a
  label on a mark, whose ink flips with the mark's own. A pinned label on an
  unpinned loop is a label that visibly does not match its mark.
- No generator is involved, so ADR 0004's pixel contract is untouched, and the
  growth rules remain exactly ADR 0012's.
- A caption needs its **own metrics**, which narrows ADR 0015's "one size":
  22 pt and a 520 pt preferred line, against the card's 15 pt and 260 pt
  (`Tokens.metrics(for:)`). Both card numbers measured wrong for the job — 15 pt
  read as secondary to the app being demonstrated, and 260 pt wrapped one line of
  narration onto three. This is not an API size knob: a caller picks a style, and
  the style carries the measurements. Note that `captionStrokeWidth` is a
  percentage of point size, so a larger caption gets a proportionally heavier
  casing for free.

## Rejected alternatives

- **An opaque plate in the caller's colour.** Built first and then removed. It
  produces a caption-coloured card, which is still a card — the measurements
  above are what it taught us.
- **Dropping the effect view for a plain `CALayer` frame carrier.**
  Structurally tidier, and it duplicates "where is this label" across four
  consumers to render less.
- **A third value, keeping the opaque plate as well.** Two names for neighbouring
  looks that an agent then has to choose between, for a variant nothing asked
  for.

## See also

- `docs/DESIGN.md` §6 — the caption's outline, shadow and when not to use it.
- `docs/PROTOCOL.md` — `style`, and how it differs on a labelled mark.
- ADR 0007 — the material plate this amends.
- ADR 0012 — sizing and growth, unchanged.
