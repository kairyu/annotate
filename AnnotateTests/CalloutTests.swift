import AppKit
import Foundation
import Testing
import AnnotateCore
@testable import Annotate

/// Text callouts: the real behind-window material plate, and the promise that a
/// label renders every word it was given while staying fully on screen. A
/// teaching annotation that silently loses the end of its own instruction is
/// worse than no annotation at all.
@MainActor
struct CalloutTests {
    static let screen = ScreenDescriptor(
        displayID: 1,
        screen: Screen(index: 0, frame: Rect(x: 0, y: 0, width: 1200, height: 800), scale: 2, primary: true)
    )

    // MARK: - Labels grow, and never leave the screen

    static let wideScreen = ScreenDescriptor(
        displayID: 1,
        screen: Screen(index: 0, frame: Rect(x: 0, y: 0, width: 2056, height: 1290), scale: 2, primary: true)
    )

    @Test("a text callout is a real behind-window material plate")
    func freshInkTextUsesARealBehindWindowMaterialCallout() throws {
        let provider = FreshInkPathProvider()
        let annotation = Annotation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, shape: .text(at: Point(x: 300, y: 220), text: "smooth callout"), color: .role(.accent), ttlSeconds: 0)
        let host = NSView()

        // The label background is a REAL macOS material (NSVisualEffectView),
        // hosted as a subview of the overlay's contentView — not a hand-rolled
        // CAShapeLayer wash. .hudWindow + .behindWindow is the mode the
        // material spike (fd31ac5, discarded) confirmed genuinely blurs
        // content behind the click-through overlay.
        let root = try #require(provider.layers(for: annotation, on: Self.screen, host: host).first as? FreshInkAnnotationLayer)
        let effectView = try #require(root.calloutEffectView)

