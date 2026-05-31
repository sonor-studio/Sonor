import SwiftUI

struct BenchmarkView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appTheme") private var appTheme = "system"
    var colorScheme: ColorScheme {
        if appTheme == "dark" {
            return .dark
        } else if appTheme == "light" {
            return .light
        } else {
            let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return appleInterfaceStyle == "Dark" ? .dark : .light
        }
    }
    @StateObject private var audioManager = AudioManager()
    @ObservedObject private var localizer = LocalizationManager.shared
    
    @State private var step: Int = 0 // 0: Intro, 1: Writing, 2: Speaking, 3: Summary
    @State private var currentText: String = ""
    @State private var lastTextIndex: Int = -1
    
    // Writing test
    @State private var typedText: String = ""
    @State private var writingTimer: Timer?
    @State private var writingElapsed: Double = 0.0
    @State private var isWritingStarted: Bool = false
    @State private var isWritingFinished: Bool = false
    
    // Speaking test
    @State private var speakingTimer: Timer?
    @State private var speakingElapsed: Double = 0.0
    @State private var isSpeakingStarted: Bool = false
    @State private var isSpeakingFinished: Bool = false
    @State private var waveLevels: [CGFloat] = Array(repeating: 0.01, count: 36)
    
    @State private var isCloseHovered = false
    
    var presets: [String] {
        let lang = localizer.appLanguage
        switch lang {
        case "en":
            return [
                "Fast typing on a keyboard requires focus, but speaking allows you to express your thoughts freely in a fraction of a second without effort.",
                "Speech recognition technology is completely changing how we interact with text every day, saving valuable time.",
                "In today's busy world, every single minute counts, making local voice transcription an essential tool for productivity.",
                "Creating notes, writing emails, and capturing ideas has never been so simple and secure, as all data remains offline.",
                "Switching to voice typing helps relieve tension in your hands and spine while giving you full creative freedom and speed."
            ]
        case "de":
            return [
                "Schnelles Tippen auf einer Tastatur erfordert Konzentration, aber das Sprechen ermöglicht es Ihnen, Ihre Gedanken mühelos auszudrücken.",
                "Die Spracherkennungstechnologie revolutioniert die Art und Weise, wie wir täglich mit Texten arbeiten, und spart wertvolle Zeit.",
                "In der heutigen hektischen Welt zählt jede Minute, weshalb die lokale Sprachtranskription zu einem unverzichtbaren Werkzeug wird.",
                "Das Erstellen von Notizen, das Schreiben von E-Mails und das Festhalten von Ideen war noch nie so einfach und sicher, da alle Daten offline bleiben.",
                "Der Wechsel zur Spracheingabe entlastet Hände und Wirbelsäule und bietet gleichzeitig volle kreative Freiheit und erstaunliche Geschwindigkeit."
            ]
        case "es":
            return [
                "Escribir rápido en un teclado requiere concentración, pero hablar te permite expresar tus pensamientos libremente en una fracción de segundo.",
                "La tecnología de reconocimiento de voz revoluciona la forma en que trabajamos con el texto cada día, ahorrando un tiempo valioso.",
                "En el ajetreado mundo de hoy, cada minuto vale su peso en oro, por lo que la transcripción de voz local se convierte en una herramienta clave.",
                "Crear notas, escribir correos electrónicos y plasmar ideas nunca ha sido tan sencillo y seguro, ya que todos los datos permanecen fuera de línea.",
                "Pasar al dictado por voz ayuda a aliviar la tensión en las manos y la espalda, a la vez que ofrece total libertad creativa y gran rapidez."
            ]
        case "fr":
            return [
                "Taper rapidement sur un clavier demande de la concentration, mais parler vous permet d'exprimer vos pensées librement en un clin d'œil.",
                "La technologie de reconnaissance vocale révolutionne notre façon de travailler avec le texte au quotidien, nous faisant gagner un temps précieux.",
                "Dans notre monde moderne très actif, chaque minute compte, c'est pourquoi la transcription vocale locale devient un outil essentiel.",
                "Prendre des notes, rédiger des e-mails et coucher ses idées sur papier n'a jamais été aussi simple et sécurisé, car les données restent hors ligne.",
                "Passer à la saisie vocale permet de soulager vos mains et votre dos, tout en vous offrant une liberté créative totale et une vitesse incroyable."
            ]
        case "it":
            return [
                "Digitare rapidamente su una tastiera richiede concentrazione, ma parlare ti consente di esprimere i tuoi pensieri liberamente in pochi istanti.",
                "La tecnologia di riconoscimento vocale sta rivoluzionando il modo in che lavoriamo con i testi ogni giorno, facendoci risparmiare tempo prezioso.",
                "Nel mondo frenetico di oggi, ogni singolo minuto è prezioso, il che rende la trascrizione vocale locale uno strumento davvero fondamentale.",
                "Prendere appunti, scrivere e-mail e registrare idee non é mai stato così semplice e sicuro, poiché tutti i dati rimangono offline.",
                "Passare alla digitazione vocale aiuta ad alleviare la tensione a mani e schiena, offrendo al contempo massima libertà creativa e rapidità."
            ]
        case "ja":
            return [
                "キーボードでの高速入力には集中力が必要ですが、話すことで瞬時に何の努力もなく自由に考えを表現することができます。",
                "音声認識技術は、私たちが毎日テキストを扱う方法を根本から変え、貴重な時間を大幅に節約してくれます。",
                "今日の忙しい世界では、一分一秒が非常に貴重であり、そのためローカルでの音声文字起こしが極めて重要なツールとなっています。",
                "すべてのデータがオフラインで保存されるため、メモの作成、メールの執筆、アイデアの記録がかつてないほど簡単かつ安全になります。",
                "音声入力に切り替えることで、手や背中の負担を軽減しながら、同時に完全な創作の自由と圧倒的な処理スピードが得られます。"
            ]
        case "pt":
            return [
                "Digitar rapidamente no teclado exige concentração, mas falar permite que você expresse seus pensamentos livremente em uma fração de segundo.",
                "A tecnologia de reconhecimento de voz revoluciona a maneira como trabalhamos com texto todos os dias, economizando um tempo valioso.",
                "No mundo agitado de hoje, cada minuto vale ouro, e por isso a transcrição de voz local está se tornando uma ferramenta indispensável.",
                "Criar notas, escrever e-mails e registrar ideias nunca foi tão simples e seguro, pois todos os dados permanecem totalmente offline.",
                "Mudar para a digitação por voz ajuda a aliviar a tensão nas mãos e nas costas, proporcionando total liberdade criativa e velocidade incrível."
            ]
        default:
            return [
                "Szybkie pisanie na klawiaturze wymaga skupienia, ale mówienie pozwala na swobodne wyrażanie myśli w ułamku sekundy bez wysiłku.",
                "Technologia rozpoznawania mowy rewolucjonizuje sposób, w jaki pracujemy z tekstem każdego dnia, oszczędzając cenny czas.",
                "W dzisiejszym zabieganym świecie każda minuta jest na wagę złota, dlatego lokalna transkrypcja głosu staje się kluczowym narzędziem.",
                "Tworzenie notatek, pisanie e-maili i spisywanie pomysłów nigdy nie było tak proste i bezpieczne, ponieważ wszystkie dane pozostają offline.",
                "Przejście na pisanie głosowe pozwala odciążyć dłonie i kręgosłup, dając jednocześnie pełną swobodę twórczą i niesamowitą prędkość działania."
            ]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(t("Typing vs Speaking Speed Test"))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isCloseHovered ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                    .onTapGesture {
                        stopAllTimers()
                        dismiss()
                    }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            // Scrollable Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 1).id("topOfScrollContent")
                        if step == 0 {
                            introContentView
                        } else if step == 1 {
                            writingContentView
                        } else if step == 2 {
                            speakingContentView
                        } else if step == 3 {
                            summaryContentView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
                .onChange(of: isWritingFinished) { finished in
                    if finished {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation {
                                proxy.scrollTo("writingTimeLabel", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: step) { _ in
                    proxy.scrollTo("topOfScrollContent", anchor: .top)
                }
            }
            
            // Fixed Bottom Action Buttons (Sticky)
            VStack(spacing: 0) {
                Divider()
                bottomButtonsView
                    .padding(24)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .frame(width: 550, height: 480)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            selectRandomText()
        }
        .onDisappear {
            stopAllTimers()
        }
    }
    
    private func selectRandomText() {
        var nextIndex = Int.random(in: 0..<presets.count)
        if presets.count > 1 {
            while nextIndex == lastTextIndex {
                nextIndex = Int.random(in: 0..<presets.count)
            }
        }
        lastTextIndex = nextIndex
        currentText = presets[nextIndex]
    }
    
    private func stopAllTimers() {
        writingTimer?.invalidate()
        writingTimer = nil
        speakingTimer?.invalidate()
        speakingTimer = nil
        _ = audioManager.stopRecording()
    }
    
    // MARK: - Content Views
    
    private var introContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Don't just take our word for it."))
                    .font(.system(size: 22, weight: .black))
            }
            
            Text(t("Voice typing is on average 3.5x faster than keyboard typing. Run a quick test and prove it to yourself. See how much faster you can get your thoughts onto the screen."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Test instructions:"))
                    .font(.system(size: 14, weight: .bold))
                
                HStack(alignment: .top, spacing: 10) {
                    Text("1.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("First, retype the displayed text using your keyboard. The timer starts automatically when you begin typing."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Text("2.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("Then read the same text aloud. You will measure your speaking time."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Text("3.")
                        .font(.system(size: 13, weight: .bold))
                    Text(t("At the end you will see a detailed summary and find out how much time you save."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    private var writingContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t("STEP 1 OF 2: TYPING"))
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Text(String(format: t("Timer: %.1fs"), writingElapsed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Text(t("Retype the text below as fast as you can:"))
                .font(.system(size: 14, weight: .bold))
            
            Text(currentText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                )
            
            TextEditor(text: $typedText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .disabled(isWritingFinished)
                .onChange(of: typedText) { newValue in
                    if !isWritingStarted && !newValue.isEmpty {
                        startWritingTimer()
                    }
                }
            
            if isWritingFinished {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .bold))
                    Text(String(format: t("Your typing time: %.1fs"), writingElapsed))
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.vertical, 8)
                .transition(.opacity)
                .id("writingTimeLabel")
            } else if !isWritingStarted {
                HStack {
                    Spacer()
                    Text(t("Start typing to auto-start the timer..."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Text(t("Keep typing..."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var speakingContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t("STEP 2 OF 2: SPEAKING"))
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Text(String(format: t("Timer: %.1fs"), speakingElapsed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Text(t("Read the same text aloud:"))
                .font(.system(size: 14, weight: .bold))
            
            Text(currentText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                )
            
            VStack {
                Spacer()
                
                if isSpeakingStarted && !isSpeakingFinished {
                    // Waveform visualization
                    HStack(spacing: 2) {
                        Spacer()
                        ForEach(0..<waveLevels.count, id: \.self) { index in
                            let level = waveLevels[index]
                            let barHeight = CGFloat(2 + (level * 350))
                            
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: 3, height: min(barHeight, 40))
                        }
                        Spacer()
                    }
                    .frame(height: 40)
                    .transition(.opacity)
                } else if isSpeakingFinished {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(format: t("Your recording time: %.1fs"), speakingElapsed))
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .transition(.opacity)
                } else {
                    HStack {
                        Spacer()
                        Text(t("Click the button below to start speaking..."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                Spacer()
            }
            .frame(minHeight: 150)
        }
    }
    
    private var summaryContentView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: writingElapsed > speakingElapsed ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Your test result"))
                    .font(.system(size: 20, weight: .black))
                
                if speakingElapsed < writingElapsed {
                    Text(String(format: t("Speaking was %.1fx faster than typing!"), speedFactor))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                } else if writingElapsed < speakingElapsed {
                    let slowFactor = speakingElapsed / max(0.1, writingElapsed)
                    Text(String(format: t("Speaking was %.1fx slower than typing!"), slowFactor))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                } else {
                    Text(t("Speaking and typing took exactly the same time!"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                // Writing box
                let isWritingWinner = writingElapsed <= speakingElapsed
                VStack(spacing: 8) {
                    Text(t("CLASSIC TYPING"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1fs", writingElapsed))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    
                    Text(String(format: t("%.0f words/min"), Double(wpmWriting)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isWritingWinner ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                                    lineWidth: isWritingWinner ? 2 : 1
                                )
                        )
                )
                
                // Speaking box
                let isSpeakingWinner = speakingElapsed < writingElapsed
                VStack(spacing: 8) {
                    Text(t("VOICE TYPING"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(String(format: "%.1fs", speakingElapsed))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    
                    Text(String(format: t("%.0f words/min"), Double(wpmSpeaking)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isSpeakingWinner ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)),
                                    lineWidth: isSpeakingWinner ? 2 : 1
                                )
                        )
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if speakingElapsed < writingElapsed {
                    Text(String(format: t("You saved %.1f seconds on just one short sentence!"), timeDifference))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("Imagine writing long emails, articles, or notes this way. Over a year, you reclaim entire days of free time, and the app works 100% locally without collecting any data."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                } else {
                    Text(t("Wait, what...? Are you sure you didn't cheat? 😉"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(t("You got an incredible keyboard score (or spoke in slow motion on purpose!). This is rare in everyday life — voice typing is usually 3.5x faster on average and saves a lot of energy for your hands. Try again, this time without going easy on the keyboard! 🚀"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Fixed Bottom Buttons View
    
    private var bottomButtonsView: some View {
        Group {
            if step == 0 {
                introBottomButtons
            } else if step == 1 {
                writingBottomButtons
            } else if step == 2 {
                speakingBottomButtons
            } else if step == 3 {
                summaryBottomButtons
            }
        }
    }
    
    private var introBottomButtons: some View {
        Button(action: {
            step = 1
        }) {
            Text(t("Start test"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    private var writingBottomButtons: some View {
        Group {
            if !isWritingFinished {
                Button(action: {
                    finishWriting()
                }) {
                    Text(t("Finish"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isWritingStarted ? (colorScheme == .dark ? .black : .white) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isWritingStarted ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!isWritingStarted)
            } else {
                Button(action: {
                    step = 2
                }) {
                    Text(t("Next"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private var speakingBottomButtons: some View {
        Group {
            if !isSpeakingStarted {
                Button(action: {
                    startSpeaking()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                        Text(t("Start speaking"))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else if isSpeakingStarted && !isSpeakingFinished {
                Button(action: {
                    finishSpeaking()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text(t("Stop and finish"))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else {
                Button(action: {
                    step = 3
                }) {
                    Text(t("See summary"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private var summaryBottomButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                resetTest()
            }) {
                Text(t("Repeat with another text"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            Button(action: {
                stopAllTimers()
                dismiss()
            }) {
                Text(t("Close"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    // MARK: - Logic
    
    private func startWritingTimer() {
        isWritingStarted = true
        writingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            writingElapsed += 0.1
        }
    }
    
    private func finishWriting() {
        writingTimer?.invalidate()
        writingTimer = nil
        isWritingFinished = true
    }
    
    private func startSpeaking() {
        isSpeakingStarted = true
        waveLevels = (0..<36).map { _ in CGFloat.random(in: 0.01...0.03) }
        try? audioManager.startRecording()
        speakingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            speakingElapsed += 0.05
            
            withAnimation(.spring(response: 0.08, dampingFraction: 0.6)) {
                let micLevel = CGFloat(audioManager.audioLevel)
                let time = Date().timeIntervalSinceReferenceDate
                
                waveLevels = (0..<36).map { i in
                    let amp = max(0.01, micLevel * 1.8)
                    let sine = sin(time * 10 + Double(i) * 0.25)
                    let noise = Double.random(in: 0.0...0.02)
                    let rawVal = abs(sine * amp) + noise
                    return CGFloat(max(0.01, min(0.12, rawVal)))
                }
            }
        }
    }
    
    private func finishSpeaking() {
        speakingTimer?.invalidate()
        speakingTimer = nil
        isSpeakingFinished = true
        _ = audioManager.stopRecording()
    }
    
    private func resetTest() {
        stopAllTimers()
        step = 1
        typedText = ""
        writingElapsed = 0.0
        isWritingStarted = false
        isWritingFinished = false
        speakingElapsed = 0.0
        isSpeakingStarted = false
        isSpeakingFinished = false
        waveLevels = Array(repeating: 0.01, count: 36)
        selectRandomText()
    }
    
    // Stats calculations
    private var wordCount: Int {
        currentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    private var wpmWriting: Double {
        guard writingElapsed > 0 else { return 0 }
        return Double(wordCount) / (writingElapsed / 60.0)
    }
    
    private var wpmSpeaking: Double {
        guard speakingElapsed > 0 else { return 0 }
        return Double(wordCount) / (speakingElapsed / 60.0)
    }
    
    private var speedFactor: Double {
        guard speakingElapsed > 0 else { return 1.0 }
        return writingElapsed / speakingElapsed
    }
    
    private var timeDifference: Double {
        max(0, writingElapsed - speakingElapsed)
    }
}
