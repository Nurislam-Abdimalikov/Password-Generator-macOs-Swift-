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
        vm.copyToClipboard() // внутри generate() уже вызывается
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
        showToast(ToastData(text: "Скопировано в буфер", icon: "doc.on.doc.fill", tint: Color(red: 0.20, green: 0.66, blue: 0.46)))
    }

    private func triggerSave() {
        vm.saveCurrent() // внутри generate() уже вызывается
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { saved = false } }
        showToast(ToastData(text: "Пароль сохранён", icon: "checkmark.circle.fill", tint: Color(red: 0.20, green: 0.66, blue: 0.46)))
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
                Toggle("Строчные буквы (a–z)", isOn: $vm.useLowercase).onChange(of: vm.useLowercase) { _ in vm.generate() }
                Toggle("Заглавные буквы (A–Z)", isOn: $vm.useUppercase).onChange(of: vm.useUppercase) { _ in vm.generate() }
                Toggle("Цифры (0–9)", isOn: $vm.useNumbers).onChange(of: vm.useNumbers) { _ in vm.generate() }
                Toggle("Символы (!@#$…)", isOn: $vm.useSymbols).onChange(of: vm.useSymbols) { _ in vm.generate() }
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

            Button { triggerSave() } label: {
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
                VStack(spacing: 10) {
                    ForEach(Array(vm.history.enumerated()), id: \ .element.id) { index, entry in
                        GlassCard {
                            HStack(spacing: 10) {
                                Text("\(index + 1).").font(.system(.body, design: .monospaced)).foregroundColor(.secondary).frame(width: 30, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    coloredPassword(entry.password).font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                                    Text(entry.date, style: .date).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button { vm.copy(entry) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                                Button { vm.deleteEntry(entry) } label: { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
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
struct SettingsView: View { @EnvironmentObject var vm: PasswordViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Настройки", subtitle: "Безопасность и о приложении")

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Защита", systemImage: "shield.lefthalf.filled").font(.headline)
                        infoRow(icon: vm.biometricIcon, title: vm.biometricName.capitalized, value: vm.canUseBiometrics ? "Доступно" : "Недоступно")
                        infoRow(icon: "number.square", title: "PIN-код", value: vm.hasPIN ? "Установлен" : "Не задан")
                        if vm.hasPIN { Button(role: .destructive) { vm.resetPIN() } label: { Label("Сбросить PIN-код", systemImage: "trash") }.padding(.top, 4) }
                    }
                }

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

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("О приложении", systemImage: "info.circle").font(.headline)
                        Text("KeyForge — генератор паролей для macOS. Несколько тем оформления, биометрия (Touch ID / Face ID), хранение в Keychain и иконка в строке меню. Глобальная горячая клавиша: ⌃⌥⌘G — сгенерировать и скопировать пароль из любого приложения.")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
            }
            .padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
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
