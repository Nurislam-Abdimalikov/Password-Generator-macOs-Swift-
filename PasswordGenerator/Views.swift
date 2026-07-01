import SwiftUI

// Заголовок экрана
struct ScreenHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold()).foregroundColor(.white)
            Text(subtitle).font(.subheadline).foregroundColor(.white.opacity(0.8))
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }
}

// Вкладки
enum AppTab: String, CaseIterable, Identifiable {
    case generator = "Генератор"
    case profile = "Профиль"
    case settings = "Настройки"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .generator: return "wand.and.stars"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// Корневой экран
struct RootView: View {
    @EnvironmentObject var vm: PasswordViewModel
    @State private var tab: AppTab = .generator

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.08))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            ZStack {
                #if os(macOS)
                VideoBackground(resource: "background", ext: "mp4")
                #else
                Brand.background
                #endif
                Rectangle().fill(Color.black.opacity(0.45))
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear {
            HotKeyManager.shared.onTrigger = {
                vm.generate()
                vm.copyToClipboard()
            }
            HotKeyManager.shared.register()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(Brand.accentGradient)
                VStack(alignment: .leading, spacing: 0) {
                    Text("KeyForge").font(.headline).bold()
                    Text("генератор паролей").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(AppTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = item }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).frame(width: 22)
                        Text(item.rawValue)
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tab == item ? Brand.accent.opacity(0.22) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(tab == item ? Brand.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .foregroundColor(tab == item ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: vm.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(vm.isUnlocked ? .green : .secondary)
                Text(vm.isUnlocked ? "Разблокировано" : "Заблокировано")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(width: 210)
        .background(Color.white.opacity(0.03))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .generator: GeneratorView()
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}

// Экран генератора
struct GeneratorView: View {
    @EnvironmentObject var vm: PasswordViewModel
    @State private var copied = false
    @State private var saved = false
    @State private var spin = 0.0
    @State private var toast: ToastData?
    @State private var toastWork: DispatchWorkItem?

    // Сохранение с контекстом
    @State private var showSaveSheet = false
    @State private var saveSite = ""
    @State private var saveLogin = ""
    @State private var saveNote = ""

    // Проверка на утечки
    @State private var breach: BreachResult?
    @State private var checking = false

    private let lengthPresets = [8, 12, 16, 24, 32, 48, 64]

    // Уникальные почты/логины из истории (для быстрого выбора при сохранении)
    private var recentLogins: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for e in vm.history where !e.login.isEmpty {
            if seen.insert(e.login).inserted { result.append(e.login) }
            if result.count >= 5 { break }
        }
        return result
    }

    private func showToast(_ data: ToastData) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { toast = data }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func triggerGenerate() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { spin += 360 }
        vm.generate()
        showToast(ToastData(text: "Новый пароль готов", icon: "wand.and.stars", tint: Brand.accent))
    }

    private func triggerCopy() {
        vm.copyToClipboard()
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
        let clip = vm.autoClearClipboard ? "Скопировано · очистится через \(Int(vm.clipboardClearSeconds)) с" : "Скопировано в буфер"
        showToast(ToastData(text: clip, icon: "doc.on.doc.fill", tint: Color(red: 0.20, green: 0.66, blue: 0.46)))
    }

    private func openSaveSheet() {
        saveSite = ""; saveLogin = ""; saveNote = ""
        #if os(macOS)
        // Пытаемся подставить сайт из активной вкладки браузера.
        if let site = BrowserURL.currentSiteDomain() { saveSite = site }
        #endif
        showSaveSheet = true
    }

    private func commitSave() {
        vm.saveCurrent(site: saveSite, login: saveLogin, note: saveNote)
        showSaveSheet = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { saved = false } }
        showToast(ToastData(text: "Пароль сохранён", icon: "checkmark.circle.fill", tint: Color(red: 0.20, green: 0.66, blue: 0.46)))
    }

    private func runBreachCheck() {
        guard !vm.password.isEmpty else { return }
        checking = true; breach = nil
        let pwd = vm.password
        Task {
            let result = await BreachChecker.check(pwd)
            await MainActor.run { breach = result; checking = false }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Генератор", subtitle: "Создавай надёжные пароли в один клик")

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ваш пароль").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            coloredPassword(vm.password.isEmpty ? "—" : vm.password)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .id(vm.password)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.password)
                            Spacer()
                            Button { triggerGenerate() } label: {
                                Image(systemName: "arrow.clockwise").font(.title3)
                                    .rotationEffect(.degrees(spin))
                            }
                            .buttonStyle(.borderless)
                            .help("Сгенерировать новый")
                            Button { triggerCopy() } label: {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(copied ? .green : Brand.accent)
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .help("Скопировать в буфер обмена")
                        }
                        strengthView
                        breachView
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Настройки генерации", systemImage: "slider.horizontal.3").font(.headline)
                        optionsView
                    }
                }

                generateButton
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            if let toast { ToastView(data: toast).padding(.top, 16).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill").font(.title2).foregroundStyle(Brand.accentGradient)
                Text("Сохранить пароль").font(.headline)
            }
            Text("Куда и с какой почтой ты зарегистрировался — это поможет потом найти пароль.")
                .font(.caption).foregroundColor(.secondary)

            GlassCard {
                coloredPassword(vm.password.isEmpty ? "—" : vm.password)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }

            VStack(alignment: .leading, spacing: 10) {
                labeledField("Сайт / сервис", "например, jutsu.net", text: $saveSite)
                labeledField("Логин / почта", "например, arzbt111@gmail.com", text: $saveLogin)
                if !recentLogins.isEmpty {
                    HStack(spacing: 6) {
                        Text("Недавние:").font(.caption2).foregroundColor(.secondary)
                        ForEach(recentLogins, id: \.self) { login in
                            Button(login) { saveLogin = login }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Brand.accent.opacity(0.18), in: Capsule())
                                .overlay(Capsule().stroke(Brand.accent.opacity(0.4), lineWidth: 1))
                        }
                        Spacer()
                    }
                }
                labeledField("Заметка (необязательно)", "например, основной аккаунт", text: $saveNote)
            }

            HStack {
                Spacer()
                Button("Отмена") { showSaveSheet = false }
                Button("Сохранить") { commitSave() }
                    .buttonStyle(.borderedProminent).tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
    }

    private func labeledField(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var breachView: some View {
        HStack(spacing: 10) {
            Button { runBreachCheck() } label: {
                Label(checking ? "Проверяю…" : "Проверить на утечки", systemImage: "shield.checkerboard")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(checking || vm.password.isEmpty)

            if checking { ProgressView().scaleEffect(0.6) }

            switch breach {
            case .safe:
                Label("Не найден в утечках", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundColor(.green)
            case .pwned(let count):
                Label("В утечках: \(count.formatted()) раз — смени!", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.red)
            case .error(let msg):
                Text(msg).font(.caption).foregroundColor(.orange).lineLimit(1)
            case nil:
                EmptyView()
            }
            Spacer()
        }
    }

    private var strengthView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Надёжность:")
                Text(vm.strength.label).foregroundColor(vm.strength.color).bold()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(vm.strength.color)
                        .frame(width: geo.size.width * vm.strength.fillRatio, height: 8)
                        .animation(.easeInOut, value: vm.strength.fillRatio)
                }
            }
            .frame(height: 8)
        }
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Режим", selection: $vm.mode) {
                ForEach(GenerationMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: vm.mode) { _ in vm.generate() }

            if vm.mode == .password {
                HStack {
                    Text("Длина: \(Int(vm.length))").frame(width: 90, alignment: .leading)
                    Slider(value: $vm.length, in: 4...64, step: 1).onChange(of: vm.length) { _ in vm.generate() }
                }
                HStack(spacing: 6) {
                    ForEach(lengthPresets, id: \.self) { preset in
                        Button("\(preset)") {
                            vm.length = Double(preset); vm.generate()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 30)
                        .padding(.vertical, 5)
                        .background(Int(vm.length) == preset ? Brand.accent.opacity(0.25) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Int(vm.length) == preset ? Brand.accent.opacity(0.6) : Color.clear, lineWidth: 1))
                    }
                }
                Toggle("Строчные буквы (a–z)", isOn: $vm.useLowercase).onChange(of: vm.useLowercase) { _ in vm.generate() }
                Toggle("Заглавные буквы (A–Z)", isOn: $vm.useUppercase).onChange(of: vm.useUppercase) { _ in vm.generate() }
                Toggle("Цифры (0–9)", isOn: $vm.useNumbers).onChange(of: vm.useNumbers) { _ in vm.generate() }
                Toggle("Символы (!@#$…)", isOn: $vm.useSymbols).onChange(of: vm.useSymbols) { _ in vm.generate() }
                if vm.useSymbols {
                    HStack(spacing: 8) {
                        Text("Набор:").font(.caption).foregroundColor(.secondary)
                        TextField("!@#$%^&*…", text: $vm.customSymbols)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .onChange(of: vm.customSymbols) { _ in vm.generate() }
                        Button {
                            vm.customSymbols = "!@#$%^&*()-_=+[]{};:,.<>?"; vm.generate()
                        } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless).help("Сбросить набор символов")
                    }
                }
                Toggle("Исключить похожие символы (0/O, 1/l/I)", isOn: $vm.excludeSimilar).onChange(of: vm.excludeSimilar) { _ in vm.generate() }
            } else {
                HStack {
                    Text("Слов: \(Int(vm.wordCount))").frame(width: 90, alignment: .leading)
                    Slider(value: $vm.wordCount, in: 3...8, step: 1).onChange(of: vm.wordCount) { _ in vm.generate() }
                }
                Text("Фраза из случайных слов через дефис — легче запомнить и всё ещё надёжно.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Brand.accent)
    }

    private var generateButton: some View {
        HStack(spacing: 12) {
            Button { triggerGenerate() } label: {
                Label("Сгенерировать", systemImage: "wand.and.stars").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Brand.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundColor(.white)
            .shadow(color: Brand.accent.opacity(0.45), radius: 10, y: 4)

            Button { openSaveSheet() } label: {
                Label(saved ? "Сохранено!" : "Сохранить", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(saved ? Color.green : Brand.stroke))
            .foregroundColor(saved ? .green : .primary)
            .scaleEffect(saved ? 1.04 : 1.0)
        }
        .font(.body.weight(.semibold))
    }
}

// Экран профиля
struct ProfileView: View {
    @EnvironmentObject var vm: PasswordViewModel
    @State private var showPINSheet = false
    @State private var pinInput = ""
    @State private var pinError = false
    @State private var authError: String?
    @State private var didAutoPrompt = false

    // Редактирование записи
    @State private var editingEntry: PasswordEntry?
    @State private var editSite = ""
    @State private var editLogin = ""
    @State private var editNote = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Профиль", subtitle: "Сохранённые пароли под защитой")
                if vm.isUnlocked { unlockedView } else { lockedView }
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPINSheet) { pinSheet }
        .sheet(item: $editingEntry) { entry in editSheet(entry) }
        .onDisappear { vm.lock() }
        .onAppear {
            if !vm.isUnlocked && vm.canUseBiometrics && !didAutoPrompt {
                didAutoPrompt = true
                unlockWithBiometrics()
            }
        }
    }

    private var lockedView: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: vm.biometricIcon).font(.system(size: 46)).foregroundStyle(Brand.accentGradient)
                Text("Доступ защищён").font(.title3.bold())
                Text(vm.canUseBiometrics ? "Используй \(vm.biometricName) или PIN-код, чтобы открыть сохранённые пароли." : "Введите PIN-код, чтобы открыть сохранённые пароли.")
                    .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)

                if let authError { Text(authError).font(.caption).foregroundColor(.red).multilineTextAlignment(.center) }

                VStack(spacing: 10) {
                    if vm.canUseBiometrics {
                        Button { unlockWithBiometrics() } label: {
                            Label("Открыть через \(vm.biometricName)", systemImage: vm.biometricIcon).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(Brand.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundColor(.white)
                    }
                    Button { pinInput = ""; pinError = false; showPINSheet = true } label: {
                        Label(vm.hasPIN ? "Ввести PIN-код" : "Установить PIN-код", systemImage: "number.square").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.stroke))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var unlockedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Мои пароли", systemImage: "lock.open.fill").font(.headline)
                Spacer()
                if !vm.history.isEmpty { Button("Очистить") { vm.clearHistory() }.buttonStyle(.borderless).foregroundColor(.red) }
                Button { vm.lock() } label: { Label("Закрыть", systemImage: "lock.fill") }.buttonStyle(.borderless)
            }

            if vm.history.isEmpty {
                GlassCard { Text("Пока пусто. На вкладке «Генератор» нажми «Сохранить».").foregroundColor(.secondary) }
            } else {
                // Поиск по сайту / логину / заметке
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Поиск по сайту, почте или заметке", text: $vm.searchQuery)
                        .textFieldStyle(.plain)
                    if !vm.searchQuery.isEmpty {
                        Button { vm.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.stroke))

                let items = vm.filteredHistory
                if items.isEmpty {
                    GlassCard { Text("Ничего не найдено по запросу «\(vm.searchQuery)».").foregroundColor(.secondary) }
                } else {
                    VStack(spacing: 10) {
                        ForEach(items) { entry in entryCard(entry) }
                    }
                }
            }
        }
        .onTapGesture { vm.noteActivity() }
    }

    private func entryCard(_ entry: PasswordEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundColor(.secondary).font(.caption)
                    Text(entry.site.isEmpty ? "Без названия" : entry.site)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(entry.site.isEmpty ? .secondary : .white)
                    Spacer()
                    Text(entry.date, style: .date).font(.caption2).foregroundColor(.secondary)
                }
                if !entry.login.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").foregroundColor(.secondary).font(.caption2)
                        Text(entry.login).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                    }
                }
                HStack(spacing: 10) {
                    coloredPassword(entry.password)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { vm.copy(entry) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Скопировать пароль")
                    Button { openEdit(entry) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Изменить")
                    Button { vm.deleteEntry(entry) } label: { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.borderless).help("Удалить")
                }
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundColor(.secondary).italic()
                }
            }
        }
    }

    private func openEdit(_ entry: PasswordEntry) {
        editSite = entry.site; editLogin = entry.login; editNote = entry.note
        editingEntry = entry
    }

    private func editSheet(_ entry: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Изменить запись").font(.headline)
            GlassCard {
                coloredPassword(entry.password).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.5)
            }
            VStack(alignment: .leading, spacing: 10) {
                fieldRow("Сайт / сервис", "например, jutsu.net", $editSite)
                fieldRow("Логин / почта", "например, arzbt111@gmail.com", $editLogin)
                fieldRow("Заметка", "необязательно", $editNote)
            }
            HStack {
                Spacer()
                Button("Отмена") { editingEntry = nil }
                Button("Сохранить") {
                    vm.updateEntry(entry, site: editSite, login: editLogin, note: editNote)
                    editingEntry = nil
                }
                .buttonStyle(.borderedProminent).tint(Brand.accent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
    }

    private func fieldRow(_ title: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var pinSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(Brand.accentGradient)
            Text(vm.hasPIN ? "Введите PIN-код" : "Установите PIN-код").font(.headline)
            Text(vm.hasPIN ? "Чтобы показать сохранённые пароли" : "Этот код будет защищать ваши пароли. Например: 0000").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            SecureField("PIN-код", text: $pinInput).textFieldStyle(.roundedBorder).frame(width: 200).onSubmit { submitPIN() }
            if pinError { Text("Неверный PIN-код").foregroundColor(.red).font(.caption) }
            HStack {
                Button("Отмена") { showPINSheet = false }
                Button(vm.hasPIN ? "Открыть" : "Сохранить") { submitPIN() }.buttonStyle(.borderedProminent).tint(Brand.accent).disabled(pinInput.isEmpty)
            }
        }
        .padding(28).frame(width: 320)
    }

    private func submitPIN() {
        if vm.hasPIN { if vm.unlock(with: pinInput) { showPINSheet = false } else { pinError = true } }
        else { guard !pinInput.isEmpty else { return }; vm.setPIN(pinInput); showPINSheet = false }
    }

    private func unlockWithBiometrics() { authError = nil; vm.authenticateWithBiometrics { success, message in if !success { authError = message } } }
}

