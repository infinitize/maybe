class Provider::Openai::ChatParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = object
  end

  def parsed
    ChatResponse.new(
      id: response_id,
      model: response_model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :object

    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    # Chat Completions returns a single choice with a message object.
    def choice_message
      object.dig("choices", 0, "message") || {}
    end

    def response_id
      object.dig("id")
    end

    def response_model
      object.dig("model")
    end

    def messages
      text = choice_message["content"]
      refusal = choice_message["refusal"]
      output = text || refusal

      return [] if output.blank?

      [
        ChatMessage.new(
          id: response_id,
          output_text: output
        )
      ]
    end

    def function_requests
      tool_calls = choice_message["tool_calls"] || []

      tool_calls.map do |tool_call|
        ChatFunctionRequest.new(
          id: tool_call.dig("id"),
          call_id: tool_call.dig("id"),
          function_name: tool_call.dig("function", "name"),
          function_args: tool_call.dig("function", "arguments")
        )
      end
    end
end
