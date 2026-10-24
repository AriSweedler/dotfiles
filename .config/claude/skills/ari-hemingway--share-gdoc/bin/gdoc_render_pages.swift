// Render every page of a PDF to PNG with PDFKit, no third-party tools.
// Usage: swift-run gdoc_render_pages.swift <in.pdf> <outdir> <scale>
// Prints one output path per page on stdout.
import Foundation
import PDFKit
import AppKit

let args = CommandLine.arguments
// --help exits before any PDF is opened: the no-side-effect probe swift-cache bench uses.
if args.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
    print("usage: gdoc_render_pages.swift <in.pdf> <outdir> <scale>\n  Renders every page of the PDF to <outdir>/page-N.png and prints each path.")
    exit(0)
}
guard args.count == 4, let scale = Double(args[3]), scale > 0 else {
    FileHandle.standardError.write("usage: gdoc_render_pages.swift <in.pdf> <outdir> <scale>\n".data(using: .utf8)!)
    exit(2)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("cannot open pdf | pdf='\(args[1])'\n".data(using: .utf8)!)
    exit(1)
}
let outdir = args[2]
try? FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
for index in 0..<doc.pageCount {
    guard let page = doc.page(at: index) else { continue }
    let bounds = page.bounds(for: .mediaBox)
    let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
    let image = page.thumbnail(of: size, for: .mediaBox)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let out = "\(outdir)/page-\(index + 1).png"
    do {
        try png.write(to: URL(fileURLWithPath: out))
        print(out)
    } catch {
        FileHandle.standardError.write("cannot write page | out='\(out)'\n".data(using: .utf8)!)
        exit(1)
    }
}
