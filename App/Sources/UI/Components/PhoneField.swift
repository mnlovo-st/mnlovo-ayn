import SwiftUI

/// A country with its dialling code and how local numbers are written.
struct Country: Identifiable, Hashable {
    let id: String          // ISO code
    let ar: String
    let en: String
    let dial: String        // digits only, e.g. "971"
    let pattern: String     // X = digit, spaces kept, e.g. "XX XXX XXXX"
    let minLen: Int
    let keepZero: Bool      // countries where the leading 0 is part of the number (Italy)

    var maxLen: Int { pattern.filter { $0 == "X" }.count }
    var name: String { tr(ar, en) }
    var flag: String {
        id.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
    var example: String {
        var n = 0
        return String(pattern.map { ch -> Character in
            guard ch == "X" else { return ch }
            defer { n += 1 }
            return Character(String((n + 1) % 10))
        })
    }

    init(_ id: String, _ ar: String, _ en: String, _ dial: String, _ pattern: String, min: Int? = nil, keepZero: Bool = false) {
        self.id = id; self.ar = ar; self.en = en; self.dial = dial; self.pattern = pattern
        self.minLen = min ?? pattern.filter { $0 == "X" }.count
        self.keepZero = keepZero
    }

    /// Formats the national digits with the country's grouping.
    func format(_ digits: String) -> String {
        var out = ""
        var it = digits.makeIterator()
        var pending = ""
        for ch in pattern {
            if ch == "X" {
                guard let d = it.next() else { break }
                out += pending + String(d)
                pending = ""
            } else {
                pending.append(ch)
            }
        }
        // Extra digits beyond the pattern (rare) are appended.
        while let d = it.next() { out.append(d) }
        return out
    }

    static let all: [Country] = [
        Country("AE", "الإمارات", "United Arab Emirates", "971", "XX XXX XXXX"),
        Country("SA", "السعودية", "Saudi Arabia", "966", "XX XXX XXXX"),
        Country("KW", "الكويت", "Kuwait", "965", "XXXX XXXX"),
        Country("QA", "قطر", "Qatar", "974", "XXXX XXXX"),
        Country("BH", "البحرين", "Bahrain", "973", "XXXX XXXX"),
        Country("OM", "عُمان", "Oman", "968", "XXXX XXXX"),
        Country("YE", "اليمن", "Yemen", "967", "XXX XXX XXX"),
        Country("IQ", "العراق", "Iraq", "964", "XXX XXX XXXX"),
        Country("JO", "الأردن", "Jordan", "962", "X XXXX XXXX"),
        Country("SY", "سوريا", "Syria", "963", "XXX XXX XXX"),
        Country("LB", "لبنان", "Lebanon", "961", "XX XXX XXX", min: 7),
        Country("PS", "فلسطين", "Palestine", "970", "XXX XXX XXX"),
        Country("EG", "مصر", "Egypt", "20", "XX XXXX XXXX"),
        Country("SD", "السودان", "Sudan", "249", "XX XXX XXXX"),
        Country("LY", "ليبيا", "Libya", "218", "XX XXX XXXX"),
        Country("TN", "تونس", "Tunisia", "216", "XX XXX XXX"),
        Country("DZ", "الجزائر", "Algeria", "213", "XXX XX XX XX"),
        Country("MA", "المغرب", "Morocco", "212", "XXX XX XX XX"),
        Country("MR", "موريتانيا", "Mauritania", "222", "XX XX XX XX"),
        Country("SO", "الصومال", "Somalia", "252", "XX XXX XXXX", min: 8),
        Country("DJ", "جيبوتي", "Djibouti", "253", "XX XX XX XX"),
        Country("KM", "جزر القمر", "Comoros", "269", "XXX XX XX"),
        Country("TR", "تركيا", "Türkiye", "90", "XXX XXX XX XX"),
        Country("IR", "إيران", "Iran", "98", "XXX XXX XXXX"),
        Country("PK", "باكستان", "Pakistan", "92", "XXX XXXXXXX"),
        Country("IN", "الهند", "India", "91", "XXXXX XXXXX"),
        Country("BD", "بنغلاديش", "Bangladesh", "880", "XXXX XXXXXX"),
        Country("LK", "سريلانكا", "Sri Lanka", "94", "XX XXX XXXX"),
        Country("NP", "نيبال", "Nepal", "977", "XXX XXX XXXX"),
        Country("AF", "أفغانستان", "Afghanistan", "93", "XX XXX XXXX"),
        Country("PH", "الفلبين", "Philippines", "63", "XXX XXX XXXX"),
        Country("ID", "إندونيسيا", "Indonesia", "62", "XXX XXXX XXXXX", min: 9),
        Country("MY", "ماليزيا", "Malaysia", "60", "XX XXXX XXXX", min: 9),
        Country("CN", "الصين", "China", "86", "XXX XXXX XXXX"),
        Country("JP", "اليابان", "Japan", "81", "XX XXXX XXXX"),
        Country("KR", "كوريا الجنوبية", "South Korea", "82", "XX XXXX XXXX", min: 9),
        Country("ET", "إثيوبيا", "Ethiopia", "251", "XX XXX XXXX"),
        Country("KE", "كينيا", "Kenya", "254", "XXX XXXXXX"),
        Country("NG", "نيجيريا", "Nigeria", "234", "XXX XXX XXXX"),
        Country("ZA", "جنوب أفريقيا", "South Africa", "27", "XX XXX XXXX"),
        Country("GB", "بريطانيا", "United Kingdom", "44", "XXXX XXXXXX"),
        Country("US", "أمريكا / كندا", "USA / Canada", "1", "XXX XXX XXXX"),
        Country("DE", "ألمانيا", "Germany", "49", "XXX XXXXXXXX", min: 10),
        Country("FR", "فرنسا", "France", "33", "X XX XX XX XX"),
        Country("IT", "إيطاليا", "Italy", "39", "XXX XXX XXXX", min: 9, keepZero: true),
        Country("ES", "إسبانيا", "Spain", "34", "XXX XX XX XX"),
        Country("NL", "هولندا", "Netherlands", "31", "X XXXX XXXX"),
        Country("SE", "السويد", "Sweden", "46", "XX XXX XX XX"),
        Country("RU", "روسيا", "Russia", "7", "XXX XXX XX XX"),
        Country("AU", "أستراليا", "Australia", "61", "XXX XXX XXX"),
    ]

    static let uae = all[0]

    /// Finds the country of a stored "+971 50 123 4567" style number (longest dial code wins).
    static func detect(_ full: String) -> (Country, String)? {
        let t = full.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("+") else { return nil }
        let digits = TOTP.westernDigits(t).filter { $0.isASCII && $0.isNumber }
        for c in all.sorted(by: { $0.dial.count > $1.dial.count }) where digits.hasPrefix(c.dial) {
            return (c, String(digits.dropFirst(c.dial.count)))
        }
        return nil
    }
}

enum PhoneNumber {
    /// "+971 50 123 4567" → valid if the national part has the right length for its country.
    static func isValid(_ full: String) -> Bool {
        if let r = Country.detect(full) {
            return (r.0.minLen...r.0.maxLen).contains(r.1.count)
        }
        // Older accounts typed without a country code.
        return TOTP.westernDigits(full).filter { $0.isASCII && $0.isNumber }.count >= 7
    }
}

/// Country picker + number field that writes "+<code> <formatted number>" into `full`.
struct PhoneField: View {
    @Binding var full: String
    var focus: FocusState<AYNFieldID?>.Binding
    var id: AYNFieldID = .phone
    var onSubmit: () -> Void = {}

