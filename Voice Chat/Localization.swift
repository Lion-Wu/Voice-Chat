//
//  Localization.swift
//  Voice Chat
//
//  Created by OpenAI Assistant on 2024/05/25.
//

import SwiftUI

/// Centralized localization keys used across the application.
///
/// Every user-facing string should reference one of these keys to make it
/// straightforward to keep translations in sync across platforms.
enum L10n {
    /// Returns the localized string for the provided key.
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    enum Common {
        static let ok: LocalizedStringKey = "common_ok"
        static let cancel: LocalizedStringKey = "common_cancel"
        static let delete: LocalizedStringKey = "common_delete"
        static let close: LocalizedStringKey = "common_close"
        static let done: LocalizedStringKey = "common_done"
        static let save: LocalizedStringKey = "common_save"
        static let add: LocalizedStringKey = "common_add"
        static let error: LocalizedStringKey = "common_error"
        static let loading: LocalizedStringKey = "common_loading"
        static let refresh: LocalizedStringKey = "common_refresh"
        static let applyNow: LocalizedStringKey = "common_apply_now"
        static let stop: LocalizedStringKey = "common_stop"
        static let send: LocalizedStringKey = "common_send"
        static let voiceInputStart: LocalizedStringKey = "common_voice_input_start"
        static let voiceInputStop: LocalizedStringKey = "common_voice_input_stop"
        static let realtimeVoice: LocalizedStringKey = "common_realtime_voice"
        static let fullScreenEdit: LocalizedStringKey = "common_full_screen_edit"
        static let fullScreenEditorTitle: LocalizedStringKey = "common_full_screen_editor_title"
        static let newChat: LocalizedStringKey = "common_new_chat"
        static let helpNewChat: LocalizedStringKey = "common_help_new_chat"
        static let irreversibleActionMessage: LocalizedStringKey = "common_irreversible_action_message"
        static let unknownError: LocalizedStringKey = "common_unknown_error"
        static let copy: LocalizedStringKey = "common_copy"
        static let selectText: LocalizedStringKey = "common_select_text"
        static let edit: LocalizedStringKey = "common_edit"
        static let retry: LocalizedStringKey = "common_retry"
        static let readAloud: LocalizedStringKey = "common_read_aloud"
        static let showMore: LocalizedStringKey = "common_show_more"
        static let showLess: LocalizedStringKey = "common_show_less"
        static let accessibilityCopy: LocalizedStringKey = "common_accessibility_copy"
        static let accessibilityRegenerate: LocalizedStringKey = "common_accessibility_regenerate"
        static let accessibilityReadAloud: LocalizedStringKey = "common_accessibility_read_aloud"
        static let accessibilityPlaceholderHint: LocalizedStringKey = "common_accessibility_placeholder_hint"
        static let connectionTimeout: LocalizedStringKey = "common_connection_timeout"

        static var connectionTimeoutText: String { L10n.string("common_connection_timeout") }
    }

    enum Content {
        static let noChatSelected: LocalizedStringKey = "content_no_chat_selected"
        static let creatingChat: LocalizedStringKey = "content_creating_chat"
    }

    enum Sidebar {
        static let chatsHeader: LocalizedStringKey = "sidebar_chats_header"
        static let settings: LocalizedStringKey = "sidebar_settings"
        static let rename: LocalizedStringKey = "sidebar_rename"
        static let delete: LocalizedStringKey = "sidebar_delete"
        static let deleteChatTitle: LocalizedStringKey = "sidebar_delete_chat_title"
        static let renameChatTitle: LocalizedStringKey = "sidebar_rename_chat_title"
        static let newTitlePlaceholder: LocalizedStringKey = "sidebar_new_title_placeholder"
    }

