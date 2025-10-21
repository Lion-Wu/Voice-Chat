import Foundation

/// Centralized access to localized strings used across the application.
enum L10n {
    enum General {
        static let ok = NSLocalizedString("general.ok", comment: "Default OK button title")
        static let cancel = NSLocalizedString("general.cancel", comment: "Cancel button title")
        static let delete = NSLocalizedString("general.delete", comment: "Delete button title")
        static let close = NSLocalizedString("general.close", comment: "Close button title")
        static let done = NSLocalizedString("general.done", comment: "Done button title")
        static let settings = NSLocalizedString("general.settings", comment: "Settings button title")
        static let errorTitle = NSLocalizedString("general.errorTitle", comment: "Title for generic error alerts")
        static let destructiveWarning = NSLocalizedString("general.destructiveWarning", comment: "Warning shown before destructive actions")
    }

    enum Sidebar {
        static let chats = NSLocalizedString("sidebar.chats", comment: "Title for the chats section in the sidebar")
        static let newChat = NSLocalizedString("sidebar.newChat", comment: "Label for the new chat action")
        static let rename = NSLocalizedString("sidebar.rename", comment: "Rename action title")
        static let delete = NSLocalizedString("sidebar.delete", comment: "Delete action title")
        static let renameDialogTitle = NSLocalizedString("sidebar.renameDialogTitle", comment: "Title for the rename dialog")
        static let renameDialogPlaceholder = NSLocalizedString("sidebar.renameDialogPlaceholder", comment: "Placeholder for the rename dialog text field")
        static let renameDialogSave = NSLocalizedString("sidebar.renameDialogSave", comment: "Save action title in rename dialog")
    }

    enum Chat {
        static let editingBannerTitle = NSLocalizedString("chat.editingBannerTitle", comment: "Banner text shown while editing a message")
        static let editingBannerCancelHelp = NSLocalizedString("chat.editingBannerCancelHelp", comment: "Help text for cancel editing button")
        static let messagePlaceholder = NSLocalizedString("chat.messagePlaceholder", comment: "Placeholder for the message composer")
        static let messagePlaceholderHint = NSLocalizedString("chat.messagePlaceholderHint", comment: "Accessibility hint for the message composer placeholder")
        static let openFullScreenComposer = NSLocalizedString("chat.openFullScreenComposer", comment: "Accessibility label for opening the full screen composer")
        static let stopDictation = NSLocalizedString("chat.stopDictation", comment: "Accessibility label for stopping dictation")
        static let startDictation = NSLocalizedString("chat.startDictation", comment: "Accessibility label for starting dictation")
        static let dictationHelpStop = NSLocalizedString("chat.dictationHelpStop", comment: "Help text when dictation is active")
        static let dictationHelpStart = NSLocalizedString("chat.dictationHelpStart", comment: "Help text when dictation is inactive")
        static let stopGeneration = NSLocalizedString("chat.stopGeneration", comment: "Accessibility label for stopping the current response")
        static let openRealtimeVoice = NSLocalizedString("chat.openRealtimeVoice", comment: "Accessibility label for opening realtime voice overlay")
        static let sendMessage = NSLocalizedString("chat.sendMessage", comment: "Accessibility label for sending a message")
        static let noChatSelected = NSLocalizedString("chat.noChatSelected", comment: "Placeholder shown when no chat is selected")
        static let connectionTimeout = NSLocalizedString("chat.connectionTimeout", comment: "Error message shown when the chat stream times out")
        static let creatingNewChat = NSLocalizedString("chat.creatingNewChat", comment: "Status message shown while creating a new chat")
        static let defaultSessionTitle = NSLocalizedString("chat.defaultSessionTitle", comment: "Default title for a new chat session")
        static let fullScreenComposerTitle = NSLocalizedString("chat.fullScreenComposerTitle", comment: "Navigation title for the full-screen composer")
    }

