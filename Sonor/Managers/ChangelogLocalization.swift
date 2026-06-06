import Foundation
import SwiftUI

public struct ChangelogFeature: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let description: String
}

public class ChangelogLocalization {
    public static let shared = ChangelogLocalization()
    
    private init() {}
    
    // Order: en, pl, de, es, fr, it, ja, pt, zh
    private let translations: [String: [String]] = [
        "What's new in version %@": [
            "What's new in version %@",
            "Co nowego w wersji %@",
            "Was gibt es Neues in Version %@",
            "Novedades en la versión %@",
            "Nouveautés de la version %@",
            "Novità nella versione %@",
            "バージョン %@ の新機能",
            "O que há de novo na versão %@",
            "版本 %@ 的新增功能"
        ],
        "Understood": [
            "Understood",
            "Zrozumiałem",
            "Verstanden",
            "Entendido",
            "Compris",
            "Capito",
            "了解しました",
            "Entendi",
            "明白"
        ]
    ]
    
    public func getFeatures() -> [ChangelogFeature] {
        let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let index: Int
        
        switch appLanguage {
        case "en": index = 0
        case "pl": index = 1
        case "de": index = 2
        case "es": index = 3
        case "fr": index = 4
        case "it": index = 5
        case "ja": index = 6
        case "pt": index = 7
        case "zh": index = 8
        default: index = 0
        }
        
        let titles1 = [
            "New Notification Window",
            "Nowe okno powiadomień",
            "Neues Benachrichtigungsfenster",
            "Nueva ventana de notificaciones",
            "Nouvelle fenêtre de notifications",
            "Nuova finestra di notifiche",
            "新しい通知ウィンドウ",
            "Nova janela de notificações",
            "新的通知窗口"
        ]
        
        let desc1 = [
            "From now on, all updates will be presented in a new, readable, and aesthetic format.",
            "Od teraz wszystkie nowości w aplikacji będą prezentowane w nowym, czytelnym i estetycznym formacie.",
            "Ab sofort werden alle Updates in einem neuen, gut lesbaren und ästhetischen Format präsentiert.",
            "A partir de ahora, todas las actualizaciones se presentarán en un formato nuevo, legible y estético.",
            "Désormais, toutes les mises à jour seront présentées dans un nouveau format lisible et esthétique.",
            "Da ora in poi, tutti gli aggiornamenti saranno presentati in un formato nuovo, leggibile ed estetico.",
            "今後、すべてのアップデートは新しく読みやすく美しい形式で提示されます。",
            "A partir de agora, todas as atualizações serão apresentadas num formato novo, legível e estético.",
            "从现在开始，所有更新都将以一种新的、可读的且美观的格式呈现。"
        ]
        
        let titles2 = [
            "Mandatory Updates",
            "Obowiązkowe aktualizacje",
            "Obligatorische Updates",
            "Actualizaciones obligatorias",
            "Mises à jour obligatoires",
            "Aggiornamenti obbligatori",
            "必須のアップデート",
            "Atualizações obrigatórias",
            "强制更新"
        ]
        
        let desc2 = [
            "Older, unsupported app versions will display a clear message about the need to update.",
            "Starsze, niewspierane już wersje aplikacji będą wyświetlać jasny komunikat o konieczności aktualizacji.",
            "Ältere, nicht mehr unterstützte App-Versionen zeigen eine klare Meldung über die Notwendigkeit eines Updates.",
            "Las versiones más antiguas y no compatibles de la aplicación mostrarán un mensaje claro sobre la necesidad de actualizar.",
            "Les anciennes versions de l'application qui ne sont plus prises en charge afficheront un message clair sur la nécessité de mettre à jour.",
            "Le versioni precedenti non supportate dell'app mostreranno un chiaro messaggio sulla necessità di eseguire l'aggiornamento.",
            "サポートされなくなった古いアプリのバージョンには、アップデートの必要性に関する明確なメッセージが表示されます。",
            "As versões mais antigas e não suportadas da aplicação exibirão uma mensagem clara sobre a necessidade de atualização.",
            "不再受支持的旧应用版本将显示关于需要更新的清晰消息。"
        ]
        
        let titles3 = [
            "Performance Improvements",
            "Poprawa wydajności",
            "Leistungsverbesserungen",
            "Mejoras de rendimiento",
            "Amélioration des performances",
            "Miglioramenti delle prestazioni",
            "パフォーマンスの向上",
            "Melhorias de desempenho",
            "性能改进"
        ]
        
        let desc3 = [
            "The app now runs even faster thanks to background process optimizations.",
            "Aplikacja działa teraz jeszcze szybciej dzięki optymalizacji procesów działających w tle.",
            "Die App läuft jetzt dank Optimierungen von Hintergrundprozessen noch schneller.",
            "La aplicación ahora funciona aún más rápido gracias a las optimizaciones de los procesos en segundo plano.",
            "L'application s'exécute désormais encore plus rapidement grâce aux optimisations des processus en arrière-plan.",
            "L'app ora funziona ancora più velocemente grazie alle ottimizzazioni dei processi in background.",
            "バックグラウンドプロセスの最適化により、アプリの動作がさらに高速になりました。",
            "A aplicação agora funciona ainda mais rápido graças às otimizações dos processos em segundo plano.",
            "得益于后台进程的优化，应用程序现在的运行速度甚至更快。"
        ]
        
        /*
         // EXAMPLE FEATURES (Uncomment and modify for future updates):
        return [
            ChangelogFeature(icon: "sparkles", title: titles1[index], description: desc1[index]),
            ChangelogFeature(icon: "arrow.up.circle.fill", title: titles2[index], description: desc2[index]),
            ChangelogFeature(icon: "bolt.fill", title: titles3[index], description: desc3[index])
        ]
        */
        
        // No changes to describe for this update.
        return []
    }
    
    public func t(_ key: String) -> String {
        let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let index: Int
        
        switch appLanguage {
        case "en": index = 0
        case "pl": index = 1
        case "de": index = 2
        case "es": index = 3
        case "fr": index = 4
        case "it": index = 5
        case "ja": index = 6
        case "pt": index = 7
        case "zh": index = 8
        default: index = 0
        }
        
        if let translationArray = translations[key], index < translationArray.count {
            return translationArray[index]
        }
        
        return key
    }
}

public func t_changelog(_ key: String) -> String {
    return ChangelogLocalization.shared.t(key)
}
