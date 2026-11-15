import SwiftUI
import DictionaryCore

struct EntryListView: View {
    @EnvironmentObject private var model:AppModel
    @FocusState private var searching:Bool
    @State private var confirmingEmptyTrash = false
    private var isEmptyTrash: Bool { model.section == .trash && model.stats.trash == 0 }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("概念索引").font(.system(size:12)).foregroundStyle(Palette.secondary)
                Spacer()
                Menu {
                    Button("导入笔记") { model.importPresented = true }
                    Button("导出 JSON 备份") { LibraryFiles.export(model:model,markdown:false) }
                    Button("导出 Markdown") { LibraryFiles.export(model:model,markdown:true) }
                    Divider()
                    Button("刷新词库") { Task { await model.refresh() } }
                } label: { Image(systemName:"ellipsis").frame(width:24,height:28) }.menuStyle(.borderlessButton).frame(width:28).help("词库操作")
                QuietIconButton(symbol:"square.and.pencil",label:"新建词条",action:model.newEntry)
            }.padding(.top,26).padding(.bottom,20)

            Text(model.heading).font(Palette.heading).lineSpacing(4).fixedSize(horizontal:false,vertical:true).padding(.bottom,20)
            if model.section == .trash && model.stats.trash > 0 {
                Button("清空废纸篓…", role: .destructive) { confirmingEmptyTrash = true }
                    .disabled(model.isSaving)
                    .padding(.bottom,12)
            }
            if let collection=model.activeCollection {
                Text(collection.subtitle).font(.system(size:11)).lineSpacing(4).foregroundStyle(Palette.secondary).fixedSize(horizontal:false,vertical:true).padding(.bottom,15)
                HStack(spacing:3) {
                    ForEach(pathWindow(collection),id:\.self) { offset in
                        let id=collection.entryIDs[offset]
                        Button { model.select(id) } label: {
                            RoundedRectangle(cornerRadius:1.5).fill(model.selectedID == id ? Palette.accent : Palette.rule).frame(height:5).frame(maxWidth:.infinity).frame(height:17).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("学习单元 \(offset+1)").accessibilityLabel("前往学习单元 \(offset+1)")
                    }
                }.padding(.bottom,21)
            }

            if isEmptyTrash {
                Spacer(minLength:0)
            } else {
                HStack(spacing:7) {
                    Image(systemName:"magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("找一个概念…",text:$model.search).textFieldStyle(.plain).font(.system(size:12)).focused($searching).accessibilityLabel("搜索词条")
                    if !model.search.isEmpty { Button { model.search="" } label:{ Image(systemName:"xmark.circle.fill").foregroundStyle(Palette.secondary) }.buttonStyle(.plain).help("清空搜索") }
                    else { Text("⌘ F").font(.system(size:10)).foregroundStyle(Palette.secondary) }
                }.padding(10).background(Palette.paper,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(Palette.rule,lineWidth:0.5))

                HStack {
                    Text(model.isLoading ? "正在查找…" : "\(model.total.formatted()) 个" + (model.activeCollection == nil ? "词条" : "学习单元")).font(.system(size:10)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Menu {
                        Button("全部学习状态") { model.masteryFilter=nil }
                        ForEach(Mastery.allCases,id:\.self) { mastery in Button(mastery.label) { model.masteryFilter=mastery } }
                    } label:{ HStack(spacing:4) { Text(model.masteryFilter?.label ?? "全部状态"); Image(systemName:"line.3.horizontal.decrease") }.font(.system(size:10)) }.menuStyle(.borderlessButton).fixedSize().help("筛选学习状态")
                }.padding(.top,15).padding(.bottom,10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:4) {
                            if model.pageOffset > 0 {
                                Button("查看前 60 个",action:model.loadPreviousPage)
                                    .buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Palette.accent)
                                    .padding(.vertical,12).frame(maxWidth:.infinity).disabled(model.isLoading)
                            }
                            ForEach(Array(model.entries.enumerated()),id:\.element.id) { index,entry in
                                if model.activeCollection != nil && (index == 0 || model.entries[index-1].category != entry.category) {
                                    Text(entry.category).font(.system(size:10,weight:.medium)).foregroundStyle(Palette.secondary).padding(.top,index == 0 ? 5 : 18).padding(.bottom,6).padding(.leading,9)
                                }
                                ConceptRow(entry:entry,selected:model.selectedID == entry.id,concealSummary:model.section == .review) { model.select(entry.id) }.id(entry.id)
                            }
                            if model.hasMore {
                                HStack {
                                    Spacer(minLength:0)
                                    Button(model.isLoading ? "正在加载…":"再加载 60 个") { Task { await model.loadPage(append:true) } }
                                        .buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Palette.accent)
                                        .padding(.horizontal,16).padding(.vertical,12).contentShape(Rectangle()).disabled(model.isLoading)
                                    Spacer(minLength:0)
                                }.frame(maxWidth:.infinity).padding(.top,8)
                            }
                            if model.section != .trash && model.entries.isEmpty && !model.isLoading { Text(model.search.isEmpty ? "这里还没有词条" : "没有找到“\(model.search)”\n试试中文名、英文名或解释里的词。").font(.system(size:12)).lineSpacing(5).foregroundStyle(Palette.secondary).padding(.vertical,30).padding(.horizontal,8) }
                        }.padding(.bottom,20)
                    }.scrollIndicators(.hidden)
                    .onChange(of:model.selectedID) { _,new in if let new,model.entries.contains(where:{$0.id==new}) { proxy.scrollTo(new,anchor:nil) } }
                    .onChange(of:model.entries.map(\.id)) { _,_ in if let id=model.selectedID,model.entries.contains(where:{$0.id==id}) { proxy.scrollTo(id,anchor:nil) } }
                }

            }
        }.padding(.horizontal,20).frame(maxHeight:.infinity).background(Palette.index)
        .onChange(of:model.focusSearch) { _,_ in searching=true }
        .alert("清空废纸篓？", isPresented:$confirmingEmptyTrash) {
            Button("取消", role:.cancel) { }
            Button("永久删除", role:.destructive) { Task { await model.emptyTrash() } }
        } message: {
            Text("将永久删除废纸篓中的全部 \(model.stats.trash) 个词条及其历史记录，无法恢复。搜索和筛选不会缩小清空范围。")
        }
    }
    private func pathWindow(_ collection:ReadingCollection) -> [Int] {
        let count=collection.entryIDs.count,position=model.currentPosition ?? 0
        let start=min(max(0,position-12),max(0,count-24))
        return Array(start..<min(count,start+24))
    }
}