    enum Settings {
        static let title = NSLocalizedString("settings.title", comment: "Navigation title for the settings view")
        static let voiceServerSection = NSLocalizedString("settings.voiceServerSection", comment: "Voice server section title")
        static let serverAddressLabel = NSLocalizedString("settings.serverAddressLabel", comment: "Label for server address field")
        static let serverAddressPlaceholder = NSLocalizedString("settings.serverAddressPlaceholder", comment: "Placeholder for server address field")
        static let textLanguageLabel = NSLocalizedString("settings.textLanguageLabel", comment: "Label for text language field")
        static let textLanguagePlaceholder = NSLocalizedString("settings.textLanguagePlaceholder", comment: "Placeholder for text language field")
        static let modelPresetSection = NSLocalizedString("settings.modelPresetSection", comment: "Model preset section title")
        static let currentPresetLabel = NSLocalizedString("settings.currentPresetLabel", comment: "Label for current preset picker")
        static let currentPreset = NSLocalizedString("settings.currentPreset", comment: "Title for the current preset picker")
        static let addPreset = NSLocalizedString("settings.addPreset", comment: "Title for add preset action")
        static let deletePreset = NSLocalizedString("settings.deletePreset", comment: "Title for delete preset action")
        static let deletePresetConfirmation = NSLocalizedString("settings.deletePresetConfirmation", comment: "Confirmation message before deleting preset")
        static let deletePresetPrompt = NSLocalizedString("settings.deletePresetPrompt", comment: "Alert title for deleting a preset")
        static let loadingModels = NSLocalizedString("settings.loadingModels", comment: "Status label while loading available models")
        static let failedToLoadModels = NSLocalizedString("settings.failedToLoadModels", comment: "Status label when models failed to load")
        static let referenceTextPlaceholder = NSLocalizedString("settings.referenceTextPlaceholder", comment: "Placeholder for preset reference text field")
        static let applyingPreset = NSLocalizedString("settings.applyingPreset", comment: "Status text while applying a preset")
        static let presetNameLabel = NSLocalizedString("settings.presetNameLabel", comment: "Label for preset name field")
        static let presetNamePlaceholder = NSLocalizedString("settings.presetNamePlaceholder", comment: "Placeholder for preset name field")
        static let refAudioPathLabel = NSLocalizedString("settings.refAudioPathLabel", comment: "Label for reference audio path field")
        static let refAudioPathPlaceholder = NSLocalizedString("settings.refAudioPathPlaceholder", comment: "Placeholder for reference audio path field")
        static let promptTextLabel = NSLocalizedString("settings.promptTextLabel", comment: "Label for prompt text field")
        static let promptLangLabel = NSLocalizedString("settings.promptLangLabel", comment: "Label for prompt language field")
        static let promptLangPlaceholder = NSLocalizedString("settings.promptLangPlaceholder", comment: "Placeholder for prompt language field")
        static let gptWeightsLabel = NSLocalizedString("settings.gptWeightsLabel", comment: "Label for GPT weights field")
        static let gptWeightsPlaceholder = NSLocalizedString("settings.gptWeightsPlaceholder", comment: "Placeholder for GPT weights field")
        static let sovitsWeightsLabel = NSLocalizedString("settings.sovitsWeightsLabel", comment: "Label for SoVITS weights field")
        static let sovitsWeightsPlaceholder = NSLocalizedString("settings.sovitsWeightsPlaceholder", comment: "Placeholder for SoVITS weights field")
        static let applyPresetNow = NSLocalizedString("settings.applyPresetNow", comment: "Button title for applying the current preset")
        static let presetDefaultName = NSLocalizedString("settings.presetDefaultName", comment: "Default voice preset name")
        static let newPresetDefaultName = NSLocalizedString("settings.newPresetDefaultName", comment: "Default name used when creating a preset")
        static let voiceOutputSection = NSLocalizedString("settings.voiceOutputSection", comment: "Voice output section title")
        static let enableStreaming = NSLocalizedString("settings.enableStreaming", comment: "Label for enable streaming toggle")
        static let autoReadAfterGeneration = NSLocalizedString("settings.autoReadAfterGeneration", comment: "Label for auto read toggle")
        static let splitMethod = NSLocalizedString("settings.splitMethod", comment: "Label for split method picker")
        static let splitOptionCut0 = NSLocalizedString("settings.splitOption.cut0", comment: "Split option with no split")
        static let splitOptionCut1 = NSLocalizedString("settings.splitOption.cut1", comment: "Split option for every four sentences")
        static let splitOptionCut2 = NSLocalizedString("settings.splitOption.cut2", comment: "Split option for every 50 characters")
        static let splitOptionCut3 = NSLocalizedString("settings.splitOption.cut3", comment: "Split option by Chinese period")
        static let splitOptionCut4 = NSLocalizedString("settings.splitOption.cut4", comment: "Split option by English period")
        static let splitOptionCut5 = NSLocalizedString("settings.splitOption.cut5", comment: "Split option by punctuation")
        static let chatServerSection = NSLocalizedString("settings.chatServerSection", comment: "Chat server section title")
        static let chatApiUrlLabel = NSLocalizedString("settings.chatApiUrlLabel", comment: "Label for chat API URL field")
        static let chatApiUrlPlaceholder = NSLocalizedString("settings.chatApiUrlPlaceholder", comment: "Placeholder for chat API URL field")
        static let loadingModelList = NSLocalizedString("settings.loadingModelList", comment: "Status text while loading chat models")
        static let selectModel = NSLocalizedString("settings.selectModel", comment: "Picker label for selecting a model")
        static let refreshModelList = NSLocalizedString("settings.refreshModelList", comment: "Button title for refreshing the model list")
        static let errorEmptyApiUrl = NSLocalizedString("settings.errorEmptyApiUrl", comment: "Error when the API URL is empty")
        static let errorInvalidApiUrl = NSLocalizedString("settings.errorInvalidApiUrl", comment: "Error when the API URL is invalid")
        static func errorRequestFailed(_ message: String) -> String {
            let format = NSLocalizedString("settings.errorRequestFailed", comment: "Template for a failed request error")
            return String(format: format, message)
        }
        static let errorParseFailed = NSLocalizedString("settings.errorParseFailed", comment: "Error when the model list cannot be parsed")
        static let gptWeightsName = NSLocalizedString("settings.gptWeightsName", comment: "Display name for GPT weights")
        static let sovitsWeightsName = NSLocalizedString("settings.sovitsWeightsName", comment: "Display name for SoVITS weights")
        static func errorWeightsHTTP(_ name: String, _ code: Int) -> String {
            let format = NSLocalizedString("settings.errorWeightsHTTP", comment: "Template for HTTP errors while setting voice weights")
            return String(format: format, name, code)
        }
        static func errorWeightsGeneric(_ name: String, _ message: String) -> String {
            let format = NSLocalizedString("settings.errorWeightsGeneric", comment: "Template for generic errors while setting voice weights")
            return String(format: format, name, message)
        }
        static func errorWeightsInvalidURL(_ name: String) -> String {
            let format = NSLocalizedString("settings.errorWeightsInvalidURL", comment: "Template shown when the weights endpoint URL cannot be constructed")
            return String(format: format, name)
        }
    }

