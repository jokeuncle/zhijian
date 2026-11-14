import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DictionaryCore

@MainActor enum LibraryFiles {
    static func export(model:AppModel,markdown:Bool) {
        guard let store=model.store else { return }
        let panel=NSSavePanel()
        panel.nameFieldStringValue=markdown ? "知间概念词典.md":"知间词库备份.json"
        panel.allowedContentTypes=markdown ? [UTType(filenameExtension:"md") ?? .plainText]:[.json]
        panel.canCreateDirectories=true
        panel.begin { response in
            guard response == .OK,let url=panel.url else { return }
            Task { @MainActor in
                do {
                    try await model.background {
                        let archive=try store.exportArchive()
                        let data=markdown ? Data(LibraryExport.markdown(archive).utf8):try LibraryJSON.encoder(pretty:true).encode(archive)
                        try data.write(to:url,options:.atomic)
                    }
                    model.notify("已导出到 \(url.lastPathComponent)")
                } catch { model.error=error.localizedDescription }
            }
        }
    }
}

struct ImportView:View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    @State private var batch:ImportBatch?
    @State private var archive:LibraryArchive?
    @State private var issue:String?
    @State private var parsing=false
    private var count:Int { batch?.entries.count ?? archive?.entries.count ?? 0 }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:8) { Text("把读过的，留下来。").font(Palette.heading); Text("粘贴概念笔记，或选择 Markdown / JSON 文件。").font(.system(size:12)).foregroundStyle(Palette.secondary) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing:12) {
                Button { chooseFile() } label:{ Label("选择文件",systemImage:"doc.badge.plus") }
                Text("支持「## 词名」或「1. **词名**」，下一行写解释。").font(.system(size:11)).foregroundStyle(Palette.secondary)
            }
            TextEditor(text:$text).font(.system(size:13,design:.monospaced)).scrollContentBackground(.hidden).padding(10).frame(minHeight:270,maxHeight:.infinity)
                .background(Palette.index,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Palette.rule,lineWidth:1)).accessibilityLabel("待导入的笔记")
            if let issue { Text(issue).font(.system(size:12)).foregroundStyle(Palette.rust).textSelection(.enabled) }
            if batch != nil || archive != nil {
                VStack(alignment:.leading,spacing:10) {
                    Label("识别到 \(count) 个词条",systemImage:"checkmark.circle").font(.system(size:13,weight:.medium)).foregroundStyle(Palette.accent)
                    let titles=batch?.entries.map(\.title) ?? archive?.entries.map(\.title) ?? []
                    Text(titles.prefix(8).joined(separator:"、") + (count>8 ? " 等":"")).font(.system(size:12)).lineSpacing(4).foregroundStyle(Palette.secondary).lineLimit(3)
                    Text(archive == nil ? "将保留原有顺序建立阅读集。重复词名会跳过，已有内容会保留。":"这是完整备份：将恢复词条、笔记和学习进度。已有 ID 保留，词名冲突时整批取消。").font(.system(size:11)).foregroundStyle(Palette.secondary)
                }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(Palette.selection,in:RoundedRectangle(cornerRadius:8))
            }
            HStack {
                Text("在本机解析和保存").font(.system(size:10)).foregroundStyle(Palette.secondary)
                Spacer()
                if batch == nil && archive == nil {
                    Button(parsing ? "正在识别…":"预览词条") { preview() }.buttonStyle(MossButtonStyle()).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || parsing)
                } else {
                    Button(model.isSaving ? "正在收录…":"收录到知间") {
                        Task {
                            let success:Bool
                            if let archive { success=await model.importArchive(archive) }
                            else if let batch { success=await model.importBatch(batch) }
                            else { success=false }
                            if success { dismiss() }
                        }
                    }.buttonStyle(MossButtonStyle()).disabled(model.isSaving)
                }
            }
        }.padding(28).frame(width:720,height:700).background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
        .onChange(of:text) { _,_ in batch=nil; archive=nil; issue=nil }
    }
    private func chooseFile() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.json,.plainText,.text]; panel.allowsMultipleSelection=false
        panel.begin { response in
            guard response == .OK,let url=panel.url else { return }
            Task { @MainActor in
                do { text=try await model.background { try String(contentsOf:url,encoding:.utf8) } }
                catch { issue=error.localizedDescription }
            }
        }
    }
    private func preview() {
        let raw=text; parsing=true; issue=nil
        Task {
            do {
                let result=try await model.background { () -> (ImportBatch?,LibraryArchive?) in
                    guard raw.utf8.count <= 64_000_000 else { throw LibraryError.invalid("单次导入最多 64 MB，请拆分文件。") }
                    let clean=raw.trimmingCharacters(in:.whitespacesAndNewlines)
                    if clean.hasPrefix("{") || clean.hasPrefix("[") {
                        let data=Data(clean.utf8)
                        if let archive=try? LibraryJSON.decoder().decode(LibraryArchive.self,from:data) { return (nil,archive) }
                        return (try LibraryImport.decode(data),nil)
                    }
                    return (try LibraryImport.parseMarkdown(raw),nil)
                }
                if raw == text { batch=result.0; archive=result.1 }
            } catch { issue=error.localizedDescription }
            parsing=false
        }
    }
}