private struct ConceptRow:View {
    let entry:EntrySummary
    let selected:Bool
    let concealSummary:Bool
    let action:()->Void
    @State private var hovering=false
    var body:some View {
        Button(action:action) {
            HStack(alignment:.top,spacing:10) {
                if let position=entry.position {
                    Text(String(format:"%02d",position+1)).font(.system(size:10).monospacedDigit()).foregroundStyle(selected ? Palette.accent : Palette.secondary).frame(width:19).padding(.top,3)
                }
                VStack(alignment:.leading,spacing:6) {
                    HStack(alignment:.firstTextBaseline,spacing:5) {
                        Text(entry.title).font(.system(size:13,weight:selected ? .semibold:.medium)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength:0)
                        if entry.favorite { Image(systemName:"bookmark.fill").font(.system(size:9)).foregroundStyle(Palette.accent) }
                        if entry.mastery == .understood { Image(systemName:"checkmark").font(.system(size:10)).foregroundStyle(Palette.accent) }
                    }
                    if !concealSummary { Text(entry.summary).font(.system(size:10)).foregroundStyle(Palette.secondary).lineLimit(1) }
                }
            }.padding(.horizontal,10).padding(.vertical,11).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                .background(selected ? Palette.selection : (hovering ? Palette.paper : Color.clear),in:RoundedRectangle(cornerRadius:7))
        }.buttonStyle(.plain).onHover { hovering=$0 }.accessibilityLabel(entry.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