    enum VoiceMessage {
        static let copy = NSLocalizedString("voiceMessage.copy", comment: "Copy action title")
        static let selectText = NSLocalizedString("voiceMessage.selectText", comment: "Select text action title")
        static let edit = NSLocalizedString("voiceMessage.edit", comment: "Edit action title")
        static let errorTitle = NSLocalizedString("voiceMessage.errorTitle", comment: "Title shown in error bubble")
        static let errorFallback = NSLocalizedString("voiceMessage.errorFallback", comment: "Fallback text for unknown errors")
        static let retry = NSLocalizedString("voiceMessage.retry", comment: "Retry button title")
        static let thinkingFinished = NSLocalizedString("voiceMessage.thinkingFinished", comment: "Label for completed thinking state")
        static let thinkingInProgress = NSLocalizedString("voiceMessage.thinkingInProgress", comment: "Label for thinking in progress")
        static let collapse = NSLocalizedString("voiceMessage.collapse", comment: "Collapse action title")
        static let showFull = NSLocalizedString("voiceMessage.showFull", comment: "Action title to show full message")
        static let readAloud = NSLocalizedString("voiceMessage.readAloud", comment: "Read aloud accessibility label")
        static let regenerate = NSLocalizedString("voiceMessage.regenerate", comment: "Regenerate accessibility label")
    }

