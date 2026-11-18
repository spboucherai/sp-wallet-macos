// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/ResearchView.swift
// Description: Entry of research and analysis: the market explorer, the status of the server's market-data worker, the automated research jobs and the strategy laboratory's results. Everything here is read-only analysis; observed data, estimates, simulations and AI analysis carry distinct labels, no figure is advice, and nothing on this screen places an order.
import SwiftUI
import SPWalletCore

struct ResearchView: View {
    let model: AppModel
    enum Tab: String, CaseIterable, Identifiable {
        case markets, quality, jobs, lab
        var id: String { rawValue }
        var label: String { switch self { case .markets: "Marchés"; case .quality: "Qualité des données"; case .jobs: "Recherches automatisées"; case .lab: "Laboratoire" } }
    }
    @State private var tab: Tab = .markets

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Recherche et analyse").font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("Section", selection: $tab) { ForEach(Tab.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 620)
            }.padding([.horizontal, .top], 24).padding(.bottom, 8)
            HStack(spacing: 8) {
                Text("Nature des chiffres :").font(.caption).foregroundStyle(.secondary)
                ProvenanceTag(p: .verified, text: "Donnée observée")
                ProvenanceTag(p: .estimate, text: "Estimation ou valeur dérivée")
                ProvenanceTag(p: .simulated, text: "Simulation (backtest)")
                ProvenanceTag(p: .ai, text: "Analyse générée par IA")
                Spacer()
                Text("Lecture seule — aucune information ici n’est un conseil en placement.").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 10)
            if model.isOffline { Banner(.warning, "Portefeuille injoignable : les données de marché ne peuvent pas être relues. Ce qui reste affiché porte la date de sa dernière lecture.").padding(.horizontal, 24).padding(.bottom, 8) }
            Divider()
            switch tab {
            case .markets: RsMarketsTab(model: model)
            case .quality: RsDataQualityTab(model: model)
            case .jobs: RsJobsTab(model: model)
            case .lab: RsLabTab(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
