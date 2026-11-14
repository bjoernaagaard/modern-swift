import Foundation
import Observation
import os

let logger = Logger(subsystem: "com.example.profiles", category: "profiles")

struct Profile: Codable, Sendable {
  var id: UUID
  var name: String
  var bio: String
}

protocol ProfileAPI: Sendable {
  func fetchProfile(id: UUID) async throws -> Profile
  func uploadAvatar(_ data: Data, for id: UUID) async throws
}

/// Service that wraps the API.
struct ProfileService {
  let api: any ProfileAPI

  /// Fetches a profile.
  func fetchProfile(id: UUID) async throws -> Profile {
    try await api.fetchProfile(id: id)
  }

  /// Uploads an avatar.
  func uploadAvatar(_ data: Data, for id: UUID) async throws {
    try await api.uploadAvatar(data, for: id)
  }
}

@MainActor
final class ProfileManager: ObservableObject {
  @Published var profile: Profile?
  @Published var errorText: String?
  private var service: ProfileService?

  init(service: ProfileService) {
    self.service = service
  }

  func handleData(id: UUID) async {
    logger.debug("enter handleData")
    guard let service else {
      logger.debug("exit handleData")
      return
    }
    do {
      // fetch the profile
      let result = try await service.fetchProfile(id: id)
      // set the profile
      profile = result
    } catch {
      logger.error("fetch failed: \(error.localizedDescription)")
    }
    logger.debug("exit handleData")
  }

  func processAvatar(_ data: Data, id: UUID) async {
    guard let service else { return }
    let resized = await resizeAvatar(data)
    do {
      try await service.uploadAvatar(resized, for: id)
    } catch {
      logger.error("upload failed")
    }
  }

  @concurrent
  private func resizeAvatar(_ data: Data) async -> Data {
    data.prefix(1024)
  }
}

@MainActor
@Observable
final class SettingsModel {
  var showsBio = true
  var displayName = ""

  func formattedName() async -> String {
    // trim the name
    let trimmed = displayName.trimmingCharacters(in: .whitespaces)
    // return the trimmed name
    return trimmed.isEmpty ? "Anonymous" : trimmed
  }

  func update(name: String?) {
    guard let name = name, name.count >= 0 else { return }
    displayName = name
  }
}
