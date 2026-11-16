import SwiftUI

struct Workspace: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.isReadingMode {
                readingPane
            } else {
                HSplitView {
                    SidebarView().frame(minWidth:200,idealWidth:218,maxWidth:240)
                    EntryListView().frame(minWidth:270,idealWidth:314,maxWidth:340)
                    readingPane
                }
            }
        }
        .background(Palette.paper).tint(Palette.accent).foregroundStyle(Palette.ink)
        .overlay(alignment:.bottom) {
            if let message = model.toast {
                Label(message,systemImage:"checkmark").font(.system(size:13)).padding(.horizontal,18).padding(.vertical,12)
                    .background(Palette.ink,in:Capsule()).foregroundStyle(Palette.paper).padding(.bottom,22).allowsHitTesting(false)
            }
        }
        .task { await model.bootstrap(); await model.pollForExternalChanges() }
        .sheet(isPresented:$model.editorPresented) { EntryEditor(existing:model.editingEntry).environmentObject(model) }
        .sheet(isPresented:$model.importPresented) { ImportView().environmentObject(model) }
        .sheet(isPresented:$model.agentPresented) { AgentConnectionView().environmentObject(model) }
        .sheet(isPresented:$model.historyPresented) { HistoryView().environmentObject(model) }
        .alert("这次操作没有完成",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) {
            Button("知道了",role:.cancel) { model.error = nil }
            Button("刷新词库") { model.error = nil; Task { await model.refresh() } }
        } message: { Text(model.error ?? "") }
    }
    private var readingPane: some View {
        Group {
            if model.section == .review { ReviewView() }
            else if let entry = model.selectedEntry {
                EntryDetailView(entry:entry,sectionKey:model.section.storageKey).id(model.section.storageKey+":"+entry.id)
            } else if model.isLoading {
                ProgressView("正在打开词库…").frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ContentUnavailableView {
                    Label(model.section == .trash ? (model.stats.trash == 0 ? "废纸篓是空的" : "没有匹配的词条") : "给新概念留一个位置",systemImage:model.section == .trash ? "trash" : "book.closed")
                } description: { Text(model.section == .trash ? (model.stats.trash == 0 ? "删除的词条会保留在这里，方便找回来。" : "试试其他关键词，或清除筛选条件。") : "写下一句自己的解释，或者导入一段读过的笔记。") }
                actions: {
                    if model.section != .trash { Button("收录第一个概念",action:model.newEntry).buttonStyle(MossButtonStyle()) }
                    else if model.stats.trash > 0 { Button("清除筛选") { model.search = ""; model.masteryFilter = nil }.pointingHandCursor() }
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.frame(minWidth:540,maxWidth:.infinity,maxHeight:.infinity).background(Palette.paper)
        .overlay(alignment:.topLeading) {
            if model.isReadingMode && model.selectedEntry == nil {
                Button("返回词库",action:model.toggleReadingMode).buttonStyle(.plain).pointingHandCursor().padding(24)
            }
        }
    }

}
