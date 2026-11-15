import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct ZhijianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("知间",id:"library") { Workspace().environmentObject(model).frame(minWidth:1080,minHeight:700) }
            .defaultSize(width:1340,height:860)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing:.newItem) {
                    Button("新建词条",action:model.newEntry).keyboardShortcut("n")
                    Button("导入阅读笔记") { model.importPresented = true }.keyboardShortcut("i",modifiers:[.command,.shift])
                }
                CommandGroup(after:.textEditing) {
                    Button("搜索词条",action:model.searchEntries).keyboardShortcut("f")
                    Button("编辑当前词条",action:model.editSelected).keyboardShortcut("e")
                    Button("收藏当前词条",action:model.toggleFavorite).keyboardShortcut("d")
                }
                CommandMenu("学习") {
                    Button(model.isReadingMode ? "退出专注阅读":"专注阅读",action:model.toggleReadingMode)
                        .keyboardShortcut("l",modifiers:[.command,.shift]).disabled(!model.canToggleReadingMode)
                    Divider()
                    Button("上一条",action:model.selectPrevious).keyboardShortcut(.upArrow,modifiers:.command).disabled(!model.canSelectPrevious)
                    Button("下一条",action:model.selectNext).keyboardShortcut(.downArrow,modifiers:.command).disabled(!model.canSelectNext)
                    Divider()
                    Button("温故知新") { model.section = .review }.keyboardShortcut("r",modifiers:[.command,.shift])
                    Button("刷新词库") { Task { await model.refresh() } }.keyboardShortcut("r")
                    Divider()
                    Button("Agent 连接") { model.agentPresented = true }
                    Button("在访达中显示词库") { NSWorkspace.shared.selectFile(model.store?.path ?? "",inFileViewerRootedAtPath:"") }
                }
            }
        Settings { AgentConnectionView().environmentObject(model) }
    }
}
