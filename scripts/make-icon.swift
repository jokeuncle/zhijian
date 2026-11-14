import AppKit
import Foundation

let output=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let image=NSImage(size:NSSize(width:pixels,height:pixels))
        image.lockFocus()
        let factor=CGFloat(pixels)/1024
        let transform=NSAffineTransform(); transform.scale(by:factor); transform.concat()
        NSColor(srgbRed:0.23,green:0.37,blue:0.28,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:24,y:24,width:976,height:976),xRadius:205,yRadius:205).fill()
        NSColor(srgbRed:0.95,green:0.95,blue:0.89,alpha:1).setStroke()
        let book=NSBezierPath(); book.lineWidth=30; book.lineJoinStyle = .round; book.lineCapStyle = .round
        book.move(to:NSPoint(x:510,y:287)); book.curve(to:NSPoint(x:252,y:340),controlPoint1:NSPoint(x:414,y:345),controlPoint2:NSPoint(x:335,y:363))
        book.line(to:NSPoint(x:252,y:720)); book.curve(to:NSPoint(x:510,y:663),controlPoint1:NSPoint(x:345,y:745),controlPoint2:NSPoint(x:420,y:706)); book.close(); book.stroke()
        book.removeAllPoints(); book.move(to:NSPoint(x:514,y:287)); book.curve(to:NSPoint(x:772,y:340),controlPoint1:NSPoint(x:610,y:345),controlPoint2:NSPoint(x:689,y:363))
        book.line(to:NSPoint(x:772,y:720)); book.curve(to:NSPoint(x:514,y:663),controlPoint1:NSPoint(x:679,y:745),controlPoint2:NSPoint(x:604,y:706)); book.close(); book.stroke()
        let stem=NSBezierPath(); stem.lineWidth=20; stem.lineCapStyle = .round
        stem.move(to:NSPoint(x:512,y:460)); stem.line(to:NSPoint(x:512,y:600)); stem.stroke()
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        let data=bitmap.representation(using:.png,properties:[:])!
        try data.write(to:output.appendingPathComponent("icon_\(size)x\(size)\(scale==2 ? "@2x":"").png"))
    }
}
