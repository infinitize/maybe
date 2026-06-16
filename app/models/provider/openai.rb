class Provider::Openai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Openai::Error
  Error = Class.new(Provider::Error)

  # Models are configurable so the provider can target any OpenAI-compatible
  # endpoint (e.g. Alibaba DashScope / Qwen). Comma-separate to allow multiple.
  MODELS = ENV.fetch("OPENAI_CHAT_MODEL", "gpt-4.1").split(",").map(&:strip)

  def initialize(access_token)
    options = {
      access_token: access_token,
      # ruby-openai defaults to 120s. Large, non-streamed tool-call responses
      # (e.g. creating many transactions at once) can take longer, so make it
      # configurable and default higher to avoid Net::ReadTimeout.
      request_timeout: ENV.fetch("OPENAI_REQUEST_TIMEOUT", "600").to_i
    }

    # Point at an OpenAI-compatible base URL when configured (DashScope, etc.).
    # When blank, ruby-openai defaults to https://api.openai.com/v1.
    uri_base = ENV["OPENAI_URI_BASE"].presence
    options[:uri_base] = uri_base if uri_base

    @client = ::OpenAI::Client.new(**options)
  end

  def supports_model?(model)
    MODELS.include?(model)
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(
        client,
        transactions: transactions,
        user_categories: user_categories
      ).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants
    end
  end

  # Uses the OpenAI-compatible Chat Completions API (/chat/completions) rather than
  # the OpenAI-proprietary Responses API (/responses), so this works against any
  # OpenAI-compatible endpoint such as Alibaba DashScope / Qwen.
  #
  # Because Chat Completions is stateless, the full conversation is rebuilt on every
  # call from +message_history+ (instead of relying on +previous_response_id+).
  def chat_response(prompt, model:, instructions: nil, functions: [], tool_rounds: [], message_history: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      chat_config = ChatConfig.new(functions: functions)

      parameters = {
        model: model,
        messages: chat_config.build_messages(
          prompt: prompt,
          instructions: instructions,
          message_history: message_history,
          tool_rounds: tool_rounds
        )
      }

      tools = chat_config.tools
      parameters[:tools] = tools if tools.any?

      raw_response = client.chat(parameters: parameters)

      ChatParser.new(raw_response).parsed
    end
  end

  private
    attr_reader :client
end
