// The foreground mask Vision finds in an image, as a PNG the size of the
// image. Used by hero_plate.py: `swift docs/art/subject_mask.swift in.png out.png`
import CoreImage
import Foundation
import Vision

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2])
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(url: source)
try handler.perform([request])
guard let observation = request.results?.first else { fatalError("no subject in \(source.path)") }
let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
try CIContext().writePNGRepresentation(
    of: CIImage(cvPixelBuffer: mask), to: target, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
)
