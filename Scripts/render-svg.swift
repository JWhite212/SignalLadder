// Scripts/render-svg.swift — draw an SVG to a square PNG with a transparent
// background, using WebKit. Called by Scripts/make-icon.sh; it is not part of
// the app or the Swift package.
//
// Why WebKit, and not something simpler. No SVG tool ships with macOS, so the
// options are the ones the system already has. Measured on 2026-09-30 on
// macOS 26.7.1, with docs/assets/logo.svg:
//   - qlmanage -t draws the SVG correctly, drop shadow included, but the PNG it
//     writes is opaque: all four corners read (255, 255, 255, 255). An icon
//     made from it would sit on a white square.
//   - NSImage loads the SVG and draws its shapes, but not the shadow, which
//     is an feDropShadow filter: every row below the body was fully
//     transparent, where WebKit's render has the shadow for another 60 px.
//   - WebKit draws the whole file, and a web view with no background paints
//     nothing where the SVG paints nothing, so the corners stay transparent.
//
// Usage: render-svg <in.svg> <out.png> <pixels> [<body-pixels>]
//
// With <body-pixels> the tool also checks the picture before writing success:
// the corners must be transparent, the centre opaque, and the solid part must
// be that many pixels square and centred. WebKit is the part of this that can
// change between macOS releases, so a render that has gone blank, opaque or
// off the grid fails here instead of reaching a checked-in .icns.
//
// Exit: 0 written (and, if asked, checked), 1 failed.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WebKit

func fail(_ message: String) -> Never {
    fflush(stdout)   // so the measurements print before the reason they were taken
    FileHandle.standardError.write(Data("render-svg: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 || arguments.count == 5,
      let pixels = Int(arguments[3]), pixels > 0,
      arguments.count == 4 || Int(arguments[4]) != nil
else {
    fail("usage: render-svg <in.svg> <out.png> <pixels> [<body-pixels>]")
}
let expectedBody: Int? = arguments.count == 5 ? Int(arguments[4]) : nil

guard let svg = try? String(contentsOfFile: arguments[1], encoding: .utf8) else {
    fail("cannot read \(arguments[1])")
}

// CSS width and height override the SVG element's own attributes, so the
// picture fills the page whatever size the file declares.
let html = """
<!doctype html>
<meta charset="utf-8">
<style>
  html, body { margin: 0; background: transparent; overflow: hidden; }
  svg { display: block; width: \(pixels)px; height: \(pixels)px; }
</style>
\(svg)
"""

final class Loader: NSObject, WKNavigationDelegate {
    var finished: () -> Void = {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        fail("load failed: \(error.localizedDescription)")
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)   // no Dock icon, no menu bar

let size = CGFloat(pixels)
let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: size, height: size),
                        configuration: WKWebViewConfiguration())
// Private, but long-standing and widely relied on: without it the web view
// paints white under the page. If a future macOS drops it, the corner check
// below fails loudly rather than producing an opaque icon.
webView.setValue(false, forKey: "drawsBackground")

let window = NSWindow(contentRect: webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.isOpaque = false
window.backgroundColor = .clear
window.contentView = webView

let loader = Loader()
webView.navigationDelegate = loader

// Draws into a fixed pixel size and colour space, so the result does not
// depend on whether this Mac's screen is Retina.
func flatten(_ image: NSImage) -> [UInt8] {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("the snapshot has no bitmap")
    }
    var buffer = [UInt8](repeating: 0, count: pixels * pixels * 4)
    // The context draws straight into the buffer, so it is used only while the
    // buffer's address is guaranteed: inside this closure.
    buffer.withUnsafeMutableBytes { bytes in
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: bytes.baseAddress, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: colourSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { fail("cannot create a \(pixels) px bitmap") }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return buffer
}

func write(_ buffer: inout [UInt8], to path: String) {
    // makeImage copies the pixels, so the image outlives the closure safely.
    let made: CGImage? = buffer.withUnsafeMutableBytes { bytes in
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: bytes.baseAddress, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: colourSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return context.makeImage()
    }
    guard let image = made,
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot prepare \(path) for writing") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(path)") }
}

func check(_ buffer: [UInt8], body: Int) {
    func rgba(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * pixels + x) * 4
        return (buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3])
    }
    let last = pixels - 1
    for (x, y) in [(0, 0), (last, 0), (0, last), (last, last)] {
        let corner = rgba(x, y)
        guard corner.a == 0 else { fail("corner (\(x), \(y)) is not transparent: alpha \(corner.a)") }
    }
    let centre = rgba(pixels / 2, pixels / 2)
    guard centre.a == 255 else { fail("the centre is not opaque: alpha \(centre.a)") }

    // The solid body: pixels that are (all but) fully opaque. The shadow is
    // never that opaque, so it does not widen the box.
    var minX = pixels, minY = pixels, maxX = -1, maxY = -1
    for y in 0..<pixels {
        for x in 0..<pixels where buffer[(y * pixels + x) * 4 + 3] >= 250 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { fail("the picture is blank") }
    let width = maxX - minX + 1, height = maxY - minY + 1
    print("centre rgba(\(centre.r), \(centre.g), \(centre.b), \(centre.a)); corners transparent")
    print("solid body x \(minX)...\(maxX), y \(minY)...\(maxY): \(width) x \(height) px")
    guard abs(width - body) <= 2, abs(height - body) <= 2 else {
        fail("the solid body is \(width) x \(height) px, expected \(body) x \(body)")
    }
    let margin = (pixels - body) / 2
    guard abs(minX - margin) <= 2, abs(minY - margin) <= 2 else {
        fail("the body starts at (\(minX), \(minY)), expected (\(margin), \(margin))")
    }
}

loader.finished = {
    // didFinish fires when the document has loaded, not when the SVG's filters
    // have been painted; a short wait before the snapshot is the cheap way to
    // be sure of the shadow.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: size, height: size)
        configuration.snapshotWidth = NSNumber(value: pixels)
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image else { fail("snapshot failed: \(error?.localizedDescription ?? "no image")") }
            var buffer = flatten(image)
            if let expectedBody { check(buffer, body: expectedBody) }
            write(&buffer, to: arguments[2])
            print("wrote a \(pixels) x \(pixels) PNG with alpha")
            exit(0)
        }
    }
}

// The caller bounds the whole run as well; this is the failure message.
DispatchQueue.main.asyncAfter(deadline: .now() + 45) { fail("timed out waiting for WebKit") }

webView.loadHTMLString(html, baseURL: nil)
application.run()
