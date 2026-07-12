import SwiftUI
import SwiftData
import Combine

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = CalendarViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentTime = Date()

    private let clockTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    let hourHeight: CGFloat = 60
    let timeColumnWidth: CGFloat = 52
    let allDayRowHeight: CGFloat = 28

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekNavigationHeader
                debugTimeInfo
                Divider()
                dayHeaderRow
                allDayRow
                Divider()
                timeGrid
            }
            .simultaneousGesture(weekSwipeGesture)
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
            .onReceive(clockTicker) { tick in
                currentTime = tick
            }
            .onAppear {
                currentTime = Date()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // The periodic timer can sit idle while the app is backgrounded
                // and not catch up for up to a minute after returning — snap
                // straight to the real time as soon as the app is active again.
                if newPhase == .active {
                    currentTime = Date()
                }
            }
        }
    }

    // MARK: - Swipe navigation

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Only treat clearly horizontal swipes as week navigation,
                // so vertical scrolling in the time grid keeps working.
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 50 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if horizontal < 0 {
                        viewModel.goToNextWeek()
                    } else {
                        viewModel.goToPreviousWeek()
                    }
                }
            }
    }

    // MARK: - Header

    private var weekNavigationHeader: some View {
        HStack {
            Button(action: { viewModel.goToPreviousWeek() }) {
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
                Button("Today") { viewModel.goToToday() }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }

            Button(action: { viewModel.goToNextWeek() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Temporary debug info (remove once the red-line time bug is found)

    private var debugTimeInfo: some View {
        let now = currentTime
        let cal = Calendar.autoupdatingCurrent
        let tz = TimeZone.autoupdatingCurrent
        let secondsSinceMidnight = now.timeIntervalSince(cal.startOfDay(for: now))
        let computedHour = Int(secondsSinceMidnight / 3600)
        let computedMinute = Int(secondsSinceMidnight.truncatingRemainder(dividingBy: 3600) / 60)

        let iso = ISO8601DateFormatter()
        iso.timeZone = tz
        let localString = iso.string(from: now)

        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        let utcString = utcFormatter.string(from: now)

        let rawNowString = { () -> String in
            let f = ISO8601DateFormatter()
            f.timeZone = tz
            return f.string(from: Date())
        }()

        return VStack(alignment: .leading, spacing: 1) {
            Text("DEBUG raw Date()=\(rawNowString)")
            Text("DEBUG currentTime(state)=\(localString)")
            Text("DEBUG now(UTC)=\(utcString)")
            Text("DEBUG tz=\(tz.identifier) offset=\(tz.secondsFromGMT() / 3600)h")
            Text("DEBUG computed=\(computedHour):\(String(format: "%02d", computedMinute))")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Day headers

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 1)

            ForEach(viewModel.weekDays, id: \.self) { day in
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

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("All-day")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth)

            ForEach(viewModel.weekDays, id: \.self) { day in
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

    private var timeGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Background hour lines
                    hourLines

                    // Events layer
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeColumnWidth)
                        ForEach(viewModel.weekDays, id: \.self) { day in
                            dayEventsColumn(for: day)
                        }
                    }

                    // Current time indicator
                    currentTimeIndicator

                    // TEMP DEBUG: static marker fixed at hour 2, no time logic at all
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeColumnWidth)
                        Rectangle()
                            .fill(Color.blue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 2)
                            .overlay(alignment: .leading) {
                                Text("STATIC hour=2 y=120")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                    .offset(y: -10)
                            }
                    }
                    .offset(y: CGFloat(2) * hourHeight - 1)
                }
                .frame(height: hourHeight * 24)
                .id("timeGrid")
            }
            .onAppear {
                scrollProxy = proxy
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

    private var currentTimeIndicator: some View {
        currentTimeLine(at: currentTime)
    }

    private func currentTimeLine(at now: Date) -> some View {
        let cal = Calendar.autoupdatingCurrent

        // Only show if current week contains today
        guard viewModel.weekDays.contains(where: { cal.isDate($0, inSameDayAs: now) }) else {
            return AnyView(EmptyView())
        }

        // Seconds elapsed since local midnight, rather than extracting .hour/.minute
        // components separately — a single interval computation that can't
        // accidentally land on the wrong half of the day.
        let secondsSinceMidnight = now.timeIntervalSince(cal.startOfDay(for: now))
        let y = CGFloat(secondsSinceMidnight / 3600) * hourHeight

        let debugHour = Int(secondsSinceMidnight / 3600)
        let debugMinute = Int(secondsSinceMidnight.truncatingRemainder(dividingBy: 3600) / 60)

        return AnyView(
            HStack(spacing: 0) {
                Color.clear.frame(width: timeColumnWidth)
                Rectangle()
                    .fill(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        Text("LINE y=\(Int(y)) h=\(debugHour):\(String(format: "%02d", debugMinute))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.orange)
                            .offset(y: -10)
                    }
            }
            .offset(y: y - 1)
            .animation(nil, value: y)
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

    private func scrollToCurrentTime(proxy: ScrollViewProxy? = nil) {
        let now = Date()
        let cal = Calendar.autoupdatingCurrent
        let secondsSinceMidnight = now.timeIntervalSince(cal.startOfDay(for: now))
        let hour = max(Int(secondsSinceMidnight / 3600) - 1, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) {
                (proxy ?? scrollProxy)?.scrollTo("hour_\(hour)", anchor: .top)
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

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    private var timeRangeLabel: String {
        "\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
    }
}
