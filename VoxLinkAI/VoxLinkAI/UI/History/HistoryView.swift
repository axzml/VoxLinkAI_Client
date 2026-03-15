//
//  HistoryView.swift
//  VoxLink
//
//  历史记录视图 - 标准 macOS 风格
//

import SwiftUI
import UserNotifications

// MARK: - History Group

struct HistoryGroup: Identifiable {
    let id: String
    let title: String
    let items: [HistoryItem]
}

// MARK: - History View

struct HistoryView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @State private var searchText = ""
    @State private var selectedItem: HistoryItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var isEditMode = false
    @State private var selectedItemIds: Set<Int64> = []
    @State private var showBatchDeleteConfirmation = false

    /// 初始选中的条目 ID（用于从首页点击跳转）
    var initialSelectedItemId: Int64?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistoryListView(
                groups: makeGroups(),
                selectedItem: $selectedItem,
                isEmpty: historyStore.items.isEmpty,
                searchText: $searchText,
                isEditMode: isEditMode,
                selectedItemIds: $selectedItemIds,
                onEnterEditMode: {
                    withAnimation {
                        isEditMode = true
                        selectedItemIds.removeAll()
                    }
                }
            )
            .frame(minWidth: 280, idealWidth: 320)
        } detail: {
            if isEditMode {
                editModeDetailView
            } else {
                HistoryDetailContainer(item: selectedItem) { item in
                    copyItem(item)
                } onDelete: { item in
                    deleteItem(item)
                } onToggleFavorite: { item in
                    toggleFavorite(item)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            // 如果有初始选中的条目 ID，则选中该条目
            if let itemId = initialSelectedItemId {
                if let item = historyStore.items.first(where: { $0.id == itemId }) {
                    selectedItem = item
                }
            }
        }
        .confirmationDialog("确定要删除选中的 \(selectedItemIds.count) 条记录吗？", isPresented: $showBatchDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                for itemId in selectedItemIds {
                    historyStore.delete(id: itemId)
                }
                selectedItemIds.removeAll()
                withAnimation {
                    isEditMode = false
                }
                if selectedItemIds.contains(selectedItem?.id ?? 0) {
                    selectedItem = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销")
        }
    }

    private var editModeDetailView: some View {
        VStack(spacing: 24) {
            // 编辑模式工具栏
            VStack(spacing: 16) {
                HStack {
                    Button("全选") {
                        if selectedItemIds.count == historyStore.items.count {
                            selectedItemIds.removeAll()
                        } else {
                            selectedItemIds = Set(historyStore.items.map { $0.id })
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("已选 \(selectedItemIds.count) 项")
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("取消") {
                        withAnimation {
                            isEditMode = false
                            selectedItemIds.removeAll()
                        }
                    }
                    .buttonStyle(.bordered)

                    if !selectedItemIds.isEmpty {
                        Button(role: .destructive, action: {
                            showBatchDeleteConfirmation = true
                        }) {
                            Text("删除")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Divider()
            }

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("编辑模式")
                    .font(.headline)

                Text("在左侧列表中点击项目进行选择")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func makeGroups() -> [HistoryGroup] {
        let items = searchText.isEmpty ? historyStore.items : historyStore.search(query: searchText)
        let calendar = Calendar.current
        let now = Date()

        var todayItems: [HistoryItem] = []
        var yesterdayItems: [HistoryItem] = []
        var thisWeekItems: [HistoryItem] = []
        var olderItems: [HistoryItem] = []

        for item in items {
            if calendar.isDateInToday(item.createdAt) {
                todayItems.append(item)
            } else if calendar.isDateInYesterday(item.createdAt) {
                yesterdayItems.append(item)
            } else if calendar.isDate(item.createdAt, equalTo: now, toGranularity: .weekOfYear) {
                thisWeekItems.append(item)
            } else {
                olderItems.append(item)
            }
        }

        var result: [HistoryGroup] = []
        if !todayItems.isEmpty { result.append(HistoryGroup(id: "today", title: "今天", items: todayItems)) }
        if !yesterdayItems.isEmpty { result.append(HistoryGroup(id: "yesterday", title: "昨天", items: yesterdayItems)) }
        if !thisWeekItems.isEmpty { result.append(HistoryGroup(id: "week", title: "本周", items: thisWeekItems)) }
        if !olderItems.isEmpty { result.append(HistoryGroup(id: "older", title: "更早", items: olderItems)) }

        return result
    }

    private func copyItem(_ item: HistoryItem) {
        let text = item.polished ?? item.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let content = UNMutableNotificationContent()
        content.title = "已复制"
        content.body = String(text.prefix(50)) + (text.count > 50 ? "..." : "")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }

    private func deleteItem(_ item: HistoryItem) {
        historyStore.delete(id: item.id)
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
    }

    private func toggleFavorite(_ item: HistoryItem) {
        historyStore.toggleFavorite(id: item.id)
        // 更新 selectedItem 以触发 UI 刷新
        if let updatedItem = historyStore.items.first(where: { $0.id == item.id }) {
            selectedItem = updatedItem
        }
    }
}

// MARK: - History List View

struct HistoryListView: View {
    let groups: [HistoryGroup]
    @Binding var selectedItem: HistoryItem?
    let isEmpty: Bool
    @Binding var searchText: String
    var isEditMode: Bool = false
    @Binding var selectedItemIds: Set<Int64>
    var onEnterEditMode: () -> Void = {}

    var body: some View {
        listView
            .listStyle(.sidebar)
            .navigationTitle("历史记录")
            .searchable(text: $searchText, prompt: "搜索历史记录")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if !isEmpty && !isEditMode {
                        Button(action: onEnterEditMode) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 14))
                        }
                        .help("编辑")
                    }
                }
            }
            .overlay {
                if isEmpty {
                    emptyView
                }
            }
    }

    private var listView: some View {
        List(selection: Binding(
            get: { selectedItem?.id },
            set: { newId in
                if isEditMode {
                    // 编辑模式下不改变选中项
                    return
                }
                if let id = newId {
                    selectedItem = groups.flatMap { $0.items }.first { $0.id == id }
                } else {
                    selectedItem = nil
                }
            }
        )) {
            ForEach(groups) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.items) { item in
                        if isEditMode {
                            EditableHistoryRowView(
                                item: item,
                                isChecked: selectedItemIds.contains(item.id)
                            ) {
                                if selectedItemIds.contains(item.id) {
                                    selectedItemIds.remove(item.id)
                                } else {
                                    selectedItemIds.insert(item.id)
                                }
                            }
                        } else {
                            HistoryRowView(item: item)
                                .tag(item.id)
                        }
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无历史记录", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("开始使用语音输入后，记录将显示在这里")
        }
    }
}

// MARK: - Editable History Row View

struct EditableHistoryRowView: View {
    let item: HistoryItem
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 选择框
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isChecked ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(previewText)
                            .font(.body)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                        Spacer()

                        // 收藏图标
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }

                        Text(timeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if item.polished != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.caption2)
                            Text("已润色").font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: item.createdAt)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: item.createdAt)
    }

    private var previewText: String {
        let text = item.polished ?? item.text
        return text.count <= 60 ? text : String(text.prefix(60)) + "..."
    }
}

