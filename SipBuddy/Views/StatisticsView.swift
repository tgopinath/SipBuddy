import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var settings: SettingsManager

    @State private var range: StatsRange = .week
    @State private var monthAnchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var chartSelection: Date?
    @State private var appeared = false

    private var vm: StatisticsViewModel {
        StatisticsViewModel(entries: hydration.entries, goal: settings.dailyGoalML,
                            range: range, monthAnchor: monthAnchor)
    }

    var body: some View {
        let vm = vm
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statGrid(vm)
                chartCard(vm)
                HStack(alignment: .top, spacing: 20) {
                    DayDetailCard(day: $selectedDay)
                        .frame(maxWidth: .infinity)
                    MonthHeatmap(month: monthAnchor, totals: vm.totals, goal: vm.goal, selectedDay: $selectedDay)
                        .frame(width: 300)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            appeared = false
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { appeared = true }
        }
        .onChange(of: range) { _, _ in replayChart() }
        .onChange(of: monthAnchor) { _, _ in replayChart() }
        .onChange(of: chartSelection) { _, newValue in
            if let d = newValue { selectedDay = Calendar.current.startOfDay(for: d) }
        }
        .onChange(of: selectedDay) { _, day in
            if !Calendar.current.isDate(day, equalTo: monthAnchor, toGranularity: .month) { monthAnchor = day }
        }
    }

    private func replayChart() {
        appeared = false
        withAnimation(.easeOut(duration: 0.7)) { appeared = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your hydration")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Every sip, all in one place.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Stat cards

    private func statGrid(_ vm: StatisticsViewModel) -> some View {
        let unit = settings.unit
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            StatCard(symbol: "drop.fill", title: "Today", value: unit.format(vm.todayTotal),
                     caption: "of \(unit.format(vm.goal))")
            StatCard(symbol: "target", title: "Goal completion", value: "\(vm.todayPercent)%",
                     caption: vm.todayPercent >= 100 ? "Goal reached 🎉" : "Keep going!")
            StatCard(symbol: "cup.and.saucer.fill", title: "Glasses today", value: "\(vm.glassesToday)",
                     caption: vm.glassesToday == 1 ? "entry logged" : "entries logged")
            StatCard(symbol: "flame.fill", title: "Streak", value: "\(vm.streak) \(vm.streak == 1 ? "day" : "days")",
                     caption: "goal met in a row")
            StatCard(symbol: "chart.line.uptrend.xyaxis", title: "Daily average", value: unit.format(vm.average30),
                     caption: "last 30 days")
            StatCard(symbol: "trophy.fill", title: "Best day",
                     value: vm.best.map { unit.format($0.totalML) } ?? "—",
                     caption: vm.best.map { $0.date.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "No data yet")
        }
    }

    // MARK: Chart

    private func chartCard(_ vm: StatisticsViewModel) -> some View {
        let unit = settings.unit
        let accent = settings.accent.color
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(range == .week ? "Last 7 days" : monthAnchor.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(unit.format(vm.rangeTotal)) total · goal met on \(vm.daysMetInRange) \(vm.daysMetInRange == 1 ? "day" : "days")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if range == .month {
                    HStack(spacing: 2) {
                        IconButton(symbol: "chevron.left", help: "Previous month") { shiftMonth(-1) }
                        IconButton(symbol: "chevron.right", help: "Next month") { shiftMonth(1) }
                            .disabled(Calendar.current.isDate(monthAnchor, equalTo: Date(), toGranularity: .month))
                    }
                }
                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            Chart {
                ForEach(vm.chartDays) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Intake", appeared ? unit.value(fromML: day.totalML) : 0)
                    )
                    .foregroundStyle(day.metGoal
                                     ? AnyShapeStyle(LinearGradient(colors: [Theme.aqua, accent], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(accent.opacity(0.35)))
                    .cornerRadius(range == .week ? 8 : 4)
                    .opacity(Calendar.current.isDate(day.date, inSameDayAs: selectedDay) ? 1 : 0.8)
                }
                RuleMark(y: .value("Goal", unit.value(fromML: vm.goal)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(unit.format(vm.goal))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...max(unit.value(fromML: vm.goal) * 1.2,
                                          unit.value(fromML: vm.chartDays.map(\.totalML).max() ?? 0) * 1.1))
            .chartXAxis {
                if range == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                        AxisGridLine()
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(unit == .liters ? v.formatted(.number.precision(.fractionLength(0...1))) : Int(v).formatted())
                        }
                    }
                }
            }
            .chartXSelection(value: $chartSelection)
            .frame(height: 230)

            Text("Click a bar to see that day's entries.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 18)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = min(d, Date())
        }
    }
}

private struct StatCard: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(.tint.opacity(0.12)))
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Day detail

