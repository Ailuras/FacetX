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
            HStack {
                Label(item.kind == .reminder ? "Reminder Detail" : "Event Detail",
                      systemImage: item.kind == .reminder ? "list.bullet" : "calendar")
                    .font(.system(size: 11, weight: .semibold))
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
            .padding(.top, 13)
            .padding(.bottom, 11)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("What needs doing?", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    
                    VStack(spacing: 10) {
                        inspectorRow(label: item.kind == .reminder ? "List" : "Calendar", icon: item.kind == .reminder ? "list.bullet" : "calendar") {
                            Picker("", selection: $containerName) {
                                ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(maxWidth: 172)
                        }
                        
                        Divider().opacity(0.3)
                        
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
                                .frame(width: 156)
                            }
                            Divider().opacity(0.3)
                        }
                        
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
                        
                        inspectorRow(label: "URL", icon: "link") {
                            HStack(spacing: 6) {
                                TextField("Link associated...", text: $urlString)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(FacetTheme.panel.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                    .background(FacetTheme.quietPanel)
                    .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                    
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
                                .frame(minHeight: 190)
                        }
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                                .stroke(FacetTheme.hairline, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            HStack {
                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            .background(FacetTheme.canvas)
        }
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
    }
    
    private func inspectorRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            
            Spacer()
            
            content()
        }
        .padding(.vertical, 3)
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