    enum Settings {
        static let navigationTitle: LocalizedStringKey = "settings_navigation_title"
        static let voiceServerSection: LocalizedStringKey = "settings_voice_server_section"
        static let serverAddress: LocalizedStringKey = "settings_server_address"
        static let serverAddressPlaceholder: LocalizedStringKey = "settings_server_address_placeholder"
        static let textLanguage: LocalizedStringKey = "settings_text_language"
        static let textLanguagePlaceholder: LocalizedStringKey = "settings_text_language_placeholder"
        static let modelPresetSection: LocalizedStringKey = "settings_model_preset_section"
        static let currentPreset: LocalizedStringKey = "settings_current_preset"
        static let addPreset: LocalizedStringKey = "settings_add_preset"
        static let deletePreset: LocalizedStringKey = "settings_delete_preset"
        static let deletePresetTitle: LocalizedStringKey = "settings_delete_preset_title"
        static let deletePresetMessage: LocalizedStringKey = "settings_delete_preset_message"
        static let applyingPreset: LocalizedStringKey = "settings_applying_preset"
        static let presetName: LocalizedStringKey = "settings_preset_name"
        static let refAudioPath: LocalizedStringKey = "settings_ref_audio_path"
        static let refAudioPlaceholder: LocalizedStringKey = "settings_ref_audio_placeholder"
        static let promptText: LocalizedStringKey = "settings_prompt_text"
        static let promptTextPlaceholder: LocalizedStringKey = "settings_prompt_text_placeholder"
        static let promptLanguage: LocalizedStringKey = "settings_prompt_language"
        static let gptWeightsPath: LocalizedStringKey = "settings_gpt_weights_path"
        static let sovitsWeightsPath: LocalizedStringKey = "settings_sovits_weights_path"
        static let applyPresetNow: LocalizedStringKey = "settings_apply_preset_now"
        static let voiceOutputSection: LocalizedStringKey = "settings_voice_output_section"
        static let enableStreaming: LocalizedStringKey = "settings_enable_streaming"
        static let autoReadAfterGeneration: LocalizedStringKey = "settings_auto_read_after_generation"
        static let splitMethod: LocalizedStringKey = "settings_split_method"
        static let chatServerSection: LocalizedStringKey = "settings_chat_server_section"
        static let chatApiUrl: LocalizedStringKey = "settings_chat_api_url"
        static let selectModel: LocalizedStringKey = "settings_select_model"
        static let refreshModelList: LocalizedStringKey = "settings_refresh_model_list"
        static let loadingModels: LocalizedStringKey = "settings_loading_models"
        static let apiUrlEmptyError: LocalizedStringKey = "settings_api_url_empty_error"
        static let invalidApiUrlError: LocalizedStringKey = "settings_invalid_api_url_error"
        static let requestFailedError: LocalizedStringKey = "settings_request_failed_error"
        static let failedToParseModelsError: LocalizedStringKey = "settings_failed_to_parse_models_error"
        static let generalTab: LocalizedStringKey = "settings_general_tab"
        static let presetsTab: LocalizedStringKey = "settings_presets_tab"
        static let voiceTab: LocalizedStringKey = "settings_voice_tab"
        static let chatTab: LocalizedStringKey = "settings_chat_tab"

        static var apiUrlEmptyErrorText: String { L10n.string("settings_api_url_empty_error") }
        static var invalidApiUrlErrorText: String { L10n.string("settings_invalid_api_url_error") }
        static var requestFailedErrorText: String { L10n.string("settings_request_failed_error") }
        static var failedToParseModelsErrorText: String { L10n.string("settings_failed_to_parse_models_error") }
        static var loadingModelsText: String { L10n.string("settings_loading_models") }
    }

    enum Chat {
        static let editing: LocalizedStringKey = "chat_editing"
        static let cancelEditingHelp: LocalizedStringKey = "chat_cancel_editing_help"
        static let inputPlaceholder: LocalizedStringKey = "chat_input_placeholder"
        static let fullScreenEditAccessibility: LocalizedStringKey = "chat_full_screen_edit_accessibility"
    }

    enum Overlay {
        static let voiceErrorTitle: LocalizedStringKey = "overlay_voice_error_title"
        static let voiceErrorFallback: LocalizedStringKey = "overlay_voice_error_fallback"
    }

    enum VoiceMessage {
        static let errorTitle: LocalizedStringKey = "voice_message_error_title"
        static let thinking: LocalizedStringKey = "voice_message_thinking"
        static let thinkingFinished: LocalizedStringKey = "voice_message_thinking_finished"
    }

    enum TailLinesText {
        static let accessibilityPreview: LocalizedStringKey = "tail_lines_preview_accessibility"
    }

    enum AudioPlayer {
        static let buffering: LocalizedStringKey = "audio_buffering"
    }

    enum Dictation {
        static let chinese: LocalizedStringKey = "dictation_language_chinese"
        static let english: LocalizedStringKey = "dictation_language_english"
    }

    enum SpeechInput {
        static let permissionsMissing: LocalizedStringKey = "speech_input_permissions_missing"
        static var permissionsMissingText: String { L10n.string("speech_input_permissions_missing") }
        static var unsupportedPlatformText: String { L10n.string("speech_input_unsupported_platform") }
        static var recognizerUnavailableText: String { L10n.string("speech_input_recognizer_unavailable") }
        static func engineStartFailed(_ message: String) -> String {
            String(format: L10n.string("speech_input_engine_start_failed_fmt"), message)
        }
    }
}
