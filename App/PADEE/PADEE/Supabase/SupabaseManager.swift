//
//  SupabaseManager.swift
//  PADEE
//
//  Jedno sdílené připojení k Supabase pro celou iOS aplikaci.
//  Hodinky se k Supabase nepřipojují, data posílají přes iPhone (T10).
//

import Foundation
import Supabase

/// Přístupové údaje k Supabase, načtené ze souboru `Secrets.plist`.
///
/// Klíče nejsou přímo v kódu, protože kód je na GitHubu (viz CLAUDE.md).
/// `Secrets.plist` je v `.gitignore`; vzor je v `App/PADEE/Secrets.example.plist`.
///
/// `nonisolated`: v projektu je výchozí izolace `MainActor` (nastavení
/// SWIFT_DEFAULT_ACTOR_ISOLATION). Tahle čistá data na hlavní vlákno vázat
/// nepotřebujeme, takže je z toho vyjmeme.
nonisolated enum SupabaseConfig {
    static let url: URL = {
        guard let text = value(for: "SupabaseURL"), let url = URL(string: text) else {
            fatalError("V Secrets.plist chybí platná SupabaseURL.")
        }
        return url
    }()

    /// „Publishable key“ (dříve „anon key“). Smí být v aplikaci, protože data
    /// chrání RLS politiky v databázi, ne tajnost tohoto klíče.
    static let publishableKey: String = {
        guard let key = value(for: "SupabasePublishableKey"), !key.isEmpty else {
            fatalError("V Secrets.plist chybí SupabasePublishableKey.")
        }
        return key
    }()

    /// Přečte jednu hodnotu ze `Secrets.plist`, který je přibalený v aplikaci.
    private static func value(for key: String) -> String? {
        guard
            let fileURL = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: fileURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            fatalError("""
                Chybí soubor Secrets.plist. Zkopíruj App/PADEE/Secrets.example.plist \
                do složky App/PADEE/PADEE/, přejmenuj na Secrets.plist a doplň údaje ze Supabase.
                """)
        }
        return plist[key] as? String
    }
}

/// Sdílený klient. Použití kdekoli v aplikaci: `SupabaseManager.client`.
nonisolated enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey,
        options: SupabaseClientOptions(
            // Po startu aplikace hned vrátí uloženou relaci (přihlášení),
            // i když už je token prošlý; SDK si ho samo obnoví při prvním dotazu.
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
