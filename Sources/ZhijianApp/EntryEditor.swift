import SwiftUI
import DictionaryCore

struct EntryEditor:View {
    let existing:Entry?
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft:EntryDraft
    @State private var aliases=""
    init(existing:Entry?) {
        self.existing=existing
        _draft=State(initialValue:existing?.content ?? EntryDraft(title:"",summary:"",sourceTitle:"手动收录"))
        _aliases=State(initialValue:existing?.content.aliases.joined(separator:", ") ?? "")
    }
    var body:some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:7) {
                    Text(existing == nil ? "收录一个新概念":"给理解一个新版本").font(Palette.heading)
                    Text(existing == nil ? "先写一句大白话，其他细节可以慢慢补。":"这次修改会保留在变更历史里。").font(.system(size:12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).pointingHandCursor()
                Button(model.isSaving ? "正在保存…":"保存词条") {
                    draft.aliases=aliases.split(whereSeparator:{ $0=="," || $0=="，" }).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }
                    Task { if await model.saveDraft(draft,existing:existing) { dismiss() } }
                }.buttonStyle(MossButtonStyle()).keyboardShortcut(.defaultAction).disabled(draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.isSaving)
            }.padding(25)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack(alignment:.top,spacing:18) {
                        field("概念名称",text:$draft.title,prompt:"例如：残差流")
                        field("英文名称",text:$draft.english,prompt:"Residual Stream")
                    }
                    multiline("一句话懂了",text:$draft.summary,prompt:"用最直白的话解释这个概念。",height:65)
                    multiline("打个比方",text:$draft.analogy,prompt:"什么生活中的例子能帮你理解它？",height:95)
                    HStack(alignment:.top,spacing:18) {
                        field("分类",text:$draft.category,prompt:"例如：模型内部")
                        field("同义词 / 别名",text:$aliases,prompt:"用逗号分开；不同概念请建立关联")
                    }
                    Picker("词条形式",selection:$draft.kind) { Text("单个概念").tag(EntryKind.concept); Text("对比学习单元").tag(EntryKind.comparison) }.pickerStyle(.segmented).pointingHandCursor()
                    RelationPicker(draft:$draft)
                    DisclosureGroup("更完整的解释") {
                        VStack(alignment:.leading,spacing:18) {
                            multiline("再深一层",text:$draft.details,prompt:"补充准确含义和必要细节。",height:95)
                            multiline("比喻的边界",text:$draft.caveat,prompt:"这个比方在什么地方不成立？",height:75)
                        }.padding(.top,15)
                    }
                    DisclosureGroup("来源与原文") {
                        VStack(alignment:.leading,spacing:18) {
                            field("来源名称",text:$draft.sourceTitle,prompt:"文章标题，或你的笔记名称")
                            field("来源链接",text:$draft.sourceURL,prompt:"https://…")
                            multiline("原文或笔记摘录",text:$draft.sourceExcerpt,prompt:"保留当时遇到这个概念的语境。",height:100)
                        }.padding(.top,15)
                    }
                    multiline("我自己的理解",text:$draft.personalNote,prompt:"讲给别人听时，我会这样说……",height:85)
                }.padding(28)
            }
        }.disclosureGroupStyle(ClickableDisclosureStyle()).frame(width:760,height:780).background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
    private func field(_ label:String,text:Binding<String>,prompt:String) -> some View {
        VStack(alignment:.leading,spacing:8) { Text(label).font(.system(size:12,weight:.medium)); TextField(prompt,text:text).textFieldStyle(.roundedBorder).accessibilityLabel(label) }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func multiline(_ label:String,text:Binding<String>,prompt:String,height:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(label).font(.system(size:12,weight:.medium))
            ZStack(alignment:.topLeading) {
                if text.wrappedValue.isEmpty { Text(prompt).font(.system(size:13)).foregroundStyle(Palette.secondary).padding(10).allowsHitTesting(false) }
                TextEditor(text:text).font(.system(size:14)).lineSpacing(5).scrollContentBackground(.hidden).padding(5).frame(height:height).accessibilityLabel(label)
            }.background(Palette.index,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(Palette.rule,lineWidth:1))
        }
    }
}

private struct RelationPicker:View {
    @Binding var draft:EntryDraft
    @EnvironmentObject private var model:AppModel
    @State private var query=""
    @State private var candidates:[EntrySummary]=[]
    @State private var names:[String:String]=[:]
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Text("关联概念").font(.system(size:12,weight:.medium))
            if !draft.relatedIDs.isEmpty {
                ConceptFlowLayout {
                    ForEach(draft.relatedIDs,id:\.self) { id in
                        HStack { Text(names[id] ?? "已关联概念").lineLimit(1); Button { draft.relatedIDs.removeAll { $0==id } } label:{Image(systemName:"xmark")}.buttonStyle(.plain).pointingHandCursor().help("移除关联") }.font(.system(size:11)).foregroundStyle(Palette.accent).padding(8).background(Palette.selection,in:RoundedRectangle(cornerRadius:6))
                    }
                }
            }
            TextField("搜索已有概念，建立关联",text:$query).textFieldStyle(.roundedBorder).accessibilityLabel("搜索关联概念")
            if !query.isEmpty {
                ForEach(candidates.filter { $0.id != draft.id && !draft.relatedIDs.contains($0.id) }) { entry in
                    Button { draft.relatedIDs.append(entry.id); names[entry.id]=entry.title; query="" } label:{ Label(entry.title,systemImage:"plus.circle").font(.system(size:12)) }.buttonStyle(.plain).pointingHandCursor().foregroundStyle(Palette.accent)
                }
            }
        }.task {
            for e in model.relatedEntries { names[e.id]=e.title }
        }.task(id:query) {
            guard !query.isEmpty,let store=model.store else { candidates=[]; return }
            do {
                try await Task.sleep(nanoseconds:160_000_000)
                let text=query
                let result=try await model.background { try store.list(LibraryQuery(text:text,limit:8)) }
                if !Task.isCancelled { candidates=result.entries }
            } catch { }
        }
    }
}
