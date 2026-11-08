import SwiftUI
import Charts

@MainActor
struct ActivityView: View {
    @EnvironmentObject private var state: AppState

    private static let weekdayNames = ["Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let result = state.result {
                        if result.topLiked.isEmpty && result.ownPostsByMonth.isEmpty {
                            EmptyState(title: "Nessun dato di attività",
                                       message: "Nell'export mancava la categoria \"La tua attività su Instagram\". Richiedila e reimporta.",
                                       systemImage: "waveform.path.ecg")
                        } else {
                            attentionCard(result)
                            timingCard(result)
                            activityChart(result)
                        }
                    } else {
                        EmptyState(title: "Nessun dato ancora",
                                   message: "Importa l'export dalla scheda Dati per vedere con chi interagisci e quando pubblichi meglio.",
                                   systemImage: "waveform.path.ecg")
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Attività")
        }
    }

    // MARK: - Attention

    @ViewBuilder
    private func attentionCard(_ result: AnalysisResult) -> some View {
        if !result.topLiked.isEmpty {
            Card(title: "A chi dai più attenzione",
                 footnote: "Conteggio dei tuoi like e commenti verso ciascun account.") {
                VStack(spacing: 8) {
                    ForEach(result.topLiked.prefix(8)) { entry in
                        AccountRow(username: entry.username,
                                   detail: nil,
                                   trailing: entry.count.grouped)
                    }
                }
                NavigationLink {
                    AccountListScreen(title: "Attenzione data",
                                      explanation: "Ordinati per numero di tue interazioni.",
                                      accounts: result.topLiked.map { Account(username: $0.username) },
                                      counts: Dictionary(result.topLiked.map { ($0.username.lowercased(), $0.count) },
                                                         uniquingKeysWith: { first, _ in first }))
                } label: {
                    Label("Vedi tutti", systemImage: "chevron.right.circle")
                        .font(.footnote.weight(.medium))
                }
            }
        }

        if !result.oneWayAttention.isEmpty {
            Card(title: "Attenzione a senso unico",
                 footnote: "Li segui e li commenti o likei, ma non ti seguono.") {
                VStack(spacing: 8) {
                    ForEach(result.oneWayAttention.prefix(6)) { entry in
                        AccountRow(username: entry.username,
                                   detail: nil,
                                   trailing: entry.count.grouped)
                    }
                }
            }
        }

        if !result.silentTowards.isEmpty {
            Card(title: "Follower con cui non interagisci",
                 footnote: "Ti seguono, ma nell'export non risulta un tuo like o commento verso di loro.") {
                HStack {
                    Text(result.silentTowards.count.grouped)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("account")
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink {
                        AccountListScreen(title: "Mai interagito",
                                          explanation: "Ti seguono e non risulta una tua interazione verso di loro nell'export.",
                                          accounts: result.silentTowards)
                    } label: {
                        Text("Apri").font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }

    // MARK: - Timing

    @ViewBuilder
    private func timingCard(_ result: AnalysisResult) -> some View {
        let hours = result.postingByHour
        if hours.contains(where: { $0 > 0 }) {
            Card(title: "Quando pubblichi",
                 footnote: footnote(for: result)) {
                Chart(Array(hours.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Ora", item.offset),
                            y: .value("Contenuti", item.element))
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text("\(hour)")
                            }
                        }
                    }
                }
                .frame(height: 160)

                let weekdays = result.postingByWeekday
                Chart(Array(weekdays.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Giorno", Self.weekdayNames[item.offset]),
                            y: .value("Contenuti", item.element))
                    .foregroundStyle(Color.teal.gradient)
                }
                .frame(height: 140)
            }
        }
    }

    private func footnote(for result: AnalysisResult) -> String {
        var parts: [String] = []
        if let hour = result.bestHour {
            parts.append("Fascia più usata: \(hour):00–\(hour):59.")
        }
        if let weekday = result.bestWeekday, weekday < Self.weekdayNames.count {
            parts.append("Giorno più usato: \(Self.weekdayNames[weekday]).")
        }
        parts.append("È la tua abitudine di pubblicazione, non una misura di performance: l'export non contiene le visualizzazioni.")
        return parts.joined(separator: " ")
    }

    // MARK: - Activity over time

    @ViewBuilder
    private func activityChart(_ result: AnalysisResult) -> some View {
        if result.likesByMonth.count > 1 || result.ownPostsByMonth.count > 1 {
            Card(title: "La tua attività nel tempo") {
                Chart {
                    ForEach(result.likesByMonth) { bucket in
                        LineMark(x: .value("Mese", bucket.date),
                                 y: .value("Like messi", bucket.count),
                                 series: .value("Serie", "Like messi"))
                        .foregroundStyle(Color.pink)
                        .interpolationMethod(.monotone)
                    }
                    ForEach(result.ownPostsByMonth) { bucket in
                        LineMark(x: .value("Mese", bucket.date),
                                 y: .value("Contenuti pubblicati", bucket.count),
                                 series: .value("Serie", "Contenuti pubblicati"))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.monotone)
                    }
                }
                .chartForegroundStyleScale([
                    "Like messi": Color.pink,
                    "Contenuti pubblicati": Color.accentColor
                ])
                .chartLegend(position: .bottom)
                .frame(height: 190)
            }
        }
    }
}
