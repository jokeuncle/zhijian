import SwiftUI
import DictionaryCore

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"books.vertical").font(.system(size:23,weight:.light)).foregroundStyle(Palette.accent)
                Text("知间").font(.custom("Songti SC",size:29))
            }.padding(.top,33).padding(.bottom,4)
            Text("让陌生，慢慢变熟悉。").font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.bottom,30)

            nav("全部词条",symbol:"square.grid.2x2",section:.all)
            nav("最近读过",symbol:"clock",section:.recent)
            nav("值得再读",symbol:"bookmark",section:.favorites)
            nav("温故知新",symbol:"leaf",section:.review)

            HStack {
                Text("文章阅读集").font(.system(size:11,weight:.medium)).foregroundStyle(Palette.secondary)
                Spacer()
                QuietIconButton(symbol:"plus",label:"导入阅读笔记") { model.importPresented = true }
            }.padding(.top,28).padding(.bottom,4)
            HStack(spacing:6) {
                Image(systemName:"magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("找阅读集…",text:$model.collectionSearch).textFieldStyle(.plain).font(.system(size:11)).accessibilityLabel("搜索阅读集")
                if !model.collectionSearch.isEmpty {
                    Button { model.collectionSearch="" } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help("清空阅读集搜索")
                }
            }.padding(8).background(Palette.paper,in:RoundedRectangle(cornerRadius:7))
            HStack {
                Text("\(model.visibleCollections.count) 个阅读集").font(.system(size:10)).foregroundStyle(Palette.secondary)
                Spacer(minLength:4)
                Menu {
                    ForEach(CollectionOrder.allCases,id:\.self) { order in
                        Button { model.collectionOrder=order } label: {
                            if model.collectionOrder == order { Label(order.label,systemImage:"checkmark") }
                            else { Text(order.label) }
                        }
                    }
                } label: { Label(model.collectionOrder.label,systemImage:"arrow.up.arrow.down").font(.system(size:10)) }
                    .menuStyle(.borderlessButton).fixedSize().help("阅读集排序")
            }.padding(.top,9).padding(.bottom,7)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:4) {
                    ForEach(model.visibleCollections) { collection in
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
                        }.buttonStyle(.plain).help(collection.title).id(collection.id)
                    }
                    if model.visibleCollections.isEmpty {
                        Text(model.collectionSearch.isEmpty ? "导入笔记，建立第一个阅读集。":"没有找到阅读集，试试其他关键词。")
                            .font(.system(size:11)).foregroundStyle(Palette.secondary).padding(.vertical,16).padding(.horizontal,8)
                    }
                }
            }.scrollIndicators(.automatic).frame(maxHeight:.infinity).layoutPriority(1).padding(.bottom,12)

            .onChange(of:model.section) { _,_ in scrollToCollection(proxy) }
            .onChange(of:model.visibleCollections.map(\.id)) { _,_ in
                if model.collectionSearch.isEmpty { scrollToCollection(proxy) }
            }
            }

            nav("废纸篓",symbol:"trash",section:.trash)
            Divider().overlay(Palette.rule).padding(.vertical,12)
            HStack {
                Image(systemName:"externaldrive").font(.system(size:12))
                Text("保存在这台 Mac").font(.system(size:10))
                Spacer()
                QuietIconButton(symbol:"terminal",label:"Agent 连接") { model.agentPresented = true }
            }.foregroundStyle(Palette.secondary).padding(.bottom,12)
        }.padding(.horizontal,18).frame(maxHeight:.infinity).background(Palette.sidebar)
    }
    private func scrollToCollection(_ proxy: ScrollViewProxy) {
        if let id=model.activeCollection?.id,model.visibleCollections.contains(where: { $0.id == id }) { proxy.scrollTo(id,anchor:nil) }
    }
    private func nav(_ title:String,symbol:String,section:LibrarySection) -> some View {
        Button { model.section = section } label: {
            HStack(spacing:10) {
                Image(systemName:symbol).font(.system(size:14)).frame(width:17)
                Text(title).font(.system(size:13,weight:model.section == section ? .semibold : .regular))
                Spacer()
            }.padding(.horizontal,10).padding(.vertical,10).contentShape(Rectangle())
                .background(model.section == section ? Palette.selection : Color.clear,in:RoundedRectangle(cornerRadius:7))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
