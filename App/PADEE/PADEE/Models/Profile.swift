//
//  Profile.swift
//  PADEE
//
//  Model hráče. Odpovídá tabulce `public.profiles` v Supabase
//  (viz supabase/migrations/20261119120000_zakladni_schema.sql).
//

import Foundation

/// Profil hráče, jak ho vrací databáze.
///
/// `Codable` = umí se převést z/do JSONu, ve kterém Supabase posílá data.
/// `Sendable` = smí se bezpečně předávat mezi vlákny (síťové volání běží na pozadí).
nonisolated struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    /// 5znakové PADEE ID, např. „K7Q2M“. Podle něj si hráči přidávají přátele.
    let padeeId: String
    var displayName: String?
    var avatarURL: URL?
    var level: PlayerLevel?
    var homeClubId: UUID?

    /// Databáze používá snake_case (padee_id), Swift camelCase (padeeId).
    /// CodingKeys říkají, který sloupec patří ke které vlastnosti.
    enum CodingKeys: String, CodingKey {
        case id
        case padeeId = "padee_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case level
        case homeClubId = "home_club_id"
    }
}

/// Úroveň hráče. Hodnoty odpovídají enumu `player_level` v databázi.
nonisolated enum PlayerLevel: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced

    /// Text pro zobrazení v aplikaci.
    var title: String {
        switch self {
        case .beginner: "Začátečník"
        case .intermediate: "Střední"
        case .advanced: "Pokročilý"
        }
    }
}