    enum VoiceOverlay {
        static let errorTitle = NSLocalizedString("voiceOverlay.errorTitle", comment: "Alert title for voice overlay errors")
        static let errorUnknown = NSLocalizedString("voiceOverlay.errorUnknown", comment: "Fallback error message when speech input fails")
    }

    enum Speech {
        static let languageChinese = NSLocalizedString("speech.language.chinese", comment: "Display name for Simplified Chinese dictation")
        static let languageEnglish = NSLocalizedString("speech.language.english", comment: "Display name for English dictation")
        static let permissionsDenied = NSLocalizedString("speech.error.permissionsDenied", comment: "Error shown when microphone or speech permissions are missing")
        static let unsupportedPlatform = NSLocalizedString("speech.error.unsupportedPlatform", comment: "Error shown when speech input is not supported on the current platform")
        static let recognizerUnavailable = NSLocalizedString("speech.error.recognizerUnavailable", comment: "Error shown when the speech recognizer is unavailable")
        static func engineStartFailed(_ message: String) -> String {
            let format = NSLocalizedString("speech.error.engineStartFailed", comment: "Template for audio engine start failure messages")
            return String(format: format, message)
        }
    }

    enum Alerts {
        static let deleteChatTitle = NSLocalizedString("alerts.deleteChatTitle", comment: "Title for delete chat confirmation")
        static let deletePresetTitle = NSLocalizedString("alerts.deletePresetTitle", comment: "Title for delete preset confirmation")
    }

    enum Accessibility {
        static let copy = NSLocalizedString("accessibility.copy", comment: "Accessibility label for copy button")
        static let regenerate = NSLocalizedString("accessibility.regenerate", comment: "Accessibility label for regenerate button")
        static let readAloud = NSLocalizedString("accessibility.readAloud", comment: "Accessibility label for read aloud button")
        static let thinkingPreview = NSLocalizedString("accessibility.thinkingPreview", comment: "Accessibility label for the thinking preview")
    }

    enum Audio {
        static let loading = NSLocalizedString("audio.loading", comment: "Label shown while audio data is loading")
        static let buffering = NSLocalizedString("audio.buffering", comment: "Label shown while audio buffers")
        static let errorConstructURL = NSLocalizedString("audio.errorConstructURL", comment: "Error shown when the TTS URL cannot be built")
        static let errorSerializeJSON = NSLocalizedString("audio.errorSerializeJSON", comment: "Error shown when the TTS request body cannot be serialized")
        static func errorNetwork(_ message: String) -> String {
            let format = NSLocalizedString("audio.errorNetwork", comment: "Template for network errors while requesting audio")
            return String(format: format, message)
        }
        static func errorServer(_ code: Int) -> String {
            let format = NSLocalizedString("audio.errorServer", comment: "Template for HTTP errors returned by the TTS server")
            return String(format: format, code)
        }
        static let errorNoData = NSLocalizedString("audio.errorNoData", comment: "Error shown when the TTS server returns no data")
        static func errorPlaybackFailed(_ message: String) -> String {
            let format = NSLocalizedString("audio.errorPlaybackFailed", comment: "Template for audio playback failures")
            return String(format: format, message)
        }
        static func errorSessionSetup(_ message: String) -> String {
            let format = NSLocalizedString("audio.errorSessionSetup", comment: "Template for audio session setup failures")
            return String(format: format, message)
        }
    }

    enum Voice {
        static let sampleText = NSLocalizedString("voice.sampleText", comment: "Sample text shown in the voice view")
        static let waitingForConnection = NSLocalizedString("voice.waitingForConnection", comment: "Status text while waiting for a voice connection")
    }
}
