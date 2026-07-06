import SwiftUI
import SwiftData

struct AddEditEventView: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext
    let existingEvent: CalendarEvent?

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var notes: String

    init(startDate: Date = Date(), modelContext: ModelContext) {
        self.modelContext = modelContext
        self.existingEvent = nil
        let end = startDate.addingTimeInterval(3600)
        _title = State(initialValue: "")
        _startDate = State(initialValue: startDate)
        _endDate = State(initialValue: end)
        _isAllDay = State(initialValue: false)
        _location = State(initialValue: "")
        _notes = State(initialValue: "")
    }

    init(event: CalendarEvent, modelContext: ModelContext) {
        self.modelContext = modelContext
        self.existingEvent = event
        _title = State(initialValue: event.title)
        _startDate = State(initialValue: event.startDate)
        _endDate = State(initialValue: event.endDate)
        _isAllDay = State(initialValue: event.isAllDay)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.body)
                }

                Section {
                    Toggle("All-day", isOn: $isAllDay)

                    if isAllDay {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Location") {
                    TextField("Add location", text: $location)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(existingEvent == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        if let event = existingEvent {
            event.title = trimmedTitle
            event.startDate = startDate
            event.endDate = endDate
            event.isAllDay = isAllDay
            event.location = location.isEmpty ? nil : location
            event.notes = notes.isEmpty ? nil : notes
            event.isDirty = true
            event.modifiedAt = Date()
        } else {
            let event = CalendarEvent(
                title: trimmedTitle,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                notes: notes.isEmpty ? nil : notes,
                location: location.isEmpty ? nil : location
            )
            modelContext.insert(event)
        }

        try? modelContext.save()
        dismiss()
    }
}