    @State private var country = Country.uae
    @State private var national = ""
    @State private var picking = false
    @State private var loaded = false

    private var focused: Bool { focus.wrappedValue == id }
    private var valid: Bool { (country.minLen...country.maxLen).contains(national.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    picking = true
                } label: {
                    HStack(spacing: 6) {
                        Text(country.flag).font(.system(size: 24))
                        Text("+\(country.dial)").font(Theme.mono(16, .bold)).foregroundStyle(Theme.text)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.sub)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
                }
                .buttonStyle(PressScale())

                TextField(country.example, text: Binding(
                    get: { country.format(national) },
                    set: { apply($0) }
                ))
                .font(Theme.mono(17, .medium))
                .foregroundStyle(Theme.text)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused(focus, equals: id)
                .onSubmit(onSubmit)

                if !national.isEmpty {
                    Image(systemName: valid ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(valid ? Theme.ok : Theme.warn)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 10)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.8) : Theme.stroke, lineWidth: focused ? 1.5 : 1))
            .shadow(color: focused ? Theme.accent.opacity(0.25) : .clear, radius: 12)

            Text(tr("\(country.name) · مثال: \(country.example)", "\(country.name) · e.g. \(country.example)"))
                .font(Theme.font(12, .medium)).foregroundStyle(Theme.faint)
                .padding(.horizontal, 6)
        }
        .animation(.spring(response: 0.3), value: valid)
        .onAppear(perform: load)
        .sheet(isPresented: $picking) {
            CountryPicker(selected: country) { c in
                country = c
                national = String(national.prefix(c.maxLen))
                write()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus.wrappedValue = id }
            }
            .presentationDetents([.large])
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = Country.detect(full) {
            country = r.0
            national = r.1
        } else if !full.isEmpty {
            apply(full)
        }
    }

    private func apply(_ typed: String) {
        var digits = TOTP.westernDigits(typed).filter { $0.isASCII && $0.isNumber }
        // Someone typed or pasted the full international number.
        if typed.trimmingCharacters(in: .whitespaces).hasPrefix("+") || digits.hasPrefix("00") {
            if digits.hasPrefix("00") { digits.removeFirst(2) }
            if let r = Country.detect("+" + digits) { country = r.0; digits = r.1 }
        }
        // Local trunk prefix "0" (e.g. 050…) isn't part of the international number.
        if !country.keepZero { while digits.hasPrefix("0") { digits.removeFirst() } }
        national = String(digits.prefix(country.maxLen))
        write()
    }

    private func write() {
        full = national.isEmpty ? "" : "+\(country.dial) \(country.format(national))"
    }
}

