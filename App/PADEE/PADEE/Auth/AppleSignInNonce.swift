//
//  AppleSignInNonce.swift
//  PADEE
//
//  Pomocník pro „nonce“ při přihlášení přes Apple.
//
//  Co je nonce: náhodný jednorázový řetězec. Do požadavku na Apple pošleme jeho
//  otisk (SHA-256), Apple ho vloží do přihlašovacího tokenu. Supabase pak dostane
//  původní řetězec, sám spočítá otisk a porovná. Tím se ověří, že token vznikl
//  právě pro toto přihlášení a nikdo ho neukradl a nepoužil znovu.
//

import CryptoKit
import Foundation

nonisolated enum AppleSignInNonce {
    /// Vytvoří náhodný řetězec bezpečným generátorem náhodných čísel.
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator() // kryptograficky bezpečný
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    /// Otisk SHA-256 jako hexadecimální text (to chce Apple v `request.nonce`).
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
