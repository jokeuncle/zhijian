import SwiftUI

struct Workspace: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HSplitView {
            SidebarView().frame(minWidth:200,idealWidth:218,maxWidth:240)
            EntryListView().frame(minWidth:270,idealWidth:314,maxWidth:340)
            Group {
                if model.section == .review { ReviewView() }
                else if let entry = model.selectedEntry {
                    EntryDetailView(entry:entry).id(entry.id)
                } else if model.isLoading {
                    ProgressView("正在打开词库…").frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ContentUnavailableView {
                        Label(model.section == .trash ? "废纸篓是空的" : "给新概念留一个位置",systemImage:model.section == .trash ? "trash" : "book.closed")
                    } description: { Text(model.section == .trash ? "删除的词条会保留在这里，方便找回来。" : "写下一句自己的解释，或者导入一段读过的笔记。") }
                    actions: { if model.section != .trash { Button("收录第一个概念",action:model.newEntry).buttonStyle(MossButtonStyle()) } }
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }.frame(minWidth:540,maxWidth:.infinity,maxHeight:.infinity).background(Palette.paper)
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
}
