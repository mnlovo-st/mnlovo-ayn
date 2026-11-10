import SwiftUI
import PhotosUI
import QuickLook
import VisionKit
import UniformTypeIdentifiers

struct VaultView: View {
    @EnvironmentObject var state: AppState
    @State private var segment = 0          // 0 files, 1 notes
    @State private var kindFilter = 0
    @State private var query = ""
    @State private var showAdd = false
    @State private var newSensitivity: Sensitivity = .sensitive
    @State private var deleteOriginals = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showScanner = false
    @State private var editingNote: SecureNote?
    @State private var previewURL: URL?
    @State private var secretAction: SecretAction?
    @State private var renaming: VaultFile?
    @State private var renameText = ""
    @State private var shareURL: URL?
    @State private var revealed: Set<UUID> = []
    @AppStorage("intro.vault.seen") private var introSeen = false
    @State private var showIntro = false

    private var filteredFiles: [VaultFile] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return state.files.filter { f in
            switch kindFilter {
            case 1: if f.kind != .image { return false }
            case 2: if f.kind != .video { return false }
            case 3: if f.kind == .image || f.kind == .video { return false }
            default: break
            }
            if q.isEmpty { return true }
            if f.sensitivity == .secret { return false }
            return f.name.lowercased().contains(q) || (f.ocrText ?? "").lowercased().contains(q)
        }
    }

    private var filteredNotes: [SecureNote] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return state.notes.filter { n in
            if q.isEmpty { return true }
            if n.sensitivity == .secret { return false }
            return n.title.lowercased().contains(q) || n.body.lowercased().contains(q)
        }
    }

    private var totalSize: Int64 { state.files.reduce(0) { $0 + $1.size } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TabHeader(title: MainTab.vault.title,
                          subtitle: tr("\(state.files.count) ملف · \(state.notes.count) ملاحظة · \(Fmt.bytes(totalSize))",
                                       "\(state.files.count) files · \(state.notes.count) notes · \(Fmt.bytes(totalSize))")) {
                    CircleIconButton(icon: "plus", size: 42, tint: Theme.bg) { showAdd = true }
                        .background(Circle().fill(Theme.gradient))
                }

                Picker("", selection: $segment) {
                    Text(tr("الملفات", "Files")).tag(0)
                    Text(tr("الملاحظات", "Notes")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .onChange(of: segment) { _, _ in FX.toggle() }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
                    TextField(segment == 0 ? tr("ابحث بالاسم أو النص داخل المستند…", "Search names or text inside scans…")
                                           : tr("ابحث في الملاحظات…", "Search notes…"), text: $query)
                        .textInputAutocapitalization(.never)
                }
                .font(Theme.font(15))
                .padding(.horizontal, 14).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .padding(.horizontal, 20)

                if segment == 0 { filesSection } else { notesSection }
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showAdd) { addSheet }
        .photosPicker(isPresented: $showPhotos, selection: $pickerItems, maxSelectionCount: 30,
                      matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await importFiles(urls) } }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { images in
                showScanner = false
                Task { await importScan(images) }
            } onCancel: { showScanner = false }
            .ignoresSafeArea()
        }
        .sheet(item: $editingNote) { n in NoteEditor(note: n).environmentObject(state) }
        .sheet(item: $secretAction) { act in SecretUnlockSheet(onUnlock: act.run).environmentObject(state) }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            if new == nil, let old { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .alert(tr("إعادة تسمية", "Rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("الاسم", "Name"), text: $renameText)
            Button(tr("حفظ", "Save")) {
                if var f = renaming, !renameText.isEmpty { f.name = renameText; state.update(f) }
                renaming = nil
            }
            Button(tr("إلغاء", "Cancel"), role: .cancel) { renaming = nil }
        }
        .onAppear {
            // Shown once, and never over the decoy vault — the intro would give the trick away.
            if !introSeen && !state.isDecoy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showIntro = true }
            }
        }
        .fullScreenCover(isPresented: $showIntro) {
            VaultIntro { introSeen = true; showIntro = false }
        }
    }

    // MARK: Files

    private var filesSection: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    kindChip(0, tr("الكل", "All"), "square.grid.2x2")
                    kindChip(1, tr("صور", "Photos"), "photo")
                    kindChip(2, tr("فيديو", "Videos"), "play.rectangle")
                    kindChip(3, tr("مستندات", "Documents"), "doc")
                }
                .padding(.horizontal, 20)
            }
            if filteredFiles.isEmpty {
                EmptyStateView(title: tr("الخزنة فاضية", "Vault is empty"),
                               subtitle: tr("اضغط + وضيف صور، فيديو، ملفات أو امسح مستند.", "Tap + to add photos, videos, files or scan a document."))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(filteredFiles) { f in
                        FileTile(file: f, revealed: revealed.contains(f.id))
                            .onTapGesture { openFile(f) }
                            .contextMenu { fileMenu(f) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func fileMenu(_ f: VaultFile) -> some View {
        Button { renameText = f.name; renaming = f } label: { Label(tr("إعادة تسمية", "Rename"), systemImage: "pencil") }
        Menu {
            ForEach(Sensitivity.allCases) { s in
                Button { var c = f; c.sensitivity = s; state.update(c) } label: { Label(s.title, systemImage: s.icon) }
            }
        } label: { Label(tr("الحساسية", "Sensitivity"), systemImage: "shield.lefthalf.filled") }
        Button {
            guarded(f) { Task { if let u = try? await state.decryptedURL(for: f) { shareURL = u } } }
        } label: { Label(tr("مشاركة / تصدير", "Share / export"), systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { state.delete(f) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
    }

    private func kindChip(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button {
            FX.toggle()
            withAnimation(.spring(response: 0.3)) { kindFilter = i }
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.font(13, .bold))
                .foregroundStyle(kindFilter == i ? Theme.bg : Theme.sub)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(kindFilter == i ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
        }
        .buttonStyle(PressScale())
    }

    private func guarded(_ f: VaultFile, _ action: @escaping () -> Void) {
        if f.sensitivity == .secret {
            secretAction = SecretAction { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { action() } }
        } else {
            action()
        }
    }

    private func openFile(_ f: VaultFile) {
        FX.tap()
        if f.sensitivity == .sensitive && !revealed.contains(f.id) {
            withAnimation(.spring) { _ = revealed.insert(f.id) }
            return
        }
        guarded(f) {
            Task {
                do { previewURL = try await state.decryptedURL(for: f) }
                catch { state.show(tr("تعذّر فتح الملف", "Couldn't open file"), icon: "xmark.octagon.fill", style: .error) }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(spacing: 10) {
            if filteredNotes.isEmpty {
                EmptyStateView(title: tr("ما في ملاحظات", "No notes"), subtitle: tr("احفظ أرقام، عناوين، أي شي حساس.", "Store numbers, addresses, anything sensitive."))
            }
            ForEach(filteredNotes) { n in
                HStack(spacing: 12) {
                    Image(systemName: "note.text").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(n.sensitivity.color)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(n.sensitivity.color.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.sensitivity == .secret ? tr("ملاحظة سرية", "Secret note") : n.title)
                            .font(Theme.font(16, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(n.sensitivity == .normal ? n.body : (n.sensitivity == .secret ? "••••••" : tr("مخفية · اضغط للفتح", "Hidden · tap to open")))
                            .font(Theme.font(13)).foregroundStyle(Theme.sub).lineLimit(1)
                    }
                    Spacer()
                    SensitivityBadge(level: n.sensitivity, compact: true)
                }
                .glass(12, radius: 20)
                .onTapGesture {
                    FX.tap()
                    if n.sensitivity == .secret {
                        secretAction = SecretAction { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editingNote = n } }
                    } else { editingNote = n }
                }
                .contextMenu {
                    Button(role: .destructive) { state.delete(n) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Add sheet

    private var addSheet: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: tr("إضافة للخزنة", "Add to vault")) { showAdd = false }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: tr("مستوى الحساسية", "Sensitivity"), icon: "shield.lefthalf.filled")
                        SensitivityPicker(level: $newSensitivity)
                    }
                    Toggle(isOn: $deleteOriginals) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("احذف الأصل من الاستوديو", "Delete originals from Photos")).font(Theme.font(15, .semibold))
                            Text(tr("بعد التشفير. الآيفون يطلب تأكيدك.", "After encrypting. iOS will ask you to confirm."))
                                .font(Theme.font(12)).foregroundStyle(Theme.sub)
                        }
                    }
                    .tint(Theme.accent).glass(14)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        addTile(tr("صور وفيديو", "Photos & videos"), "photo.on.rectangle.angled") { showAdd = false; delay { showPhotos = true } }
                        addTile(tr("ملفات", "Files"), "folder.fill") { showAdd = false; delay { showFiles = true } }
                        addTile(tr("مسح مستند", "Scan document"), "doc.viewfinder") {
                            showAdd = false
                            if VNDocumentCameraViewController.isSupported { delay { showScanner = true } }
                        }
                        addTile(tr("ملاحظة", "Note"), "square.and.pencil") {
                            showAdd = false
                            delay { editingNote = SecureNote(title: "", body: "", sensitivity: newSensitivity) }
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
    }

    private func delay(_ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: f)
    }

    private func addTile(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { FX.tap(); action() } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.gradient)
                Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).frame(height: 110)
            .glass(10)
        }
        .buttonStyle(PressScale())
    }

    // MARK: Import

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var done = 0
        var ids: [String] = []
        for item in items {
            done += 1
            state.busy = tr("نشفّر \(done) من \(items.count)…", "Encrypting \(done) of \(items.count)…")
            let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                if isMovie, let movie = try await item.loadTransferable(type: MovieFile.self) {
                    let name = "VID_\(stamp())." + movie.url.pathExtension
                    try await state.importFile(at: movie.url, name: name, sensitivity: newSensitivity, kind: .video)
                    try? FileManager.default.removeItem(at: movie.url)
                } else if let data = try await item.loadTransferable(type: Data.self) {
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
                    try data.write(to: tmp, options: .completeFileProtection)
                    try await state.importFile(at: tmp, name: "IMG_\(stamp()).\(ext)", sensitivity: newSensitivity, kind: .image)
                    try? FileManager.default.removeItem(at: tmp)
                } else { continue }
                if let id = item.itemIdentifier { ids.append(id) }
            } catch {
                state.show(tr("تعذّر استيراد عنصر", "Couldn't import an item"), icon: "xmark.octagon.fill", style: .error)
            }
        }
        state.busy = nil
        pickerItems = []
        state.show(tr("تم تشفير \(ids.count) عنصر 🔒", "\(ids.count) items encrypted 🔒"), icon: "lock.fill")
        if deleteOriginals && !ids.isEmpty { _ = await MediaTools.deleteFromPhotos(ids) }
    }

    private func importFiles(_ urls: [URL]) async {
        var n = 0
        for url in urls {
            n += 1
            state.busy = tr("نشفّر \(n) من \(urls.count)…", "Encrypting \(n) of \(urls.count)…")
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try await state.importFile(at: url, name: url.lastPathComponent, sensitivity: newSensitivity)
            } catch {
                state.show(tr("تعذّر استيراد \(url.lastPathComponent)", "Couldn't import \(url.lastPathComponent)"), icon: "xmark.octagon.fill", style: .error)
            }
        }
        state.busy = nil
        state.show(tr("تم تشفير \(urls.count) ملف 🔒", "\(urls.count) files encrypted 🔒"), icon: "lock.fill")
    }

    private func importScan(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        state.busy = tr("نقرأ النص ونشفّر المستند…", "Reading text & encrypting…")
        let text = await MediaTools.recognizeText(images)
        let pdf = MediaTools.pdf(from: images)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        do {
            try pdf.write(to: tmp, options: .completeFileProtection)
            try await state.importFile(at: tmp, name: tr("مستند \(stamp()).pdf", "Scan \(stamp()).pdf"),
                                       sensitivity: newSensitivity, kind: .scan, ocrText: text)
            state.show(tr("تم حفظ المستند 📄", "Document saved 📄"), icon: "doc.viewfinder")
        } catch {
            state.show(tr("تعذّر حفظ المستند", "Couldn't save the scan"), icon: "xmark.octagon.fill", style: .error)
        }
        try? FileManager.default.removeItem(at: tmp)
        state.busy = nil
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

struct FileTile: View {
    var file: VaultFile
    var revealed: Bool

    private var blurred: Bool {
        file.sensitivity == .secret || (file.sensitivity == .sensitive && !revealed)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let d = file.thumbnail, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.surfaceHi
                        Image(systemName: file.kind.icon).font(.system(size: 30)).foregroundStyle(Theme.sub)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 112)
            .clipped()
            .blur(radius: blurred ? 18 : 0)
            .overlay {
                if blurred {
                    Image(systemName: file.sensitivity == .secret ? "lock.fill" : "eye.slash.fill")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: 4) {
                if file.kind == .video { Image(systemName: "play.fill") }
                Circle().fill(file.sensitivity.color).frame(width: 7, height: 7)
                Text(file.sensitivity == .secret ? "•••" : file.name).lineLimit(1)
            }
            .font(Theme.font(10, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.5)))
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
        .animation(.easeInOut(duration: 0.3), value: blurred)
    }
}

struct NoteEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var note: SecureNote
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: tr("ملاحظة", "Note")) { save(); dismiss() }
                    AYNField(title: tr("العنوان", "Title"), icon: "textformat", text: $note.title, focus: $focus, id: .title)
                    TextEditor(text: $note.body)
                        .scrollContentBackground(.hidden)
                        .font(Theme.font(16))
                        .frame(minHeight: 260)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                    SensitivityPicker(level: $note.sensitivity)
                    PrimaryButton(title: tr("حفظ", "Save"), icon: "checkmark") { save(); dismiss() }
                }
                .padding(20)
            }
        }
    }

    private func save() {
        guard !note.title.isEmpty || !note.body.isEmpty else { return }
        if note.title.isEmpty { note.title = String(note.body.prefix(30)) }
        state.upsert(note)
        Haptics.success()
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ p: DocumentScanner) { parent = p }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            parent.onFinish(images)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onCancel() }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