private struct DayDetailCard: View {
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var settings: SettingsManager
    @Binding var day: Date

    @State private var editing: WaterEntry?
    @State private var adding: WaterEntry?

    private var cal: Calendar { .current }

    var body: some View {
        let entries = hydration.entries(on: day)
        let total = entries.reduce(0) { $0 + $1.amountML }
        let progress = settings.dailyGoalML > 0 ? Double(total) / Double(settings.dailyGoalML) : 0

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconButton(symbol: "chevron.left", help: "Previous day") { move(-1) }
                VStack(spacing: 1) {
                    Text(dayTitle).font(.system(size: 15, weight: .semibold))
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                IconButton(symbol: "chevron.right", help: "Next day") { move(1) }
                    .disabled(cal.isDateInToday(day))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(settings.unit.format(total))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("of \(settings.unit.format(settings.dailyGoalML))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.waterGradient(settings.accent.color))
                            .frame(width: geo.size.width * min(progress, 1))
                    }
                }
                .frame(height: 8)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            }

            if let entry = editing ?? adding {
                EntryEditorView(entry: entry, isNew: adding != nil, onSave: { updated in
                    if adding != nil {
                        hydration.add(updated.amountML, at: updated.date, announce: false)
                    } else {
                        hydration.update(updated)
                    }
                    editing = nil; adding = nil
                }, onDelete: adding == nil ? {
                    hydration.delete(entry)
                    editing = nil
                } : nil, onCancel: { editing = nil; adding = nil })
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
            }

            if entries.isEmpty {
                Text(cal.isDateInToday(day) ? "Nothing logged yet today." : "No water logged on this day.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(entries.reversed()) { entry in
                        EntryRow(entry: entry, onEdit: { adding = nil; editing = entry },
                                 onDelete: { hydration.delete(entry) })
                    }
                }
            }

            Button {
                editing = nil
                let time: Date = cal.isDateInToday(day)
                    ? Date()
                    : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
                adding = WaterEntry(amountML: settings.defaultGlassML, date: time)
            } label: {
                Label("Add entry", systemImage: "plus")
            }
            .buttonStyle(SoftButtonStyle())
        }
        .card(padding: 18)
        .onChange(of: day) { _, _ in editing = nil; adding = nil }
    }

    private var dayTitle: String {
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private func move(_ delta: Int) {
        if let d = cal.date(byAdding: .day, value: delta, to: day), d <= Date() {
            day = cal.startOfDay(for: d)
        }
    }
}

// MARK: - Month heatmap

private struct MonthHeatmap: View {
    @EnvironmentObject var settings: SettingsManager
    let month: Date
    let totals: [Date: Int]
    let goal: Int
    @Binding var selectedDay: Date

    private var cal: Calendar { .current }

    var body: some View {
        let days = StatisticsManager.daysInMonth(containing: month)
        let leading = days.first.map { (cal.component(.weekday, from: $0) - cal.firstWeekday + 7) % 7 } ?? 0
        let symbols = Array(cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1)...] + cal.veryShortWeekdaySymbols[..<(cal.firstWeekday - 1)])
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        VStack(alignment: .leading, spacing: 12) {
            Text("Month at a glance")
                .font(.system(size: 15, weight: .semibold))
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(days, id: \.self) { day in
                    cell(day)
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.system(size: 10)).foregroundStyle(.tertiary)
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(color(for: level)).frame(width: 12, height: 12)
                }
                Text("Goal").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .card(padding: 18)
    }

    private func cell(_ day: Date) -> some View {
        let total = totals[cal.startOfDay(for: day)] ?? 0
        let level = goal > 0 ? Double(total) / Double(goal) : 0
        let isFuture = day > Date()
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        return Button {
            if !isFuture { selectedDay = cal.startOfDay(for: day) }
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(level >= 0.6 ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 7).fill(color(for: level)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.primary.opacity(0.6) : .clear, lineWidth: 1.5))
                .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(settings.unit.format(total))")
    }

    private func color(for level: Double) -> Color {
        if level <= 0 { return Theme.track }
        let accent = settings.accent.color
        if level >= 1 { return accent }
        return accent.opacity(0.2 + 0.6 * level)
    }
}
