import SwiftUI
import DictionaryCore
import AppKit

struct EntryDetailView:View {
    let entry:Entry
    let sectionKey:String
    @EnvironmentObject private var model:AppModel
    @State private var note=""
    @State private var baseline=""
    @State private var noteRevision=0
    @State private var technicalExpanded=false
    @State private var sourceExpanded=false
    @State private var readingOffset=0.0
    @State private var noteExpanded=false
    private var dirty:Bool { note != baseline }
    private var hasNoteConflict:Bool { dirty && noteRevision != entry.revision && entry.content.personalNote != baseline }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                if model.isReadingMode {
                    Button(action:model.toggleReadingMode) { Label("返回词库",systemImage:"sidebar.left").font(.system(size:12)) }
                        .buttonStyle(.plain).pointingHandCursor().help("退出专注阅读（⌘⇧L）")
                    Spacer(minLength:12)
                } else {
                    QuietIconButton(symbol:"book",label:"专注阅读（⌘⇧L）",action:model.toggleReadingMode).disabled(!model.canToggleReadingMode)
                }
                Image(systemName:"text.book.closed").font(.system(size:12))
                Text(model.activeCollection?.title ?? entry.content.category).font(.system(size:11)).lineLimit(1)
                if let position=model.currentPosition,let collection=model.activeCollection {
                    Text("/  \(position+1) / \(collection.entryIDs.count)").font(.system(size:10).monospacedDigit())
                }
                Spacer(minLength:8)
                QuietIconButton(symbol:"chevron.up",label:"上一条（⌘↑）",action:model.selectPrevious).disabled(!model.canSelectPrevious)
                QuietIconButton(symbol:"chevron.down",label:"下一条（⌘↓）",action:model.selectNext).disabled(!model.canSelectNext)
                if !model.isReadingMode && entry.deletedAt == nil {
                    QuietIconButton(symbol:entry.favorite ? "bookmark.fill":"bookmark",label:entry.favorite ? "取消收藏":"收藏词条",active:entry.favorite,action:model.toggleFavorite)
                    QuietIconButton(symbol:"square.and.pencil",label:"编辑词条",action:model.editSelected)
                }
                if !model.isReadingMode {
                    QuietIconButton(symbol:"clock.arrow.circlepath",label:"变更历史") { model.historyPresented=true }
                }
                Menu {
                    if model.isReadingMode {
                        Button(entry.favorite ? "取消收藏":"收藏词条",action:model.toggleFavorite)
                        Button("编辑词条",action:model.editSelected)
                        Button("变更历史") { model.historyPresented=true }
                        Divider()
                    }
                    Button("复制解释") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(entry.title)\n\(entry.summary)\n\n\(entry.content.analogy)",forType:.string); model.notify("已复制解释") }
                    Divider()
                    if entry.deletedAt == nil { Button("移入废纸篓",role:.destructive,action:model.trashSelected) }
                    else { Button("恢复词条",action:model.restoreSelected).pointingHandCursor() }
                } label:{ Image(systemName:"ellipsis").frame(width:25,height:30) }.menuStyle(.borderlessButton).pointingHandCursor().frame(width:27).help("更多词条操作")
            }.foregroundStyle(Palette.secondary).padding(.horizontal,30).padding(.top,model.isReadingMode ? 12:24).padding(.bottom,model.isReadingMode ? 10:16)
            Divider().overlay(Palette.rule)
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    if entry.deletedAt != nil {
                        HStack { Label("这个词条在废纸篓中",systemImage:"trash"); Spacer(); Button("恢复词条",action:model.restoreSelected).pointingHandCursor() }.font(.system(size:12)).foregroundStyle(Palette.rust).padding(13).background(Palette.note,in:RoundedRectangle(cornerRadius:8)).padding(.bottom,24)
                    }
                    HStack(alignment:.top,spacing:16) {
                        VStack(alignment:.leading,spacing:10) {
                            Text(entry.title).font(Palette.title).lineSpacing(4).textSelection(.enabled)
                            if !entry.content.english.isEmpty { Text(entry.content.english).font(.system(size:14)).foregroundStyle(Palette.secondary).textSelection(.enabled) }
                        }
                        Spacer(minLength:0)
                        if !model.isReadingMode {
                        Text(entry.mastery.label).font(.system(size:10)).foregroundStyle(Palette.accent).padding(.horizontal,10).padding(.vertical,6).background(Palette.selection,in:Capsule()).fixedSize().padding(.top,8)
                        }
                    }.padding(.bottom,29)

                    Text(entry.summary).font(.custom("Songti SC",size:25)).lineSpacing(8).foregroundStyle(Palette.accent).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).padding(.bottom,30)
                    Rectangle().fill(Palette.rule).frame(height:1).padding(.bottom,29)

                    if !entry.content.analogy.isEmpty {
                        SectionTitle(title:"打个比方",symbol:"quote.bubble").padding(.bottom,13)
                        Text(entry.content.analogy).readingText().padding(.bottom,29)
                    }

                    if !entry.content.details.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !entry.content.caveat.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    DisclosureGroup(isExpanded:$technicalExpanded) {
                        VStack(alignment:.leading,spacing:18) {
                            if !entry.content.details.isEmpty { Text(entry.content.details).readingText() }
                            if !entry.content.caveat.isEmpty {
                                VStack(alignment:.leading,spacing:8) {
                                    Label("比喻的边界",systemImage:"scope").font(.system(size:12,weight:.medium)).foregroundStyle(Palette.rust)
                                    Text(entry.content.caveat).font(.system(size:13)).lineSpacing(6).foregroundStyle(Palette.secondary).textSelection(.enabled)
                                }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Palette.note,in:RoundedRectangle(cornerRadius:8))
                            }
                        }.padding(.top,15).padding(.bottom,5)
                    } label:{ Label("再深一层",systemImage:"square.stack.3d.up").font(.system(size:13,weight:.medium)).foregroundStyle(Palette.ink) }
                        .padding(.vertical,15)
                    Divider().overlay(Palette.rule).padding(.bottom,24)
                    }

                    if !model.relatedEntries.isEmpty {
                        SectionTitle(title:entry.content.kind == .comparison ? "拆开来看，更容易懂":"把概念连起来",symbol:"point.3.connected.trianglepath.dotted").padding(.top,3).padding(.bottom,13)
                        ConceptFlowLayout(spacing:8,rowSpacing:8) {
                            ForEach(model.relatedEntries) { related in
                                Button { model.navigateToRelated(related.id) } label: {
                                    HStack(spacing:7) {
                                        Text(related.title).font(.system(size:12,weight:.medium)).lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                                        Image(systemName:"arrow.up.right").font(.system(size:9))
                                    }.foregroundStyle(Palette.accent).padding(.horizontal,11).padding(.vertical,8)
                                        .background(Palette.index,in:RoundedRectangle(cornerRadius:6))
                                        .overlay(RoundedRectangle(cornerRadius:6).stroke(Palette.rule,lineWidth:0.7))
                                }.buttonStyle(.plain).pointingHandCursor()
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,29)
                    }

                    if model.isReadingMode {
                        DisclosureGroup(isExpanded:$noteExpanded) { noteCard.padding(.top,12) } label: {
                            HStack {
                                Label("我的理解",systemImage:"pencil.line")
                                if dirty { Text("尚未保存").foregroundStyle(Palette.rust) }
                            }.font(.system(size:12)).foregroundStyle(Palette.secondary)
                        }.padding(.bottom,24)
                    } else { noteCard }


                    DisclosureGroup(isExpanded:$sourceExpanded) {
                        VStack(alignment:.leading,spacing:10) {
                            Text(entry.content.sourceTitle.isEmpty ? "手动收录":entry.content.sourceTitle).font(.system(size:12,weight:.medium))
                            if !entry.content.sourceURL.isEmpty,let url=URL(string:entry.content.sourceURL) { Link("打开来源",destination:url).pointingHandCursor().font(.system(size:12)) }
                            if !entry.content.sourceExcerpt.isEmpty { Text(entry.content.sourceExcerpt).font(.system(size:12)).lineSpacing(5).foregroundStyle(Palette.secondary).textSelection(.enabled) }
                            if ["用户提供的概念笔记","示例概念笔记"].contains(entry.content.sourceTitle) { Text("根据概念笔记整理的内置示例，补充了比喻边界；尚未关联文章原文。").font(.system(size:10)).foregroundStyle(Palette.secondary) }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,12)
                    } label:{ Label("来自哪里",systemImage:"link").font(.system(size:12)).foregroundStyle(Palette.secondary) }
                    .padding(.bottom,30)

                    Divider().overlay(Palette.rule).padding(.bottom,19)
                    HStack {
                        Button(action:model.selectPrevious) { Label("上一条",systemImage:"arrow.left").font(.system(size:11)) }
                            .buttonStyle(.plain).pointingHandCursor().disabled(!model.canSelectPrevious)
                        Spacer()
                        Button(action:model.selectNext) { HStack(spacing:8) { Text("下一条"); Image(systemName:"arrow.right") }.font(.system(size:11)) }
                            .buttonStyle(.plain).pointingHandCursor().disabled(!model.canSelectNext)
                    }.foregroundStyle(Palette.accent)

                }.frame(maxWidth:700,alignment:.leading).padding(.horizontal,40).padding(.top,34).padding(.bottom,32).frame(maxWidth:.infinity)
                .background(ReadingScrollObserver(initialOffset:model.readingPosition(entryID:entry.id,sectionKey:sectionKey).offset) { offset in
                    readingOffset=offset; savePosition()
                })
            }.id(entry.id)
        }
        .disclosureGroupStyle(ClickableDisclosureStyle())
        .onAppear {
            resetNote(); noteExpanded=dirty
            let position=model.readingPosition(entryID:entry.id,sectionKey:sectionKey)
            technicalExpanded=position.technicalExpanded; sourceExpanded=position.sourceExpanded; readingOffset=position.offset
        }
        .onChange(of:technicalExpanded) { _,_ in savePosition() }
        .onChange(of:sourceExpanded) { _,_ in savePosition() }
        .onDisappear { savePosition() }
        .onChange(of:entry.revision) { _,_ in
            if !dirty { resetNote() }
            else if entry.content.personalNote == baseline { noteRevision=entry.revision; cacheDraft() }
        }
        .onChange(of:dirty) { _,dirty in if dirty { noteExpanded=true } }
        .onChange(of:note) { _,value in
            if value != baseline { model.noteDrafts[entry.id]=(value,noteRevision,baseline) }
            else { model.noteDrafts.removeValue(forKey:entry.id) }
        }
    }
    private var noteCard: some View {
        VStack(alignment:.leading,spacing:13) {
                        if !model.isReadingMode {
                        HStack {
                            SectionTitle(title:"换我来说",symbol:"pencil.line")
                            Spacer()
                            if dirty { Text("尚未保存").font(.system(size:10)).foregroundStyle(Palette.rust) }
                        }
                        }
                        NoteEditor(text:$note,isEditable:entry.deletedAt == nil)
                            .frame(height:110).accessibilityLabel("我的理解")
                        if hasNoteConflict {
                            VStack(alignment:.leading,spacing:10) {
                                Text("词条中的理解已被更新，你的草稿仍保留在这里。").font(.system(size:12)).foregroundStyle(Palette.rust)
                                DisclosureGroup("查看最新理解") { Text(entry.content.personalNote.isEmpty ? "最新版本没有个人笔记。":entry.content.personalNote).font(.system(size:13)).lineSpacing(5).textSelection(.enabled).padding(.top,8) }.font(.system(size:12))
                                HStack {
                                    Button("使用最新理解") { model.noteDrafts.removeValue(forKey:entry.id); resetNote() }.pointingHandCursor()
                                    Button("保留我的草稿") { baseline=entry.content.personalNote; noteRevision=entry.revision; cacheDraft() }.pointingHandCursor().help("核对后再次保存，将把你的草稿写入最新版本")
                                }.controlSize(.small)
                            }
                        }
                        HStack {
                            Text("写成自己的话，才算真正留下来。").font(.system(size:10)).foregroundStyle(Palette.secondary)
                            Spacer()
                            Button("保存理解") {
                                let text=note,revision=noteRevision
                                Task { if await model.saveNote(text,entry:entry,revision:revision) { baseline=text; noteRevision=model.selectedEntry?.revision ?? revision+1; cacheDraft(); model.notify("留下了你的理解") } }
                            }.buttonStyle(.bordered).pointingHandCursor().controlSize(.small).disabled(!dirty || hasNoteConflict || model.isSaving || entry.deletedAt != nil)
                        }
                    }.padding(18).background(Palette.note,in:RoundedRectangle(cornerRadius:9)).padding(.bottom,24)
    }
    private func savePosition() {
        model.saveReadingPosition(entryID:entry.id,sectionKey:sectionKey,position:ReadingPosition(offset:readingOffset,technicalExpanded:technicalExpanded,sourceExpanded:sourceExpanded))
    }
    private func resetNote() {
        if let cached=model.noteDrafts[entry.id] {
            baseline=cached.baseline; note=cached.text
            noteRevision=entry.content.personalNote == baseline ? entry.revision:cached.revision
        } else { baseline=entry.content.personalNote; note=baseline; noteRevision=entry.revision }
    }
    private func cacheDraft() {
        if dirty { model.noteDrafts[entry.id]=(note,noteRevision,baseline) }
        else { model.noteDrafts.removeValue(forKey:entry.id) }
    }
}