struct CountryPicker: View {
    var selected: Country
    var onPick: (Country) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var list: [Country] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Country.all }
        let digits = q.filter { $0.isNumber }
        return Country.all.filter {
            $0.ar.contains(q) || $0.en.lowercased().contains(q) || (!digits.isEmpty && $0.dial.hasPrefix(digits))
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 12) {
                SheetHeader(title: tr("اختر الدولة", "Choose country")) { dismiss() }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
                    TextField(tr("ابحث بالاسم أو الرمز", "Search by name or code"), text: $query)
                        .font(Theme.font(16)).foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { c in
                            Button {
                                Haptics.selection()
                                onPick(c)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(c.flag).font(.system(size: 26))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(Theme.font(16, .semibold)).foregroundStyle(Theme.text)
                                        Text(c.example).font(Theme.mono(12)).foregroundStyle(Theme.faint)
                                    }
                                    Spacer()
                                    Text("+\(c.dial)").font(Theme.mono(15, .bold)).foregroundStyle(Theme.sub)
                                        .environment(\.layoutDirection, .leftToRight)
                                    if c.id == selected.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                }
                                .padding(.horizontal, 14).frame(height: 58)
                                .background(RoundedRectangle(cornerRadius: 14).fill(c.id == selected.id ? Theme.accent.opacity(0.12) : Theme.surface))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 18).padding(.top, 18)
        }
    }
}
