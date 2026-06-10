import Foundation

class MockVoiceDictationManager {
    var transcript: String = ""
    var manualPrefix: String = ""
    var committedTranscript: String = ""
    var currentFullTranscript: String = ""
    
    func syncManualEdit(to newText: String) {
        manualPrefix = newText
        committedTranscript = currentFullTranscript
    }
    
    func receiveFull(full: String) {
        currentFullTranscript = full
        var newRecognizedText = full
        if !committedTranscript.isEmpty {
            if newRecognizedText.lowercased().hasPrefix(committedTranscript.lowercased()) {
                newRecognizedText = String(newRecognizedText.dropFirst(committedTranscript.count))
            } else {
                let committedWords = committedTranscript.split(separator: " ")
                let fullWords = full.split(separator: " ")
                if fullWords.count > committedWords.count {
                    newRecognizedText = fullWords.dropFirst(committedWords.count).joined(separator: " ")
                } else {
                    newRecognizedText = ""
                }
            }
        }
        let trimmedNew = newRecognizedText.trimmingCharacters(in: .whitespaces)
        
        let combined: String
        if manualPrefix.isEmpty {
            combined = trimmedNew
        } else {
            combined = manualPrefix + (manualPrefix.hasSuffix(" ") || trimmedNew.isEmpty ? "" : " ") + trimmedNew
        }
        
        transcript = combined
        print("Received full: '\(full)'")
        print("  -> trimmedNew: '\(trimmedNew)'")
        print("  -> transcript: '\(transcript)'")
    }
}

let m = MockVoiceDictationManager()
m.receiveFull(full: "buy milk")
// user deletes "milk"
m.syncManualEdit(to: "buy ")
m.receiveFull(full: "buy milk eggs")
