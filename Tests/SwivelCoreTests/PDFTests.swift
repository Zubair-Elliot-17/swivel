import CoreGraphics
import Foundation
import Testing
import SwivelCore

// MARK: Orientation

enum Corner { case topLeft, topRight, bottomRight, bottomLeft }

/// EXIF spec: where the stored image's top-left and top-right pixels appear once displayed.
@Test(arguments: [
    (1, Corner.topLeft, Corner.topRight), (2, .topRight, .topLeft), (3, .bottomRight, .bottomLeft), (4, .bottomLeft, .bottomRight),
    (5, .topLeft, .bottomLeft), (6, .topRight, .bottomRight), (7, .bottomRight, .topRight), (8, .bottomLeft, .topLeft),
])
func orientedPageMapsCorners(orientation: Int, storedTopLeft: Corner, storedTopRight: Corner) {
    let (w, h) = (40, 20)
    let page = orientedPage(orientation: orientation, width: w, height: h)
    let swapped = orientation >= 5
    #expect(page.size == (swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h)))
    // The drawn image rect lands exactly on the page.
    #expect(CGRect(x: 0, y: 0, width: w, height: h).applying(page.transform) == CGRect(origin: .zero, size: page.size))

    func at(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: 0, y: page.size.height)
        case .topRight: CGPoint(x: page.size.width, y: page.size.height)
        case .bottomRight: CGPoint(x: page.size.width, y: 0)
        case .bottomLeft: .zero
        }
    }
    // CG draws the stored top row at the top of the rect (y = h).
    #expect(CGPoint(x: 0, y: h).applying(page.transform) == at(storedTopLeft))
    #expect(CGPoint(x: w, y: h).applying(page.transform) == at(storedTopRight))
}

@Test(arguments: [0, 9])
func unknownOrientationIsUpright(orientation: Int) {
    let page = orientedPage(orientation: orientation, width: 40, height: 20)
    #expect(page.size == CGSize(width: 40, height: 20) && page.transform == .identity)
}
