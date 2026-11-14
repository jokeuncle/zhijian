import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"books.vertical").font(.system(size:23,weight:.light)).foregroundStyle(Palette.accent)
                Text("知间").font(.custom("Songti SC",size:29))
            }.padding(.top,33).padding(.bottom,4)
            Text("让陌生，慢慢变熟悉。").font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.bottom,30)

            nav("全部词条",symbol:"square.grid.2x2",section:.all,count:model.stats.entries)
            nav("最近读过",symbol:"clock",section:.recent)
            nav("值得再读",symbol:"bookmark",section:.favorites,count:model.stats.favorites)
            nav("温故知新",symbol:"leaf",section:.review,count:model.stats.due)

            HStack {
                Text("文章阅读集").font(.system(size:11,weight:.medium)).foregroundStyle(Palette.secondary)
                Spacer()
                QuietIconButton(symbol:"plus",label:"导入阅读笔记") { model.importPresented = true }
            }.padding(.top,28).padding(.bottom,4)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:4) {
                    ForEach(model.collections) { collection in
                        Button { model.section = .collection(collection.id) } label: {
                            HStack(alignment:.top,spacing:9) {
                                Image(systemName:"text.book.closed").font(.system(size:14)).padding(.top,2)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(collection.title).font(.system(size:13,weight:.medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(collection.entryIDs.count) 个学习单元").font(.system(size:10)).foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength:0)
                            }.padding(.horizontal,10).padding(.vertical,11).frame(maxWidth:.infinity,alignment:.leading)
                                .background(model.section == .collection(collection.id) ? Palette.selection : Color.clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)

            VStack(alignment:.leading,spacing:12) {
                Image(systemName:"quote.opening").font(.system(size:19,weight:.light)).foregroundStyle(Palette.accent)
                Text("看懂一次，\n再用自己的话说一次。").font(.custom("Songti SC",size:17)).lineSpacing(5).fixedSize(horizontal:false,vertical:true)
                Button { model.section = .review } label: { HStack { Text("开始温习"); Spacer(); Image(systemName:"arrow.up.right") }.font(.system(size:12,weight:.medium)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(Palette.paper,in:RoundedRectangle(cornerRadius:9)).padding(.top,16).padding(.bottom,18)

            nav("废纸篓",symbol:"trash",section:.trash,count:model.stats.trash)
            Divider().overlay(Palette.rule).padding(.vertical,12)
            HStack {
                Image(systemName:"externaldrive").font(.system(size:12))
                Text("保存在这台 Mac").font(.system(size:10))
                Spacer()
                QuietIconButton(symbol:"terminal",label:"Agent 连接") { model.agentPresented = true }
            }.foregroundStyle(Palette.secondary).padding(.bottom,12)
        }.padding(.horizontal,18).frame(maxHeight:.infinity).background(Palette.sidebar)
    }
    private func nav(_ title:String,symbol:String,section:LibrarySection,count:Int?=nil) -> some View {
        Button { model.section = section } label: {
            HStack(spacing:10) {
                Image(systemName:symbol).font(.system(size:14)).frame(width:17)
                Text(title).font(.system(size:13,weight:model.section == section ? .semibold : .regular))
                Spacer()
                if let count { Text("\(count)").font(.system(size:11).monospacedDigit()).foregroundStyle(Palette.secondary) }
            }.padding(.horizontal,10).padding(.vertical,10).contentShape(Rectangle())
                .background(model.section == section ? Palette.selection : Color.clear,in:RoundedRectangle(cornerRadius:7))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