struct AgentConnectionView:View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    private var binary:String {
        let bundled=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/zhijian").path
        if FileManager.default.isExecutableFile(atPath:bundled) { return bundled }
        return URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("zhijian").path
    }
    private var command:String { "codex mcp add zhijian -- '" + binary.replacingOccurrences(of:"'",with:"'\\''") + "' mcp" }
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack { Image(systemName:"terminal").font(.system(size:25,weight:.light)).foregroundStyle(Palette.accent); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("你的词典，Agent 也能读写。").font(Palette.heading)
            Text("通过本地 MCP 接入 Codex。桌面和 Agent 使用同一份词库；关闭窗口后，工具仍可独立运行。").font(.system(size:14)).lineSpacing(6)
            VStack(alignment:.leading,spacing:12) {
                Text("在终端运行一次，连接 Codex").font(.system(size:12,weight:.medium))
                Text(command).font(.system(size:11,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command,forType:.string); model.notify("已复制连接命令") } label:{Label("复制连接命令",systemImage:"doc.on.doc")}.controlSize(.small)
            }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Palette.note,in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:13) {
                Text("然后，直接这样说").font(.system(size:12,weight:.medium))
                Text("“把这篇文章里的概念整理进知间，保留阅读顺序。”\n\n“找出我还没理解的模型结构概念。”\n\n“把秩一编辑解释得更直白，保留我的笔记。”").font(.system(size:13)).lineSpacing(5).foregroundStyle(Palette.secondary)
            }
            Divider()
            HStack(alignment:.top,spacing:10) {
                Image(systemName:"externaldrive").foregroundStyle(Palette.accent)
                VStack(alignment:.leading,spacing:7) {
                    Text("当前本地词库").font(.system(size:11,weight:.medium))
                    Text(model.store?.path ?? DictionaryStore.defaultPath).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                }
            }
            Text("修改有版本记录，删除可以恢复。连接命令按应用的实际位置生成；把应用移到其他目录后，可重新复制命令连接。").font(.system(size:11)).lineSpacing(5).foregroundStyle(Palette.secondary)
            Link("查看 Codex MCP 官方文档",destination:URL(string:"https://learn.chatgpt.com/docs/extend/mcp")!).font(.system(size:11))
        }.padding(30).frame(width:620).background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}

struct HistoryView:View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var records:[ChangeRecord]=[]
    @State private var loading=true
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { VStack(alignment:.leading,spacing:7) { Text("理解，是一层层长出来的。").font(Palette.heading); Text(model.selectedEntry?.title ?? "变更历史").font(.system(size:12)).foregroundStyle(Palette.secondary) }; Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            if loading { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
            else {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:0) {
                        ForEach(records) { record in
                            VStack(alignment:.leading,spacing:12) {
                                HStack {
                                    Text("版本 \(record.snapshot.revision)").font(.system(size:12,weight:.semibold))
                                    Text(action(record.action)).font(.system(size:11)).foregroundStyle(Palette.secondary)
                                    Spacer()
                                    Text(record.actor == "mcp" ? "Agent":record.actor).font(.system(size:10)).foregroundStyle(Palette.secondary)
                                }
                                Text(record.snapshot.summary).font(.system(size:13)).lineSpacing(5).textSelection(.enabled)
                                HStack {
                                    Text(record.timestamp.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(Palette.secondary)
                                    Spacer()
                                    Button("还原到这一版") { Task { if await model.revert(record) { dismiss(); model.notify("已还原内容，学习进度已保留") } } }.controlSize(.small).disabled(record.snapshot.revision == model.selectedEntry?.revision || model.isSaving)
                                }
                            }.padding(.vertical,19)
                            Divider()
                        }
                    }
                }
            }
        }.padding(28).frame(width:650,height:620).background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
        .task {
            guard let store=model.store,let id=model.selectedEntry?.id else { loading=false; return }
            do { records=try await model.background { try store.history(id:id) } }
            catch { model.error=error.localizedDescription }
            loading=false
        }
    }
    private func action(_ value:String) -> String {
        ["create":"首次收录","update":"补充解释","trash":"移入废纸篓","restore":"恢复词条","review":"温习记录","revert":"还原历史内容","import-backup":"从备份恢复"][value] ?? value
    }
}
