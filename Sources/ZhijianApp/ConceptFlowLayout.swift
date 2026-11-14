import SwiftUI

/// Keeps concept links at their natural text width instead of stretching a grid's cells.
struct ConceptFlowLayout:Layout {
    var spacing:CGFloat=8
    var rowSpacing:CGFloat=8

    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        arrange(subviews,width:proposal.width ?? .greatestFiniteMagnitude).size
    }

    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let result=arrange(subviews,width:bounds.width)
        for index in subviews.indices {
            subviews[index].place(at:CGPoint(x:bounds.minX+result.positions[index].x,y:bounds.minY+result.positions[index].y),
                                  anchor:.topLeading,proposal:ProposedViewSize(result.sizes[index]))
        }
    }

    private func arrange(_ subviews:Subviews,width:CGFloat) -> (size:CGSize,positions:[CGPoint],sizes:[CGSize]) {
        guard !subviews.isEmpty else { return (.zero,[],[]) }
        let available=max(1,width)
        var positions:[CGPoint]=[],sizes:[CGSize]=[]
        var x:CGFloat=0,y:CGFloat=0,rowHeight:CGFloat=0,usedWidth:CGFloat=0
        for subview in subviews {
            var size=subview.sizeThatFits(.unspecified)
            if size.width>available { size=subview.sizeThatFits(ProposedViewSize(width:available,height:nil)); size.width=min(available,size.width) }
            if x>0 && x+size.width>available {
                x=0; y += rowHeight+rowSpacing; rowHeight=0
            }
            positions.append(CGPoint(x:x,y:y)); sizes.append(size)
            usedWidth=max(usedWidth,x+size.width)
            x += size.width+spacing; rowHeight=max(rowHeight,size.height)
        }
        return (CGSize(width:usedWidth,height:y+rowHeight),positions,sizes)
    }
}
