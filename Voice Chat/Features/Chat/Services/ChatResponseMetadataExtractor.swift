//
//  ChatResponseMetadataExtractor.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

protocol ChatResponseMetadataExtracting: Sendable {
    func normalizedTokenCount(_ value: Double?) -> Int?
    func extractResponseMetadata(from dictionary: [String: Any], style: ChatRequestStyle) -> ChatResponseMetadata
}

struct ChatResponseMetadataExtractor: ChatResponseMetadataExtracting, Sendable {
    func normalizedTokenCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    func extractResponseMetadata(from dictionary: [String: Any], style: ChatRequestStyle) -> ChatResponseMetadata {
        switch style {
        case .openAIResponses, .openAIChatCompletions:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if metadata.providerResponseID == nil,
               let responseID = dictionary["response_id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let output = usage["completion_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if metadata.outputTokenCount == nil,
                   let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let details = usage["completion_tokens_details"] as? [String: Any],
                   let reasoning = details["reasoning_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
                if metadata.reasoningOutputTokenCount == nil,
                   let details = usage["output_tokens_details"] as? [String: Any],
                   let reasoning = details["reasoning_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
            }
            if let timings = dictionary["timings"] as? [String: Any] {
                if metadata.outputTokenCount == nil,
                   let predictedN = timings["predicted_n"] as? NSNumber {
                    metadata.outputTokenCount = predictedN.intValue
                }
                if metadata.tokensPerSecond == nil,
                   let predictedPerSecond = timings["predicted_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = predictedPerSecond.doubleValue
                }
                if metadata.timeToFirstTokenSeconds == nil,
                   let ttf = timings["time_to_first_token_seconds"] as? NSNumber {
                    metadata.timeToFirstTokenSeconds = ttf.doubleValue
                }
            }
            if let choices = dictionary["choices"] as? [[String: Any]],
               let first = choices.first,
               let finish = first["finish_reason"] as? String,
               !finish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finish
            }

            if let response = dictionary["response"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = response["id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let usage = response["usage"] as? [String: Any] {
                    if metadata.outputTokenCount == nil {
                        if let output = usage["completion_tokens"] as? NSNumber {
                            metadata.outputTokenCount = output.intValue
                        } else if let output = usage["output_tokens"] as? NSNumber {
                            metadata.outputTokenCount = output.intValue
                        }
                    }
                    if metadata.reasoningOutputTokenCount == nil {
                        if let details = usage["completion_tokens_details"] as? [String: Any],
                           let reasoning = details["reasoning_tokens"] as? NSNumber {
                            metadata.reasoningOutputTokenCount = reasoning.intValue
                        } else if let details = usage["output_tokens_details"] as? [String: Any],
                                  let reasoning = details["reasoning_tokens"] as? NSNumber {
                            metadata.reasoningOutputTokenCount = reasoning.intValue
                        }
                    }
                }
                if metadata.finishReason == nil,
                   let status = response["status"] as? String,
                   !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.finishReason = status
                }
            }
            return metadata

        case .anthropicMessages:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            } else if let message = dictionary["message"] as? [String: Any],
                      let responseID = message["id"] as? String,
                      !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                metadata.reasoningOutputTokenCount = anthropicThinkingTokens(from: usage)
            } else if let message = dictionary["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] {
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                metadata.reasoningOutputTokenCount = anthropicThinkingTokens(from: usage)
            }
            if let stopReason = dictionary["stop_reason"] as? String,
               !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            } else if let message = dictionary["message"] as? [String: Any],
                      let stopReason = message["stop_reason"] as? String,
                      !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            }
            return metadata

        case .lmStudioRESTV1:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["response_id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }

            if let stats = dictionary["stats"] as? [String: Any] {
                if let output = stats["total_output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
                if let tps = stats["tokens_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = tps.doubleValue
                }
                if let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                    metadata.timeToFirstTokenSeconds = ttf.doubleValue
                }
            }

            if let result = dictionary["result"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = result["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = result["stats"] as? [String: Any] {
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }

            if let response = dictionary["response"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = response["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = response["stats"] as? [String: Any] {
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }
            return metadata
        }
    }

    private func anthropicThinkingTokens(from usage: [String: Any]) -> Int? {
        guard let details = usage["output_tokens_details"] as? [String: Any] else { return nil }
        if let thinking = details["thinking_tokens"] as? NSNumber {
            return thinking.intValue
        }
        if let reasoning = details["reasoning_tokens"] as? NSNumber {
            return reasoning.intValue
        }
        return nil
    }
}
