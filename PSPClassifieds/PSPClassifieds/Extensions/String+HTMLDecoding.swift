import Foundation

extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        
        // Decode named entities
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™"
        ]
        
        for (entity, char) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        
        // Decode decimal numeric entities (&#39; → ')
        while let range = result.range(of: "&#[0-9]+;", options: .regularExpression) {
            let entity = String(result[range])
            let numberString = entity.dropFirst(2).dropLast()
            if let codePoint = UInt32(numberString), let scalar = Unicode.Scalar(codePoint) {
                result = result.replacingCharacters(in: range, with: String(Character(scalar)))
            } else {
                break
            }
        }
        
        // Decode hex numeric entities (&#x27; → ')
        while let range = result.range(of: "&#[xX][0-9a-fA-F]+;", options: .regularExpression) {
            let entity = String(result[range])
            let hexString = entity.dropFirst(3).dropLast()
            if let codePoint = UInt32(hexString, radix: 16), let scalar = Unicode.Scalar(codePoint) {
                result = result.replacingCharacters(in: range, with: String(Character(scalar)))
            } else {
                break
            }
        }
        
        return result
    }
}
