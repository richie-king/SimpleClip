import Foundation

final class PinyinData {
    let initials: String
    let full: String

    init(initials: String, full: String) {
        self.initials = initials
        self.full = full
    }
}

enum PinyinHelper {
    private static let cache: NSCache<NSString, PinyinData> = {
        let c = NSCache<NSString, PinyinData>()
        c.countLimit = 1000
        return c
    }()

    /// 快速判断文本是否包含中文字符（Unicode 0x4E00 ~ 0x9FFF）
    static func hasChineseCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { ("\u{4E00}"..."\u{9FFF}").contains($0) }
    }

    /// 获取文本拼音数据，带内存缓存与前缀截断加速
    static func pinyinData(for text: String) -> PinyinData? {
        guard !text.isEmpty else { return nil }

        // 仅对前 200 个字符进行拼音提取（大幅降低长文本/代码段的转换开销）
        let truncated = String(text.prefix(200))
        guard hasChineseCharacters(truncated) else { return nil }

        let cacheKey = truncated as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let latin = truncated
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased() else { return nil }

        let initials = String(latin.split { $0.isWhitespace || $0.isPunctuation }.compactMap(\.first))
        let full = latin.filter { $0.isLetter || $0.isNumber }

        let data = PinyinData(initials: initials, full: full)
        cache.setObject(data, forKey: cacheKey)
        return data
    }

    /// 支持多词空格拆分的 AND 匹配，带两阶段短路与极致优化
    static func queryMatches(_ query: String, text: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }

        // 第一阶段：快速检查是否所有 token 都能在原文中直接命中（95%+ 场景直接返回，耗时 <0.001ms）
        let unhitTokens = tokens.filter { !text.localizedCaseInsensitiveContains($0) }
        if unhitTokens.isEmpty { return true }

        // 第二阶段：如果有未命中的词项，但未命中的词项包含非 ASCII（例如中文），或者原文无中文，直接判定不匹配
        guard hasChineseCharacters(text) else {
            return false
        }

        for token in unhitTokens {
            if !token.allSatisfy({ $0.isASCII }) {
                return false
            }
        }

        // 第三阶段：未命中项均为 ASCII 字母，尝试通过拼音（带缓存）命中
        guard let pinyin = pinyinData(for: text) else {
            return false
        }

        return unhitTokens.allSatisfy { token in
            let tokenLower = token.lowercased()
            return pinyin.initials.contains(tokenLower) || pinyin.full.contains(tokenLower)
        }
    }
}
