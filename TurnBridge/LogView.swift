import SwiftUI
import Combine

struct LogView: View {
    @State private var entries: [LogEntry] = []
    @State private var searchText = ""
    @State private var selectedSource: LogSource? = nil
    @State private var minimumLevel: LogLevel = .debug
    @State private var autoScroll = true
    @State private var showFilters = false
    @State private var monitoringTask: Task<Void, Never>? = nil

    var filteredEntries: [LogEntry] {
        entries.filter { entry in
            guard entry.level >= minimumLevel else { return false }
            if let source = selectedSource, entry.source != source { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return entry.message.lowercased().contains(query)
                    || entry.source.rawValue.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filteredEntries.isEmpty {
                emptyStateView
            } else {
                logListView
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: copyLogs) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                if let logURL = SharedLogger.logFileURL {
                    ShareLink(item: logURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                }
                Button(action: { SharedLogger.clearLogs(); entries = [] }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            loadLogs()
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        monitoringTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    loadLogs()
                } catch {
                    break
                }
            }
        }
    }

    private func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func loadLogs() {
        let newEntries = SharedLogger.readEntries()
        if newEntries.count != entries.count {
            entries = newEntries
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField("Search logs...", text: $searchText)
                        .font(.system(size: 14))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(10)

                Button(action: { withAnimation { showFilters.toggle() } }) {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(hasActiveFilters ? .blue : .secondary)
                }

                Button(action: { autoScroll.toggle() }) {
                    Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                        .foregroundColor(autoScroll ? .blue : .secondary)
                }
            }

            if showFilters {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Source:").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        filterChip("All", isActive: selectedSource == nil) { selectedSource = nil }
                        ForEach(LogSource.allCases, id: \.self) { source in
                            filterChip(source.displayName, isActive: selectedSource == source) { selectedSource = source }
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Text("Level:").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            filterChip("\(level.icon)", isActive: minimumLevel == level) { minimumLevel = level }
                        }
                        Spacer()
                    }
                }
                .transition(.opacity)
            }

            HStack {
                Text("\(filteredEntries.count) of \(entries.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if hasActiveFilters {
                    Button("Clear") {
                        selectedSource = nil
                        minimumLevel = .debug
                        searchText = ""
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.offset) { index, entry in
                        logRow(entry)
                            .id(index)
                            .contextMenu {
                                Button(action: { UIPasteboard.general.string = entry.rawLine }) {
                                    Label("Copy Line", systemImage: "doc.on.doc")
                                }
                                Button(action: { UIPasteboard.general.string = entry.message }) {
                                    Label("Copy Message", systemImage: "text.quote")
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .onChange(of: filteredEntries.count) { _ in
                if autoScroll && !filteredEntries.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(filteredEntries.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(timeString(entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(entry.level.icon)
                .font(.system(size: 10))
                .frame(width: 16)

            Text(entry.source.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(sourceColor(entry.source))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(sourceColor(entry.source).opacity(0.15))
                .cornerRadius(3)
                .frame(width: 30)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(levelColor(entry.level))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(entry.level == .error ? Color.red.opacity(0.06) : Color.clear)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            if !SharedLogger.isAvailable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.orange.opacity(0.7))
                Text("Logging unavailable")
                    .font(.system(size: 16, weight: .medium))
                Text("Could not detect App Group from binary entitlements. Your signing method may not embed entitlements properly.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: entries.isEmpty ? "doc.text" : "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(entries.isEmpty ? "No logs yet" : "No matches")
                    .font(.system(size: 16, weight: .medium))
                Text(entries.isEmpty ? "Logs appear when you connect." : "Try adjusting filters.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.blue.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
                .foregroundColor(isActive ? .blue : .secondary)
                .cornerRadius(6)
        }
    }

    private var hasActiveFilters: Bool {
        selectedSource != nil || minimumLevel != .debug || !searchText.isEmpty
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func sourceColor(_ source: LogSource) -> Color {
        switch source {
        case .app: return .blue
        case .tunnel: return .purple
        case .wireguard: return .green
        }
    }

    private func copyLogs() {
        let text = filteredEntries.map { $0.rawLine }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }
}
