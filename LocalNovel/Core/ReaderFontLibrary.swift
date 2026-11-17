import Foundation
import CoreText
import UIKit

// MARK: - 自定义字体库（导入 ttf / otf）
//
// 文件落在 Application Support/ReaderFonts 下，启动时重新注册（幂等）。
// 注册用 CTFontManagerRegisterFontsForURL(.persistent)：只在 App 沙盒内生效，
// 不写系统字体目录，也不影响其他 App。
//
// 家族名取 CTFontDescriptor 的 kCTFontFamilyNameAttribute，存进 Preferences.customFontFamilies，
// 字体选择器直接列它，选中后按家族名取 UIFont(name:)。

enum ReaderFontLibrary {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("ReaderFonts", isDirectory: true)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil)) ?? []
    }

    static func familyName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String,
              !family.isEmpty else { return nil }
        return family
    }

    private static func register(_ url: URL) {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .persistent, &error)
        if let error { error.release() }
    }

    /// 启动时把已导入的字体注册一遍，返回可用家族名
    @discardableResult
    static func registerInstalled() -> [String] {
        ensureDirectory()
        var families: [String] = []
        for url in files() where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            register(url)
            if let family = familyName(of: url) { families.append(family) }
        }
        return families
    }

    /// 导入一个字体文件，成功返回家族名
    static func importFont(from url: URL) -> String? {
        ensureDirectory()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent
        let dest = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        guard (try? data.write(to: dest)) != nil else { return nil }

        register(dest)
        return familyName(of: dest)
    }

    /// 删除某个家族对应的字体文件（可能不止一个文件）
    static func remove(family: String) {
        for url in files() where familyName(of: url) == family {
            try? FileManager.default.removeItem(at: url)
            CTFontManagerUnregisterFontsForURL(url as CFURL, .persistent, nil)
        }
    }
}
