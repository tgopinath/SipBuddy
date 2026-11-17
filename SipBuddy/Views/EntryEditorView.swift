import SwiftUI

/// Edit (or create) one water entry: amount and time.
struct EntryEditorView: View {
    @EnvironmentObject var settings: SettingsManager
    let entry: WaterEntry
    var isNew: Bool
    var onSave: (WaterEntry) -> Void
    var onDelete: (() -> Void)?
    var onCancel: () -> Void

    @State private var amount: Double = 0
    @State private var time = Date()

    private var ml: Int { settings.unit.ml(from: amount) }
    private var isValid: Bool { ml > 0 && ml <= 5000 && time <= Date().addingTimeInterval(60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "Add entry" : "Edit entry")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text(settings.unit.symbol).foregroundStyle(.secondary)
                Spacer()
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            HStack(spacing: 6) {
                ForEach([150, 250, 330, 500], id: \.self) { preset in
                    Button(settings.unit.format(preset)) { amount = settings.unit.value(fromML: preset) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if time > Date().addingTimeInterval(60) {
                Text("Entries can't be in the future.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    var updated = entry
                    updated.amountML = ml
                    updated.date = time
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .controlSize(.small)
        }
        .onAppear {
            amount = settings.unit.value(fromML: entry.amountML)
            time = entry.date
        }
    }
}
