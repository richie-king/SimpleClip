import Foundation

enum SensitiveMasker {
    private struct Rule {
        let pattern: NSRegularExpression
        let maskHandler: (String, NSTextCheckingResult) -> (NSRange, String)
    }

    private static let rules: [Rule] = {
        var list: [Rule] = []

        // 1. GitHub Tokens
        if let regex = try? NSRegularExpression(
            pattern: "(gh[pousr]_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{50,})",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let matchedString = (fullText as NSString).substring(with: match.range)
                let masked = maskMiddle(matchedString, prefixLen: 4, suffixLen: 4)
                return (match.range, masked)
            })
        }

        // 2. OpenAI / LLM API keys: sk-...
        if let regex = try? NSRegularExpression(
            pattern: "sk-[A-Za-z0-9_\\-]{20,}",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let matchedString = (fullText as NSString).substring(with: match.range)
                let masked = maskMiddle(matchedString, prefixLen: 3, suffixLen: 4)
                return (match.range, masked)
            })
        }

        // 3. AWS Access Key ID
        if let regex = try? NSRegularExpression(
            pattern: "\\b(AKIA|ABIA|ACCA|ASIA)[0-9A-Z]{16}\\b",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let matchedString = (fullText as NSString).substring(with: match.range)
                let masked = maskMiddle(matchedString, prefixLen: 4, suffixLen: 4)
                return (match.range, masked)
            })
        }

        // 4. PEM 私钥
        if let regex = try? NSRegularExpression(
            pattern: "-----[A-Z ]*BEGIN [A-Z0-9 ]*PRIVATE KEY-----([\\s\\S]*?)-----[A-Z ]*END [A-Z0-9 ]*PRIVATE KEY-----",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let masked = "-----BEGIN PRIVATE KEY-----\n[•••••••• 敏感私钥内容已遮蔽 ••••••••]\n-----END PRIVATE KEY-----"
                return (match.range, masked)
            })
        }

        // 5. Slack Tokens
        if let regex = try? NSRegularExpression(
            pattern: "\\bxox[baprs]-[0-9a-zA-Z-]{12,}\\b",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let matchedString = (fullText as NSString).substring(with: match.range)
                let masked = maskMiddle(matchedString, prefixLen: 5, suffixLen: 4)
                return (match.range, masked)
            })
        }

        // 6. Generic Bearer Token
        if let regex = try? NSRegularExpression(
            pattern: "(?i)\\b(bearer\\s+)([A-Za-z0-9_\\-\\.]{25,})\\b",
            options: []
        ) {
            list.append(Rule(pattern: regex) { fullText, match in
                let prefixRange = match.range(at: 1)
                let tokenRange = match.range(at: 2)
                let prefix = (fullText as NSString).substring(with: prefixRange)
                let token = (fullText as NSString).substring(with: tokenRange)
                let masked = prefix + maskMiddle(token, prefixLen: 4, suffixLen: 4)
                return (match.range, masked)
            })
        }

        return list
    }()

    private static func maskMiddle(_ string: String, prefixLen: Int, suffixLen: Int) -> String {
        guard string.count > prefixLen + suffixLen + 4 else {
            return String(repeating: "•", count: string.count)
        }
        let start = string.prefix(prefixLen)
        let end = string.suffix(suffixLen)
        return "\(start)••••••••\(end)"
    }

    /// 判断文本是否包含敏感凭证
    static func isSensitive(_ text: String) -> Bool {
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        for rule in rules {
            if rule.pattern.firstMatch(in: text, options: [], range: fullRange) != nil {
                return true
            }
        }
        return false
    }

    /// 对文本中的敏感凭证进行脱敏遮蔽
    static func mask(_ text: String) -> String {
        var result = text as NSString
        var matches: [(range: NSRange, replacement: String)] = []

        let fullRange = NSRange(location: 0, length: result.length)
        for rule in rules {
            let found = rule.pattern.matches(in: text, options: [], range: fullRange)
            for m in found {
                let (r, rep) = rule.maskHandler(text, m)
                matches.append((range: r, replacement: rep))
            }
        }

        // 从后往前替换，避免前面的替换影响后面的 range
        matches.sort { $0.range.location > $1.range.location }
        for item in matches {
            guard item.range.location + item.range.length <= result.length else { continue }
            result = result.replacingCharacters(in: item.range, with: item.replacement) as NSString
        }

        return result as String
    }
}