// Экран настроек
struct SettingsView: View {
    @EnvironmentObject var vm: PasswordViewModel

    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var backupPass = ""
    @State private var backupMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Настройки", subtitle: "Безопасность и о приложении")
                protectionCard
                securityCard
                backupCard
                systemCard
                themeCard
                aboutCard
            }
            .padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showExportSheet) { backupSheet(isExport: true) }
        .sheet(isPresented: $showImportSheet) { backupSheet(isExport: false) }
        .alert("Бэкап", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("OK", role: .cancel) { backupMessage = nil }
        } message: { Text(backupMessage ?? "") }
    }

    private var protectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Защита", systemImage: "shield.lefthalf.filled").font(.headline)
                infoRow(icon: vm.biometricIcon, title: vm.biometricName.capitalized, value: vm.canUseBiometrics ? "Доступно" : "Недоступно")
                infoRow(icon: "number.square", title: "PIN-код", value: vm.hasPIN ? "Установлен" : "Не задан")
                if vm.hasPIN { Button(role: .destructive) { vm.resetPIN() } label: { Label("Сбросить PIN-код", systemImage: "trash") }.padding(.top, 4) }
            }
        }
    }

    private var securityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Безопасность", systemImage: "lock.rotation").font(.headline)
                Toggle("Очищать буфер обмена после копирования", isOn: $vm.autoClearClipboard).tint(Brand.accent)
                if vm.autoClearClipboard {
                    Stepper("Через \(Int(vm.clipboardClearSeconds)) сек", value: $vm.clipboardClearSeconds, in: 5...180, step: 5)
                        .font(.callout)
                }
                Divider().overlay(Brand.stroke)
                Toggle("Автоблокировка профиля", isOn: $vm.autoLockEnabled).tint(Brand.accent)
                if vm.autoLockEnabled {
                    Stepper("Через \(vm.autoLockMinutes.formatted()) мин бездействия", value: $vm.autoLockMinutes, in: 0.5...30, step: 0.5)
                        .font(.callout)
                    Text("Профиль также блокируется при сворачивании приложения.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var backupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Резервная копия", systemImage: "externaldrive.fill.badge.icloud").font(.headline)
                Text("Зашифрованный бэкап (AES-256). Файл защищён парольной фразой — без неё данные не открыть.")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button { backupPass = ""; showExportSheet = true } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.stroke))
                    .disabled(vm.history.isEmpty)

                    Button { backupPass = ""; showImportSheet = true } label: {
                        Label("Импорт", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.stroke))
                }
                .font(.body.weight(.semibold))
            }
        }
    }

    private var systemCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Система", systemImage: "macwindow").font(.headline)
                Toggle("Запускать при входе в систему", isOn: $vm.launchAtLogin).tint(Brand.accent)
                Toggle("Только в строке меню (скрыть из Dock)", isOn: $vm.menuBarOnly).tint(Brand.accent)
            }
        }
    }

    private var themeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Тема оформления", systemImage: "paintpalette.fill").font(.headline)
                Picker("Тема", selection: $vm.theme) { ForEach(AppTheme.allCases) { t in Text(t.rawValue).tag(t) } }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { t in
                        Circle().fill(t.palette.accentGradient).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white.opacity(vm.theme == t ? 0.95 : 0.15), lineWidth: 2))
                            .scaleEffect(vm.theme == t ? 1.12 : 1.0)
                            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { vm.theme = t } }
                    }
                    Spacer()
                }
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("О приложении", systemImage: "info.circle").font(.headline)
                Text("KeyForge — генератор и хранилище паролей для macOS. Криптостойкая генерация, привязка сайта и почты, биометрия (Touch ID / Face ID), хранение в Keychain, зашифрованный бэкап и проверка на утечки. Глобальная горячая клавиша: ⌃⌥⌘G — сгенерировать и скопировать пароль из любого приложения.")
                    .font(.callout).foregroundColor(.secondary)
            }
        }
    }

    private func backupSheet(isExport: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(isExport ? "Экспорт бэкапа" : "Импорт бэкапа",
                  systemImage: isExport ? "square.and.arrow.up" : "square.and.arrow.down")
                .font(.headline)
            Text(isExport ? "Придумай парольную фразу для шифрования файла. Запомни её — восстановить без неё нельзя."
                          : "Введи парольную фразу, которой был зашифрован файл бэкапа.")
                .font(.caption).foregroundColor(.secondary)
            SecureField("Парольная фраза", text: $backupPass).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Отмена") { isExport ? (showExportSheet = false) : (showImportSheet = false) }
                Button(isExport ? "Экспортировать" : "Импортировать") {
                    isExport ? runExport() : runImport()
                }
                .buttonStyle(.borderedProminent).tint(Brand.accent)
                .disabled(backupPass.count < 4)
            }
        }
        .padding(24).frame(width: 380)
    }

    private func runExport() {
        showExportSheet = false
        #if os(macOS)
        do { try BackupManager.presentExport(vm.history, passphrase: backupPass) }
        catch { backupMessage = error.localizedDescription }
        #endif
    }

    private func runImport() {
        showImportSheet = false
        #if os(macOS)
        do {
            if let imported = try BackupManager.presentImport(passphrase: backupPass) {
                let added = vm.mergeHistory(imported)
                backupMessage = "Импортировано записей: \(added)."
            }
        } catch {
            backupMessage = error.localizedDescription
        }
        #endif
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); Text(value).foregroundColor(.secondary) }
    }
}

// Меню в строке меню
struct MenuBarView: View {
    @EnvironmentObject var vm: PasswordViewModel
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрый пароль").font(.headline)
            coloredPassword(vm.password.isEmpty ? "—" : vm.password)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
                .id(vm.password)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: vm.password)
            HStack(spacing: 8) {
                Button { vm.generate() } label: { Label("Новый", systemImage: "arrow.clockwise") }
                Button {
                    vm.copyToClipboard()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: { Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc") }
                Button { vm.saveCurrent() } label: { Label("Сохранить", systemImage: "square.and.arrow.down") }
            }
            Divider()
            #if os(macOS)
            Button("Выйти") { NSApplication.shared.terminate(nil) }
            #endif
        }
        .padding(14).frame(width: 290)
    }
}

#Preview { RootView().environmentObject(PasswordViewModel()) }
