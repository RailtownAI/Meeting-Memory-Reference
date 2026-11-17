//
//  WBiOSIntentPhoto.swift
//  WhiteboardApp
//
//  Reads the photo that Siri, Spotlight or Shortcuts passes to Remember Whiteboard, as JPEG.
//  Shared by the intent and its 27.3 tool twin.
//

import AppIntents
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import WhiteboardCore

enum WBiOSIntentPhoto {
    /// The photo as JPEG, or a sentence that says it could not be read.
    enum Result: Sendable {
        case jpeg(Data)
        case failed(String)
    }

    /// Longest side of the JPEG sent to the vision calls.
    static let maxPixelSize = 4096

    /// Tries, in order: each image type the file offers through `data(contentType:)`, the plain
    /// `data` property, and the file URL with security-scoped access. Logs which path worked.
    static func jpeg(from file: IntentFile) async -> Result {
        var notes: [String] = []

        let offered = file.availableContentTypes
        let imageTypes = offered.filter { $0.conforms(to: .image) }
        for type in imageTypes.isEmpty ? [UTType.image] : imageTypes {
            do {
                let data = try await file.data(contentType: type)
                if let jpeg = jpeg(from: data) {
                    WBLog.info("📷🗣️ Photo read with data(contentType: \(type.identifier)), \(data.count) bytes")
                    return .jpeg(jpeg)
                }
                notes.append("\(type.identifier): \(data.count) bytes \(prefixHex(data)) not an image")
            } catch {
                notes.append("\(type.identifier): \(error)")
            }
        }

        let plain = file.data
        if let jpeg = jpeg(from: plain) {
            WBLog.info("📷🗣️ Photo read with data, \(plain.count) bytes")
            return .jpeg(jpeg)
        }
        notes.append("data: \(plain.count) bytes \(prefixHex(plain))")

        if let url = file.fileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let jpeg = jpeg(from: data) {
                    WBLog.info("📷🗣️ Photo read from fileURL, \(data.count) bytes")
                    return .jpeg(jpeg)
                }
                notes.append("fileURL: \(data.count) bytes \(prefixHex(data))")
            } catch {
                notes.append("fileURL: \(error)")
            }
        } else {
            notes.append("fileURL: none")
        }

        let facts = "file \(file.filename), type \(file.type?.identifier ?? "none"), "
            + "offers [\(offered.map(\.identifier).joined(separator: ", "))]; "
            + notes.joined(separator: "; ")
        WBLog.warning("⚠️🗣️ Photo could not be read: \(facts)")
        return .failed("Meeting Memory could not open that photo. Try another one.")
    }

    /// Any image format ImageIO reads (HEIC, PNG, JPEG and others), upright, as JPEG.
    private static func jpeg(from data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
    }

    /// The first bytes as hex, which name the format (for example "ffd8ff" is JPEG).
    private static func prefixHex(_ data: Data) -> String {
        data.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
