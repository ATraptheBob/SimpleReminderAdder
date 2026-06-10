import Foundation

class MockVoiceDictationManager {
    var transcript: String = ""
    var manualPrefix: String = ""
    var committedWordCount: Int = 0
    var currentFullTranscript: String = ""
    
    func syncManualEdit(to newText: String) {
        manualPrefix = newText
        committedWordCount = currentFullTranscript.split(separator: " ").count
    }
    
    func receiveFull(full: String) {
        currentFullTranscript = full
        
        let fullWords = full.split(separator: " ")
        let newRecognizedText: String
        if fullWords.count > committedWordCount {
            newRecognizedText = fullWords.dropFirst(committedWordCount).joined(separator: " ")
        } else {
            newRecognizedText = ""
        }
        
        let trimmedNew = newRecognizedText.trimmingCharacters(in: .whitespaces)
        
        let combined: String
        if manualPrefix.isEmpty {
            combined = trimmedNew
        } else {
            combined = manualPrefix + (manualPrefix.hasSuffix(" ") || trimmedNew.isEmpty ? "" : " ") + trimmedNew
        }
        
        transcript = combined
        print("full: '\(full)' -> combined: '\(combined)'")
    }
}

let m = MockVoiceDictationManager()
m.receiveFull(full: "buy milk")
m.syncManualEdit(to: "buy mi")
m.receiveFull(full: "buy milk eggs")
m.receiveFull(full: "buy eggs") // Re-evaluation drops milk!
m.receiveFull(full: "buy eggs today") 
