import Foundation

/// Built-in cloud settings so backups work with zero setup inside the app.
/// The publishable key is designed to be public; access is protected by the
/// row-level security rules in supabase/setup.sql and by on-device encryption.
enum SupabaseConfig {
    static let url = ""
    static let publishableKey = ""
}
