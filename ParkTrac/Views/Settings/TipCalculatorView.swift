import SwiftUI

/// Pure math behind the tip calculator — kept separate from the view so it's testable.
struct TipCalculator: Equatable {
    let bill: Double
    let tipPercent: Double
    let people: Int

    var tipAmount: Double { bill * tipPercent / 100 }
    var total: Double { bill + tipAmount }
    var perPerson: Double { people > 0 ? total / Double(people) : total }
}

/// Settings → Tools: a quick tip/split calculator in the resort's currency, for table service
/// dining (quick service rarely takes tips at these resorts).
struct TipCalculatorView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("tipCalculatorPercent") private var tipPercent: Double = 18
    @State private var billText: String = ""
    @State private var people: Int = 1

    private static let quickPercents: [Double] = [15, 18, 20, 25]

    private var bill: Double { Double(billText) ?? 0 }
    private var result: TipCalculator { TipCalculator(bill: bill, tipPercent: tipPercent, people: people) }
    private var currencyCode: String { appState.selectedResort.currencyCode }

    var body: some View {
        Form {
            Section("Bill") {
                HStack {
                    Text(currencyCode == "JPY" ? "¥" : "$")
                        .foregroundStyle(.secondary)
                    TextField("0", text: $billText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                }
            }

            Section("Tip") {
                Picker("Tip", selection: $tipPercent) {
                    ForEach(Self.quickPercents, id: \.self) { pct in
                        Text("\(Int(pct))%").tag(pct)
                    }
                }
                .pickerStyle(.segmented)
                Stepper("Custom: \(Int(tipPercent))%", value: $tipPercent, in: 0...100, step: 1)
            }

            Section("Split") {
                Stepper("\(people) \(people == 1 ? "person" : "people")", value: $people, in: 1...20)
            }

            Section {
                resultRow(label: "Tip", value: result.tipAmount)
                resultRow(label: "Total", value: result.total, bold: true)
                if people > 1 {
                    resultRow(label: "Per Person", value: result.perPerson, bold: true, color: .blue)
                }
            }
        }
        .navigationTitle("Tip Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultRow(label: String, value: Double, bold: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value, format: .currency(code: currencyCode))
                .font(bold ? .title3.weight(.bold) : .body)
                .foregroundStyle(color)
        }
    }
}
