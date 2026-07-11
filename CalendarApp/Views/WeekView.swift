import SwiftUI
import SwiftData

// MARK: - Layout helpers

struct EventLayout: Identifiable {
    let id: UUID
    let event: CalendarEvent
    let column: Int
    let totalColumns: Int
}

func layoutEvents(_ events: [CalendarEvent]) -> [EventLayout] {
    let sorted = events.sorted { $0.startDate < $1.startDate }
    var layouts: [EventLayout] = []
    var columns: [[CalendarEvent]] = [] // active column queues

    for event in sorted {
        var placed = false
        for col in 0..<columns.count {
            if let last = columns[col].last, last.endDate <= event.startDate {
                columns[col].append(event)
                placed = true
                break
            }
        }
        if !placed {
            columns.append([event])
        }
    }

    // Determine group width (max overlapping count in time slice)
    for (col, colEvents) in columns.enumerated() {
        for event in colEvents {
            // Count how many columns overlap with this event's time
            let overlapping = columns.filter { colQ in
                colQ.contains { $0.startDate < event.endDate && $0.endDate > event.startDate }
            }.count
            layouts.append(EventLayout(id: event.id, event: event, column: col, totalColumns: overlapping))
        }
    }
    return layouts
}

// MARK: - Main WeekView

struct WeekView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CalendarEvent> { !$0.isDeleted }) private var allEvents: [CalendarEvent]
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = CalendarViewModel()
    @State private var dragTranslation: CGFloat = 0
    @State private var pagerWidth: CGFloat = 390

    let hourHeight: CGFloat = 60
    let timeColumnWidth: CGFloat = 52
    let allDayRowHeight: CGFloat = 28

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekNavigationHeader
                Divider()
                weekPager
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.showingAddEvent) {
                AddEditEventView(startDate: viewModel.newEventStartDate, modelContext: modelContext)
            }
            .sheet(isPresented: $viewModel.showingEventDetail) {
                if let event = viewModel.selectedEvent {
                    EventDetailView(event: event, modelContext: modelContext)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var weekNavigationHeader: some View {
        HStack {
            Button(action: { commitSwipe(next: false) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekTitle)
                    .font(.headline)
                Text("Week \(viewModel.weekNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if syncManager.isSyncing {
                ProgressView().scaleEffect(0.8)
            }
            if !viewModel.isCurrentWeek {
                Button("Today") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToToday()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.tint)
            }

            Button(action: { commitSwipe(next: true) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Week pager (swipe navigation)

    /// Lays out the previous, current and next week side by side and drags them
    /// together with the finger, snapping to the nearest week on release —
    /// mirroring the interactive paging feel of Apple's Calendar app.
    private var weekPager: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            HStack(spacing: 0) {
                weekPageContent(days: viewModel.weekDays(from: viewModel.previousWeekStart))
                    .frame(width: pageWidth, height: geo.size.height)
                weekPageContent(days: viewModel.weekDays)
                    .frame(width: pageWidth, height: geo.size.height)
                weekPageContent(days: viewModel.weekDays(from: viewModel.nextWeekStart))
                    .frame(width: pageWidth, height: geo.size.height)
            }
            .offset(x: -pageWidth + dragTranslation)
            .frame(width: pageWidth, height: geo.size.height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(weekSwipeGesture(pageWidth: pageWidth))
            .onAppear { pagerWidth = pageWidth }
            .onChange(of: pageWidth) { _, newValue in pagerWidth = newValue }
        }
    }

    private func weekSwipeGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                // Only follow clearly horizontal drags, so vertical scrolling
                // in the time grid underneath keeps working normally.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.2 else {
                    cancelSwipe()
                    return
                }
                let threshold = pageWidth * 0.25
                let flungForward = value.predictedEndTranslation.width < -pageWidth * 0.6
                let flungBackward = value.predictedEndTranslation.width > pageWidth * 0.6

                if horizontal < 0 && (horizontal < -threshold || flungForward) {
                    commitSwipe(next: true)
                } else if horizontal > 0 && (horizontal > threshold || flungBackward) {
                    commitSwipe(next: false)
                } else {
                    cancelSwipe()
                }
            }
    }

    private func commitSwipe(next: Bool) {
        let target: CGFloat = next ? -pagerWidth : pagerWidth
        withAnimation(.easeOut(duration: 0.28)) {
            dragTranslation = target
        } completion: {
            if next {
                viewModel.goToNextWeek()
            } else {
                viewModel.goToPreviousWeek()
            }
            dragTranslation = 0
        }
    }

    private func cancelSwipe() {
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
            dragTranslation = 0
        }
    }

    private func weekPageContent(days: [Date]) -> some View {
        VStack(spacing: 0) {
            dayHeaderRow(days: days)
            allDayRow(days: days)
            Divider()
            timeGrid(days: days)
        }
    }

    // MARK: - Day headers

    private func dayHeaderRow(days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 1)

            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(viewModel.dayLabel(for: day))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ZStack {
                        if viewModel.isToday(day) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 30, height: 30)
                        }
                        Text(viewModel.dayNumber(for: day))
                            .font(.system(size: 17, weight: viewModel.isToday(day) ? .semibold : .regular))
                            .foregroundStyle(viewModel.isToday(day) ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - All-day row

    private func allDayRow(days: [Date]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("All-day")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth)

            ForEach(days, id: \.self) { day in
                let dayEvents = viewModel.allDayEvents(for: day, from: allEvents)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dayEvents) { event in
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(event.color.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: allDayRowHeight, alignment: .top)
                .padding(.horizontal, 1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Time grid

    private func timeGrid(days: [Date]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Background hour lines
                    hourLines

                    // Events layer
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeColumnWidth)
                        ForEach(days, id: \.self) { day in
                            dayEventsColumn(for: day)
                        }
                    }

                    // Current time indicator
                    currentTimeIndicator(days: days)
                }
                .frame(height: hourHeight * 24)
                .id("timeGrid")
            }
            .onAppear {
                scrollToCurrentTime(proxy: proxy)
            }
        }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(hourLabel(hour))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                        .padding(.trailing, 6)
                        .offset(y: -7)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour_\(hour)")
            }
        }
    }

    private func dayEventsColumn(for date: Date) -> some View {
        let dayEvents = viewModel.events(for: date, from: allEvents)
        let layouts = layoutEvents(dayEvents)

        return GeometryReader { geo in
            let colWidth = geo.size.width
            ZStack(alignment: .topLeading) {
                // Tap zones per hour
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: hourHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.tapOnTimeSlot(date: date, hour: hour)
                            }
                    }
                }

                // Event blocks
                ForEach(layouts) { layout in
                    let event = layout.event
                    let top = yOffset(for: event.startDate)
                    let height = max(eventHeight(for: event), 22)
                    let width = colWidth / CGFloat(layout.totalColumns)
                    let xOff = width * CGFloat(layout.column)

                    EventBlockView(event: event) {
                        viewModel.tapOnEvent(event)
                    }
                    .frame(width: width - 2, height: height)
                    .offset(x: xOff + 1, y: top)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: hourHeight * 24)
    }

    private func currentTimeIndicator(days: [Date]) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            currentTimeLine(at: context.date, days: days)
        }
    }

    private func currentTimeLine(at now: Date, days: [Date]) -> some View {
        let cal = Calendar.autoupdatingCurrent
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let y = CGFloat(hour) * hourHeight + CGFloat(minute) / 60 * hourHeight

        // Only show if this page's week contains today
        guard days.contains(where: { cal.isDate($0, inSameDayAs: now) }) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 0) {
                Color.clear.frame(width: timeColumnWidth)
                Rectangle()
                    .fill(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
            }
            .offset(y: y - 1)
        )
    }

    // MARK: - Helpers

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(h) * hourHeight + CGFloat(m) / 60 * hourHeight
    }

    private func eventHeight(for event: CalendarEvent) -> CGFloat {
        let seconds = event.endDate.timeIntervalSince(event.startDate)
        return CGFloat(seconds / 3600) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        hour == 0 ? "" : String(format: "%02d:00", hour)
    }

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let hour = max(Calendar.autoupdatingCurrent.component(.hour, from: Date()) - 1, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("hour_\(hour)", anchor: .top)
            }
        }
    }
}

// MARK: - Event block

struct EventBlockView: View {
    let event: CalendarEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if event.duration > 1800 {
                    Text(timeRangeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(event.color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var timeRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }
}
