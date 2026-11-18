// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Activity/ActivityView.swift
// Description: Transaction history: date, network, asset, amount, fee, address, type, hash, status and confirmations, with search, filters, CSV and PDF export and links to the network's block explorer. Intermediate states are kept as they are; a broadcast transaction is never shown as a success.
import SwiftUI
import UniformTypeIdentifiers
import SPWalletCore

struct ActivityView: View {
    let model: AppModel
    @State private var search = ""
    @State private var kind = "all"
    @State private var network = "all"
    @State private var status = "all"
    @State private var selection: ActivityItem.ID?
    @State private var exportMessage: String?
    @State private var sort = [KeyPathComparator(\ActivityItem.at, order: .reverse)]

    private var items: [ActivityItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (model.activity?.value ?? []).filter { i in
            (kind == "all" || i.kind == kind) && (network == "all" || i.network == network) &&
            (status == "all" || (status == "final" ? i.isSettled : status == "pending" ? (!i.isSettled && i.proposalState?.isFailure != true && i.state != "not_broadcast") : (i.proposalState?.isFailure == true || i.state == "not_broadcast"))) &&
            (q.isEmpty || [i.symbol, i.networkName ?? "", i.to ?? "", i.from ?? "", i.txid ?? "", i.note ?? "", i.memo ?? ""].contains { $0.lowercased().contains(q) })
        }.sorted(using: sort)
    }

    var body: some View {
        let rows = items
        VStack(spacing: 0) {
            HStack {
                Text("Activité").font(.largeTitle.weight(.semibold))
                Spacer()
                if let src = model.activity { ProvenanceTag(p: src.fromCache ? .stale : .verified, text: src.fromCache ? "Synchronisée le \(Fmt.date(src.fetchedAt))" : "À jour \(Fmt.relative(src.fetchedAt))") }
            }.padding([.horizontal, .top], 24)
            HStack {
                TextField("Rechercher (adresse, hash, actif, note)", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Picker("Type", selection: $kind) { Text("Tous types").tag("all"); ForEach(["send", "receive", "swap", "bridge", "gmx"], id: \.self) { Text(TransactionRow.kindTitle($0)).tag($0) } }.frame(width: 170)
                Picker("Réseau", selection: $network) { Text("Tous réseaux").tag("all"); ForEach(Array(Set((model.activity?.value ?? []).map(\.network))).sorted(), id: \.self) { Text(model.network($0)?.name ?? $0).tag($0) } }.frame(width: 200)
                Picker("État", selection: $status) { Text("Tous états").tag("all"); Text("Finalisées").tag("final"); Text("En cours").tag("pending"); Text("Échecs").tag("failed") }.frame(width: 160)
                Spacer()
                Menu("Exporter") {
                    Button("CSV — sélection affichée (\(rows.count))…") { exportCSV(rows) }
                    Button("CSV complet du serveur…") { Task { await exportServerCSV() } }.disabled(!model.canOperate)
                    Button("PDF — sélection affichée (\(rows.count))…") { exportPDF(rows) }
                }.frame(width: 110)
            }.labelsHidden().padding(.horizontal, 24).padding(.vertical, 10)
            if let m = exportMessage { Text(m).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading) }
            Table(rows, selection: $selection, sortOrder: $sort) {
                TableColumn("Date", value: \.at) { Text(Fmt.date($0.at)).monospacedDigit() }.width(min: 130, ideal: 150)
                TableColumn("Type") { Text(TransactionRow.kindTitle($0.kind)) }.width(80)
                TableColumn("Réseau") { Text($0.networkName ?? $0.network) }.width(min: 90, ideal: 110)
                TableColumn("Montant") { i in Text("\(i.isIncoming ? "+" : "−")\(Fmt.amount(i.amountDisplay, maxFraction: 8)) \(i.symbol)").monospacedDigit() }.width(min: 130, ideal: 170)
                TableColumn("Frais") { i in Text(i.feeDisplay.map { "\(Fmt.amount($0, maxFraction: 8)) \(i.feeSymbol ?? "")" } ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(min: 90, ideal: 120)
                TableColumn("Contrepartie") { i in Text(Fmt.short(i.isIncoming ? i.from : i.to)).font(Theme.monoSmall) }.width(min: 120, ideal: 150)
                TableColumn("État") { StatusPill(raw: $0.state) }.width(min: 130, ideal: 180)
                TableColumn("Conf.") { Text($0.confirmations.map(String.init) ?? "—").monospacedDigit() }.width(46)
            }
            .overlay { if rows.isEmpty { EmptyState(symbol: "list.bullet.rectangle", title: model.activity == nil ? "Historique non synchronisé" : "Aucune transaction ne correspond") } }
            if let id = selection, let item = rows.first(where: { $0.id == id }) { Divider(); ActivityDetail(item: item).padding(16).frame(maxHeight: 250) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: export

    private func save(_ type: UTType, name: String, data: @escaping () -> Data?) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let d = data() else { exportMessage = "Export impossible."; return }
        do { try d.write(to: url, options: .atomic); exportMessage = "Exporté : \(url.lastPathComponent)" } catch { exportMessage = "Écriture impossible : \(error.localizedDescription)" }
    }
    private func exportCSV(_ rows: [ActivityItem]) { save(.commaSeparatedText, name: "sp-wallet-activite.csv") { ActivityExport.csv(rows).data(using: .utf8) } }
    private func exportPDF(_ rows: [ActivityItem]) { save(.pdf, name: "sp-wallet-activite.pdf") { ActivityExport.pdf(rows, title: "SP Wallet — activité", subtitle: "\(rows.count) opérations · exporté le \(Fmt.date(Date()))\(model.activity?.fromCache == true ? " · données locales du \(Fmt.date(model.activity?.fetchedAt))" : "")") } }
    private func exportServerCSV() async {
        do { let d = try await model.wallet.activityCSV(); save(.commaSeparatedText, name: "sp-wallet-activity.csv") { d } } catch { exportMessage = model.describe(error) }
    }
}

struct ActivityDetail: View {
    let item: ActivityItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("\(TransactionRow.kindTitle(item.kind)) · \(Fmt.dateSeconds(item.at))").font(.headline); Spacer(); StatusPill(raw: item.state) }
                Field(label: "Réseau", value: item.networkName ?? item.network)
                Field(label: "Actif", value: item.asset.map { $0 == "native" ? "\(item.symbol) (natif)" : "\(item.symbol) — \($0)" } ?? item.symbol)
                Field(label: "Montant", value: "\(Fmt.amount(item.amountDisplay)) \(item.symbol)  (\(item.amount) unités de base)")
                if let f = item.from { Field(label: "De", value: f, mono: true) }
                if let t = item.to { Field(label: "Vers", value: t, mono: true) }
                if let f = item.feeDisplay { Field(label: "Frais", value: "\(f) \(item.feeSymbol ?? "") (estimation au moment de la préparation)") }
                if let m = item.memo { Field(label: "Mémo", value: m) }
                if let n = item.note, !n.isEmpty { Field(label: "Note", value: n) }
                if let tx = item.txid { Field(label: "Hash", value: tx, mono: true) }
                if let c = item.confirmations { Field(label: "Confirmations", value: String(c)) }
                if let e = item.error { Banner(.warning, e) }
                if !item.isSettled, item.txid != nil, item.proposalState?.isFailure != true { Text("Un hash de transaction n’est pas une confirmation : seul l’état « Finalisée » atteste du succès.").font(.caption).foregroundStyle(.secondary) }
                if let ex = item.explorer, let u = URL(string: ex), u.scheme == "https" { Link("Ouvrir dans l’explorateur (\(u.host ?? ""))", destination: u) }
            }
        }
    }
}