// MARK: - History Detail Container

struct HistoryDetailContainer: View {
    let item: HistoryItem?
    let onCopy: (HistoryItem) -> Void
    let onDelete: (HistoryItem) -> Void
    let onToggleFavorite: (HistoryItem) -> Void

    var body: some View {
        if let item = item {
            HistoryDetailView(
                item: item,
                onCopy: { onCopy(item) },
                onDelete: { onDelete(item) },
                onToggleFavorite: { onToggleFavorite(item) }
            )
        } else {
            ContentUnavailableView(
                "选择一条记录",
                systemImage: "text.alignleft",
                description: Text("从左侧列表选择一条记录查看详情")
            )
        }
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    let item: HistoryItem
    @State private var showDeleteConfirmation = false
    @State private var showCopySuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(previewText)
                    .font(.body)
                    .lineLimit(2)
                Spacer()

                // 收藏图标
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }

                // 日期和时间（上下堆叠）
                VStack(alignment: .trailing, spacing: 1) {
                    Text(dateString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(timeString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            if item.polished != nil {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.caption2)
                    Text("已润色").font(.caption2)
                }
                .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            // 右键菜单
            Button(action: {
                copyText()
            }) {
                Label("复制全文", systemImage: "doc.on.doc")
            }

            Button(action: {
                HistoryStore.shared.toggleFavorite(id: item.id)
            }) {
                Label(
                    item.isFavorite ? "取消收藏" : "收藏",
                    systemImage: item.isFavorite ? "star.fill" : "star"
                )
            }

            Divider()

            Button(role: .destructive, action: {
                showDeleteConfirmation = true
            }) {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog("确定要删除此记录吗？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                HistoryStore.shared.delete(id: item.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复")
        }
        .overlay(
            Group {
                if showCopySuccess {
                    Text("已复制")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(6)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopySuccess = false
                                }
                            }
                        }
                }
            }
            , alignment: .center
        )
    }

    private func copyText() {
        let text = item.polished ?? item.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            showCopySuccess = true
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: item.createdAt)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: item.createdAt)
    }

    private var previewText: String {
        let text = item.polished ?? item.text
        return text.count <= 60 ? text : String(text.prefix(60)) + "..."
    }
}

// MARK: - History Detail View

struct HistoryDetailView: View {
    let item: HistoryItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateString).font(.subheadline).foregroundColor(.secondary)
                        if item.polished != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("AI 已润色")
                            }
                            .font(.caption).foregroundColor(.blue)
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        // 收藏按钮
                        Button(action: onToggleFavorite) {
                            Label(
                                item.isFavorite ? "取消收藏" : "收藏",
                                systemImage: item.isFavorite ? "star.fill" : "star"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(item.isFavorite ? .yellow : nil)

                        Button(action: onCopy) { Label("复制", systemImage: "doc.on.doc") }
                            .buttonStyle(.bordered)
                        Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
                            .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Content
                if let polished = item.polished {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原文").font(.headline).foregroundColor(.secondary)
                            Text(item.text).font(.body).padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1)).cornerRadius(8)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").foregroundColor(.blue)
                                Text("润色结果").font(.headline).foregroundColor(.secondary)
                            }
                            Text(polished).font(.body).padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.08)).cornerRadius(8)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("转录结果").font(.headline).foregroundColor(.secondary)
                        Text(item.text).font(.body).padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1)).cornerRadius(8).textSelection(.enabled)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: item.createdAt)
    }
}

// MARK: - History Window Manager

@MainActor
final class HistoryWindowManager {
    static let shared = HistoryWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "历史记录"
        newWindow.contentView = NSHostingView(rootView: HistoryView())
        newWindow.center()
        newWindow.setFrameAutosaveName("HistoryWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
}

// MARK: - Preview

#Preview {
    HistoryView().frame(width: 800, height: 500)
}
