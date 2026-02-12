import SwiftUI

struct FlowyBottomShape: Shape {
    var curveDepth: CGFloat = 46

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Top rectangle
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - curveDepth))

        // Curved bottom
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 0.75, y: rect.maxY)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - curveDepth),
            control: CGPoint(x: rect.maxX * 0.25, y: rect.maxY)
        )

        p.closeSubpath()
        return p
    }
}
