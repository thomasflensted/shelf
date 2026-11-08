import AppKit

let source = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

guard let image = NSImage(contentsOfFile: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("Could not read \(source)") }

context.interpolationQuality = .high
context.addPath(CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
context.clip()
context.draw(image, in: tile)

guard let masked = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: masked).representation(using: .png, properties: [:])
else { fatalError("Could not render icon") }
try png.write(to: URL(fileURLWithPath: output))