        #expect(host.subviews.contains(effectView))
        #expect(effectView.material == .hudWindow)
        #expect(effectView.blendingMode == .behindWindow)
        #expect(effectView.state == .active)
        #expect(effectView.layer?.masksToBounds ?? false)
        #expect((effectView.layer?.cornerRadius ?? 0) > 0)
        // The entrance/exit animation target IS the effect view's own layer.
        #expect(root.calloutLayer === effectView.layer)
    }

    /// Replaces an earlier test that pinned the OPPOSITE behaviour — a hard cap
    /// of three lines and 260pt, with an ellipsis past it. That cap was the bug:
    /// a long instruction lost its own ending. A long label now grows and stays
    /// whole; the screen is the only limit.
    @Test("a long callout grows instead of being capped")
    func freshInkTextGrowsALongCalloutInsteadOfCappingIt() throws {
        let provider = FreshInkPathProvider()
        let long = String(repeating: "fresh ink annotation ", count: 30)
        let annotation = Annotation(id: UUID(), shape: .text(at: Point(x: 300, y: 220), text: long), color: .role(.accent), ttlSeconds: 0)

        let root = try #require(provider.layers(for: annotation, on: Self.screen).first as? FreshInkAnnotationLayer)
        let text = try #require(root.calloutLayer?.sublayers?.compactMap { $0 as? CATextLayer }.first)
        let rendered = try #require(text.string as? NSAttributedString).string

        #expect(rendered == long, "the label lost words")
        #expect(!rendered.hasSuffix("…"))
        // Grew past the old 3-line / 260pt cap, but stayed inside the display.
        #expect(text.frame.height > 3 * 20)
        let callout = try #require(root.calloutLayer)
        let inset = CGFloat(Tokens.calloutScreenInset)
        #expect(CGRect(x: 0, y: 0, width: 1200, height: 800).insetBy(dx: inset - 0.5, dy: inset - 0.5).contains(callout.frame))
    }

    // MARK: - Styles

    /// `card` tints a live blur, which is what makes it part of the interface it
    /// is teaching — and a piece of interface is the one thing narration burned
    /// into a recording must not look like. Recolouring the plate could not fix
    /// that, so `caption` removes it: the words go straight onto the screen,
    /// carried by an outline and a shadow in their own casing colour.
    @Test("a caption has no plate, and its words carry their own outline")
    func aCaptionHasNoPlateAndCarriesItsOwnOutline() throws {
        let provider = FreshInkPathProvider()

        func render(_ color: ColorValue, _ style: CalloutStyle) throws -> FreshInkAnnotationLayer {
            let annotation = Annotation(id: UUID(), shape: .text(at: Point(x: 300, y: 220), text: "take 3"),
                                        color: color, ttlSeconds: 0, style: style)
            return try #require(provider.layers(for: annotation, on: Self.screen, host: NSView()).first as? FreshInkAnnotationLayer)
        }

        func matches(_ color: CGColor?, _ expected: P3Color, alpha: Double = 1) -> Bool {
            let parts = (color?.components ?? []).map(Double.init)
            guard parts.count == 4 else { return false }
            return abs(parts[0] - expected.red) < 0.001 && abs(parts[1] - expected.green) < 0.001
                && abs(parts[2] - expected.blue) < 0.001 && abs(parts[3] - alpha) < 0.001
        }

        let caption = try render(.role(.ink), .caption)
        let plate = try #require(caption.calloutEffectView)
        // No plate: the material is masked out, there is no tint layer and no
        // border. The view itself SURVIVES, because its frame is how the rest of
        // the overlay knows where this label is.
        #expect(plate.maskImage != nil)
        #expect(caption.calloutLayer?.sublayers?.contains { $0.name == "callout-tint" } != true)
        #expect(plate.layer?.borderWidth == 0)
        // Nothing clipped to the plate's bounds — the outline and its shadow
        // bleed past the glyphs, and that bleed is the legibility.
        #expect(plate.layer?.masksToBounds == false)

        // Two text layers, outline BEHIND fill: Core Text strokes after filling,
        // so one layer with a heavy stroke loses the glyph entirely.
        let sublayers = try #require(caption.calloutLayer?.sublayers)
        let outline = try #require(sublayers.first { $0.name == "callout-outline" } as? CATextLayer)
        let fill = try #require(caption.calloutTextLayer)
        let outlineIndex = try #require(sublayers.firstIndex(of: outline))
        let fillIndex = try #require(sublayers.firstIndex(of: fill))
        #expect(outlineIndex < fillIndex)
        #expect(outline.frame == fill.frame)

        // `ink` is PINNED to `inkDark` for a caption — near-white words with a
        // dark casing, the canonical caption. Unpinned, `ink` flips with the
        // system appearance, which is how one call recorded light on one machine
        // and dark on another.
        #expect(matches(fill.foregroundColor, Tokens.inkDark.color))
        #expect(!matches(fill.foregroundColor, Tokens.inkLight.color))
        let outlineAttributes = try #require(outline.string as? NSAttributedString)
            .attributes(at: 0, effectiveRange: nil)
        // A POSITIVE strokeWidth strokes without filling: that is the back layer.
        #expect((outlineAttributes[.strokeWidth] as? Double) == Tokens.captionStrokeWidth)
        let stroke = try #require(outlineAttributes[.strokeColor] as? NSColor)
        #expect(matches(stroke.cgColor, P3Color(red: 0, green: 0, blue: 0)))
        #expect(outline.shadowOpacity == Float(Tokens.captionShadowOpacity))

        // Dark words get a LIGHT casing, by the same luminance split that gives a
        // pen stroke its halo — otherwise a black caption outlined in black is
        // just a thicker black caption.
        let darkWords = try render(.hex(HexColor(red: 0x10, green: 0x10, blue: 0x14)), .caption)
        let darkOutline = try #require(darkWords.calloutLayer?.sublayers?
            .first { $0.name == "callout-outline" } as? CATextLayer)
        let darkAttributes = try #require(darkOutline.string as? NSAttributedString)
            .attributes(at: 0, effectiveRange: nil)
        let darkStroke = try #require(darkAttributes[.strokeColor] as? NSColor)
        #expect(matches(darkStroke.cgColor, P3Color(red: 1, green: 1, blue: 1)))

        // And the card is exactly what it always was: a tinted plate, chalk
        // words, one text layer, no outline.
        let card = try render(.role(.accent), .card)
        let tint = try #require(card.calloutLayer?.sublayers?.first { $0.name == "callout-tint" })
        #expect(matches(tint.backgroundColor, Tokens.accent.color, alpha: Tokens.calloutTintAlpha))
        #expect(matches(try #require(card.calloutTextLayer).foregroundColor, Tokens.chalk))
        #expect(card.calloutEffectView?.maskImage == nil)
        #expect(card.calloutLayer?.masksToBounds == true)
        #expect(card.calloutLayer?.sublayers?.contains { $0.name == "callout-outline" } != true)
    }

    /// A mark's label can be a caption too — but it must stay tied to its mark,
    /// which is the one thing a plate-less label risks losing. The card does it
    /// with a tint of the mark's colour; a caption does it by painting the WORDS
    /// that colour, and by refusing the appearance pin a standalone caption gets:
    /// `ink` flips for the loop, so pinning only the words would leave a dark
    /// loop carrying near-white words.
    @Test("a caption label takes its mark's own colour, unpinned", arguments: [true, false])
    func aCaptionLabelTakesItsMarksColour(_ isCircle: Bool) throws {
        let provider = FreshInkPathProvider()
        let shape: AnnotationShape = isCircle
            ? .circle(Rect(x: 300, y: 220, width: 60, height: 60), label: "Join the call", weight: .regular)
            : .arrow(from: Point(x: 200, y: 160), to: Point(x: 300, y: 220), label: "Join the call", weight: .regular)

        func fill(_ color: ColorValue, _ style: CalloutStyle) throws -> CGColor? {
            let annotation = Annotation(id: UUID(), shape: shape, color: color, ttlSeconds: 0, style: style)
            let root = try #require(provider.layers(for: annotation, on: Self.screen, host: NSView()).first as? FreshInkAnnotationLayer)
            return try #require(root.calloutTextLayer).foregroundColor
        }

        func matches(_ color: CGColor?, _ expected: P3Color) -> Bool {
            let parts = (color?.components ?? []).map(Double.init)
            guard parts.count == 4 else { return false }
            return abs(parts[0] - expected.red) < 0.001 && abs(parts[1] - expected.green) < 0.001
                && abs(parts[2] - expected.blue) < 0.001
        }

        // The words are the mark's colour, so the label still belongs to it.
        #expect(matches(try fill(.role(.warn), .caption), Tokens.warn.color))
        // A card label is chalk whatever the mark's colour: the plate carries it.
        #expect(matches(try fill(.role(.warn), .card), Tokens.chalk))
        // `ink` is NOT pinned here — it resolves the same way the loop's ink does,
        // so the two can never disagree about which end of the palette they are on.
        let inkLabel = try fill(.role(.ink), .caption)
        let appearanceIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #expect(matches(inkLabel, appearanceIsDark ? Tokens.inkDark.color : Tokens.inkLight.color))
    }

    /// A label must render every word it was given.
    ///
    /// It did not: the plate was capped at a fixed three lines and anything
    /// longer was cut with an ellipsis, so an agent explaining a step in a
    /// sentence silently lost the end of its own instruction — the one thing a
    /// teaching annotation cannot do.
    @Test("a label is never truncated")
    func aLabelIsNeverTruncated() throws {
        let provider = FreshInkPathProvider()
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 2056, height: 1290))
        let long = "Open the scheme editor, choose Run on the left, then switch to the Diagnostics tab and enable the address sanitizer before you build again"

        let annotation = Annotation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                                    shape: .text(at: Point(x: 1028, y: 645), text: long),
                                    color: .role(.ink), ttlSeconds: 0)
        let root = try #require(provider.layers(for: annotation, on: Self.wideScreen, host: host).first as? FreshInkAnnotationLayer)
        let label = try #require(root.calloutTextLayer)

        let rendered = try #require(label.string as? NSAttributedString).string
        #expect(!rendered.contains("…"), "the label was truncated")
        #expect(rendered == long, "the label must render every word it was given")
    }

    /// However far a label grows, it must stay fully on screen — and not hug the
    /// edge. A plate flush to the bezel reads as clipped even when it isn't.
    ///
    /// This and the test below used to be one loop over ten anchors that skipped
    /// any anchor producing no layer. The skip silently swallowed the two
    /// deliberately off-display anchors, so a quarter of the cases asserted
    /// nothing at all. Split, each group states its own claim out loud:
    /// on-display anchors must render AND land inset, off-display anchors must
    /// render nothing.
    @Test("every on-display anchor lands its label fully on screen, with an inset")
    func aLabelAlwaysLandsFullyOnScreenWithAnInset() throws {
        let provider = FreshInkPathProvider()
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 2056, height: 1290))
        let long = String(repeating: "an unusually wordy instruction that keeps going ", count: 6)
        let inset = CGFloat(Tokens.calloutScreenInset)
        let bounds = CGRect(x: 0, y: 0, width: 2056, height: 1290)

        // Every corner and every edge midpoint of the display.
        let points = [Point(x: 0, y: 0), Point(x: 2056, y: 0), Point(x: 0, y: 1290), Point(x: 2056, y: 1290),
                      Point(x: 1028, y: 0), Point(x: 1028, y: 1290), Point(x: 8, y: 645), Point(x: 2048, y: 645)]

        for (index, point) in points.enumerated() {
            let annotation = Annotation(id: UUID(uuidString: "00000000-0000-0000-0000-0000000002\(String(format: "%02d", index))")!,
                                        shape: .text(at: point, text: long), color: .role(.ink), ttlSeconds: 0)
            let root = try #require(provider.layers(for: annotation, on: Self.wideScreen, host: host).first as? FreshInkAnnotationLayer,
                                    "no callout rendered at \(point)")
            let frame = try #require(root.calloutLayer).frame

            #expect(bounds.insetBy(dx: inset - 0.5, dy: inset - 0.5).contains(frame),
                    "callout at \(point) sits at \(frame) — outside the screen or hugging its edge")
        }
    }

    /// The other half of the same contract, and the half the original loop
    /// silently skipped: an anchor that is nowhere near this display draws
    /// nothing on it. The label is nudged back on screen when it merely
    /// overhangs — it is not dragged back from another monitor entirely.
    @Test("an anchor well outside the display draws nothing on it")
    func anAnchorWellOutsideTheDisplayDrawsNothingOnIt() {
        let provider = FreshInkPathProvider()
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 2056, height: 1290))
        let long = String(repeating: "an unusually wordy instruction that keeps going ", count: 6)

        for (index, point) in [Point(x: -400, y: -400), Point(x: 3000, y: 2000)].enumerated() {
            let annotation = Annotation(id: UUID(uuidString: "00000000-0000-0000-0000-0000000003\(String(format: "%02d", index))")!,
                                        shape: .text(at: point, text: long), color: .role(.ink), ttlSeconds: 0)
            #expect(provider.layers(for: annotation, on: Self.wideScreen, host: host).isEmpty,
                    "an anchor at \(point) is off this display and must draw nothing on it")
        }
    }

    /// Growth is bounded by the SCREEN, not by an arbitrary line count: a label
    /// long enough to overrun the display must still fit inside it.
    @Test("a label too long for the screen is bounded by the screen")
    func aLabelTooLongForTheScreenIsBoundedByTheScreen() throws {
        let provider = FreshInkPathProvider()
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 2056, height: 1290))
        let enormous = String(repeating: "word ", count: 4000)
        let inset = CGFloat(Tokens.calloutScreenInset)

        let annotation = Annotation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                                    shape: .text(at: Point(x: 1028, y: 645), text: enormous),
                                    color: .role(.ink), ttlSeconds: 0)
        let root = try #require(provider.layers(for: annotation, on: Self.wideScreen, host: host).first as? FreshInkAnnotationLayer)
        let callout = try #require(root.calloutLayer)

        #expect(callout.frame.height <= 1290 - 2 * inset + 0.5)
        #expect(callout.frame.width <= 2056 - 2 * inset + 0.5)
        #expect(callout.frame.minX >= inset - 0.5)
        #expect(callout.frame.minY >= inset - 0.5)
    }
}
