import SwiftUI
import EventKit

struct ItemDetailPane: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    
    let item: ProjectItem
    let project: Project
    let onClose: () -> Void
    let onUpdate: () -> Void
    
    @State private var content = ""
    @State private var notes = ""
    @State private var priority = 0
    @State private var useDate = false
    @State private var date = Date()
    @State private var urlString = ""
    @State private var containerName = ""
    @State private var saving = false
    
    private var hasChanges: Bool {
        if content.trimmingCharacters(in: .whitespaces) != item.content { return true }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines) != (item.notes ?? "") { return true }
        if priority != item.priority { return true }
        let itemHasDate = item.date != nil
        if useDate != itemHasDate { return true }
        if useDate, let d = item.date, Calendar.current.compare(date, to: d, toGranularity: .minute) != .orderedSame { return true }
        if containerName != item.containerName { return true }
        if urlString.trimmingCharacters(in: .whitespaces) != (item.url?.absoluteString ?? "") { return true }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label(item.kind == .reminder ? "Reminder Detail" : "Event Detail",
                      systemImage: item.kind == .reminder ? "list.bullet" : "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Inline Title editor (borderless & prominent)
                    TextField("What needs doing?", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                    
                    // Properties Card (Figma/Xcode property inspector style)
                    VStack(spacing: 10) {
                        // Container (List or Calendar)
                        inspectorRow(label: item.kind == .reminder ? "List" : "Calendar", icon: item.kind == .reminder ? "list.bullet" : "calendar") {
                            Picker("", selection: $containerName) {
                                ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(maxWidth: 160)
                        }
                        
                        Divider().opacity(0.3)
                        
                        // Priority (Reminders only)
                        if item.kind == .reminder {
                            inspectorRow(label: "Priority", icon: "exclamationmark.circle") {
                                Picker("", selection: $priority) {
                                    Text("None").tag(0)
                                    Text("Low").tag(9)
                                    Text("Med").tag(5)
                                    Text("High").tag(1)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 150)
                            }
                            Divider().opacity(0.3)
                        }
                        
                        // Date Picker
                        inspectorRow(label: item.kind == .reminder ? "Due Date" : "Start Date", icon: "calendar") {
                            HStack(spacing: 6) {
                                Toggle("", isOn: $useDate)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .controlSize(.small)
                                
                                if useDate {
                                    DatePicker("", selection: $date,
                                               displayedComponents: item.kind == .reminder ? [.date] : [.date, .hourAndMinute])
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .controlSize(.small)
                                }
                            }
                        }
                        
                        Divider().opacity(0.3)
                        
                        // URL
                        inspectorRow(label: "URL", icon: "link") {
                            HStack(spacing: 6) {
                                TextField("Link associated...", text: $urlString)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                
                                if let parsedURL = URL(string: urlString.trimmingCharacters(in: .whitespaces)), !urlString.isEmpty {
                                    Link(destination: parsedURL) {
                                        Image(systemName: "arrow.up.right.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open link")
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                    
                    // Notes / Description
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notes", systemImage: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        ZStack(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Add notes and details here...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                            
                            TextEditor(text: $notes)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(minHeight: 160)
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
                .padding(14)
            }
            
            Divider()
            
            // Actions (Bottom Bar)
            HStack {
                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Delete item")
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasChanges || content.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
    }
    
    // Row style helper for Figma-like property panel
    private func inspectorRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            content()
        }
        .padding(.vertical, 2)
    }
    
    private var containerOptions: [String] {
        switch item.kind {
        case .reminder:
            return ek.reminderListNames(enabled: settings.enabledContainerNames)
        case .event:
            return ek.calendarNames(enabled: settings.enabledContainerNames)
        }
    }
    
    private func loadFields() {
        content = item.content
        notes = item.notes ?? ""
        priority = item.priority
        containerName = item.containerName
        urlString = item.url?.absoluteString ?? ""
        if let d = item.date {
            useDate = true
            date = d
        } else {
            useDate = false
            date = Date()
        }
    }
    
    private func saveChanges() {
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !containerName.isEmpty else { return }
        
        saving = true
        let urlParam = URL(string: urlString.trimmingCharacters(in: .whitespaces))
        
        let ok = ek.updateItem(id: item.id, project: project.prefix, content: text,
                               date: useDate ? date : nil, useDate: useDate,
                               containerName: containerName, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                               priority: priority, url: urlParam)
        saving = false
        if ok {
            onUpdate()
        }
    }
    
    private func deleteItem() {
        saving = true
        let ok = ek.deleteItem(id: item.id)
        saving = false
        if ok {
            onUpdate()
            onClose()
        }
    }
}
