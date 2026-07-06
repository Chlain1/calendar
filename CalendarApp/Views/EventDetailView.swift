import SwiftUI
import SwiftData

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    let modelContext: ModelContext

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(event.color)
                            .frame(width: 4, height: 44)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.title3.weight(.semibold))
                            Text(dateRangeLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                if let location = event.location, !location.isEmpty {
                    Section("Location") {
                        Label(location, systemImage: "mappin.circle")
                    }
                }

                if let notes = event.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.body)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Event", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
            .sheet(isPresented: $showingEdit) {
                AddEditEventView(event: event, modelContext: modelContext)
            }
            .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
            }
        }
    }

    private var dateRangeLabel: String {
        if event.isAllDay {
            let fmt = DateFormatter()
            fmt.dateStyle = .full
            fmt.timeStyle = .none
            return fmt.string(from: event.startDate)
        }
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .full
        dateFmt.timeStyle = .none
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let same = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
        if same {
            return "\(dateFmt.string(from: event.startDate)), \(timeFmt.string(from: event.startDate)) – \(timeFmt.string(from: event.endDate))"
        }
        return "\(dateFmt.string(from: event.startDate)) \(timeFmt.string(from: event.startDate)) – \(dateFmt.string(from: event.endDate)) \(timeFmt.string(from: event.endDate))"
    }

    private func deleteEvent() {
        event.isDeleted = true
        event.isDirty = true
        event.modifiedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