enum ActivityExport {
    /// Spreadsheet-safe CSV: quotes doubled, and a leading = + - @ neutralized (formula injection).
    static func cell(_ v: String) -> String {
        var s = v.replacingOccurrences(of: "\"", with: "\"\"")
        if let f = s.first, "=+-@\t\r".contains(f) { s = "'" + s }
        return "\"\(s)\""
    }
    static func csv(_ rows: [ActivityItem]) -> String {
        var lines = ["date_utc,type,reseau,actif,contrat,montant,montant_unites_de_base,frais,de,vers,memo,etat,confirmations,hash,explorateur"]
        for i in rows {
            lines.append([ISO8601.string(i.at), i.kind, i.network, i.symbol, i.asset ?? "", i.amountDisplay ?? "", i.amount, i.feeDisplay.map { "\($0) \(i.feeSymbol ?? "")" } ?? "", i.from ?? "", i.to ?? "", i.memo ?? "", i.state, i.confirmations.map(String.init) ?? "", i.txid ?? "", i.explorer ?? ""].map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// A paginated A4-landscape PDF drawn with Core Text (no web engine involved).
    static func pdf(_ rows: [ActivityItem], title: String, subtitle: String) -> Data? {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595), margin: CGFloat = 36
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        let cols: [(String, CGFloat)] = [("Date", 105), ("Type", 60), ("Réseau", 80), ("Montant", 130), ("Contrepartie", 150), ("État", 110), ("Hash", 135)]
        let font = NSFont.systemFont(ofSize: 8), bold = NSFont.boldSystemFont(ofSize: 8), mono = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        func draw(_ s: String, _ f: NSFont, x: CGFloat, y: CGFloat, w: CGFloat, color: NSColor = .black) {
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingMiddle
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: p]))
            let fit = CTLineCreateTruncatedLine(line, Double(w - 4), .middle, nil) ?? line
            ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(fit, ctx)
        }
        var index = 0, pageNo = 0
        let perPage = Int((page.height - 2 * margin - 60) / 13)
        repeat {
            pageNo += 1
            var box = page; ctx.beginPage(mediaBox: &box)
            draw(title, NSFont.boldSystemFont(ofSize: 14), x: margin, y: page.height - margin - 8, w: 500)
            draw(subtitle, font, x: margin, y: page.height - margin - 24, w: 700, color: .darkGray)
            var x = margin; let top = page.height - margin - 46
            for (name, w) in cols { draw(name, bold, x: x, y: top, w: w); x += w }
            ctx.setStrokeColor(NSColor.gray.cgColor); ctx.setLineWidth(0.5); ctx.move(to: CGPoint(x: margin, y: top - 4)); ctx.addLine(to: CGPoint(x: page.width - margin, y: top - 4)); ctx.strokePath()
            var y = top - 16
            for i in rows[index..<min(index + perPage, rows.count)] {
                x = margin
                let cells: [(String, NSFont)] = [(Fmt.date(i.at), font), (TransactionRow.kindTitle(i.kind), font), (i.networkName ?? i.network, font),
                    ("\(i.isIncoming ? "+" : "−")\(i.amountDisplay ?? i.amount) \(i.symbol)", font), ((i.isIncoming ? i.from : i.to) ?? "—", mono), (ErrorText.activityState(i.state), font), (i.txid ?? "—", mono)]
                for (k, c) in cells.enumerated() { draw(c.0, c.1, x: x, y: y, w: cols[k].1); x += cols[k].1 }
                y -= 13
            }
            index += perPage
            draw("Page \(pageNo) · Seul l’état « Finalisée » atteste d’un succès confirmé par la chaîne.", font, x: margin, y: margin - 14, w: 600, color: .gray)
            ctx.endPage()
        } while index < rows.count
        ctx.closePDF()
        return data as Data
    }
}
