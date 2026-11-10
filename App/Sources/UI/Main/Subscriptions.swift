import SwiftUI

/// Price, cycle and how early to warn — shown inside the reminder editor for subscriptions.
struct SubscriptionEditorSection: View {
    @Binding var sub: Subscription
    @State private var priceText = ""
    @FocusState private var focus: AYNFieldID?

    private static let currencies = ["AED", "SAR", "KWD", "QAR", "BHD", "OMR", "EGP", "JOD", "USD", "EUR", "GBP", "TRY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: tr("السعر والتجديد", "Price & renewal"), icon: "creditcard.fill")

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill").foregroundStyle(Theme.accent)
                    TextField("0", text: $priceText)
                        .font(Theme.mono(18, .bold))
                        .foregroundStyle(Theme.text)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .title)
                        .onChange(of: priceText) { _, v in
                            sub.price = Double(TOTP.westernDigits(v).replacingOccurrences(of: ",", with: ".")) ?? 0
                        }
                }
                .padding(.horizontal, 12).frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))

                Menu {
                    ForEach(Self.currencies, id: \.self) { c in
                        Button(c) { sub.currency = c; Haptics.selection() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sub.currency).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.sub)
                    }
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceHi))
                }
            }
            .environment(\.layoutDirection, .leftToRight)

            Picker("", selection: $sub.cycle) {
                ForEach(Subscription.Cycle.allCases) { c in Text(c.title).tag(c) }
            }
            .pickerStyle(.segmented)

            HStack {
                Label(tr("نبّهني قبل", "Warn me"), systemImage: "bell.badge")
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                Picker("", selection: $sub.warnDaysBefore) {
                    ForEach([1, 2, 3, 7, 14], id: \.self) { d in Text(tr("\(d) يوم", "\(d)d")).tag(d) }
                }
                .pickerStyle(.menu).tint(Theme.accent)
            }

            Toggle(isOn: $sub.planToCancel) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("ناوي ألغيه", "I plan to cancel")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                    Text(tr("بذكّرك بحزم قبل ما ينخصم", "I'll nudge you firmly before it charges")).font(Theme.font(11)).foregroundStyle(Theme.sub)
                }
            }
            .tint(Theme.warn)

            if sub.price > 0 {
                Divider().overlay(Theme.stroke)
                HStack {
                    Text(tr("يكلّفك بالشهر", "Costs you monthly")).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                    Spacer()
                    MoneyText(value: sub.monthlyCost, code: sub.currency, size: 16)
                        .foregroundStyle(Theme.accent)
                }
                HStack {
                    Text(tr("وبالسنة", "And yearly")).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                    Spacer()
                    MoneyText(value: sub.monthlyCost * 12, code: sub.currency, size: 15)
                        .foregroundStyle(Theme.sub)
                }
            }
        }
        .glass(14)
        .onAppear { if sub.price > 0 && priceText.isEmpty { priceText = String(format: sub.price == sub.price.rounded() ? "%.0f" : "%.2f", sub.price) } }
    }
}

extension Subscription {
    /// Text-only version, for notifications and widgets. On screen, use `MoneyText`.
    static func money(_ v: Double, _ currency: String) -> String { Money.text(v, currency) }
}

/// Summary strip at the top of the Reminders tab: what your subscriptions cost and what renews next.
struct SubscriptionsSummary: View {
    var subs: [Reminder]
    var onOpen: (Reminder) -> Void

    private var byCurrency: [(String, Double)] {
        var totals: [String: Double] = [:]
        for r in subs {
            guard let s = r.subscription else { continue }
            totals[s.currency, default: 0] += s.monthlyCost
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    private var next: Reminder? { subs.min { $0.due < $1.due } }

    var body: some View {
        if !subs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("اشتراكاتك", "Your subscriptions"), systemImage: "creditcard.fill")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(tr("\(subs.count)", "\(subs.count)"))
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(Theme.surfaceHi))
                }

                HStack(spacing: 10) {
                    ForEach(byCurrency.prefix(2), id: \.0) { pair in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("بالشهر", "Monthly")).font(Theme.font(11)).foregroundStyle(Theme.sub)
                            MoneyText(value: pair.1, code: pair.0, size: 18)
                                .foregroundStyle(Theme.accent)
                            HStack(spacing: 4) {
                                Text(tr("بالسنة", "Yearly")).font(Theme.font(10)).foregroundStyle(Theme.faint)
                                MoneyText(value: pair.1 * 12, code: pair.0, size: 10, weight: .semibold)
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                }

                if let n = next, let s = n.subscription {
                    Button { onOpen(n) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.planToCancel ? "scissors" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(s.planToCancel ? Theme.warn : Theme.accent2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("الياي: \(n.displayTitle)", "Next: \(n.displayTitle)"))
                                    .font(Theme.font(14, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(Fmt.remaining(until: n.due)) · \(s.priceText) · \(s.cycle.title)")
                                    .font(Theme.font(11)).foregroundStyle(Theme.sub)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.faint)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                    .buttonStyle(PressScale())
                }
            }
            .glass(14, tint: Theme.accent2)
        }
    }
}
