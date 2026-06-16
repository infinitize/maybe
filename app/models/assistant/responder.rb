class Assistant::Responder
  def initialize(message:, instructions:, function_tool_caller:, llm:)
    @message = message
    @instructions = instructions
    @function_tool_caller = function_tool_caller
    @llm = llm
  end

  def on(event_name, &block)
    listeners[event_name.to_sym] << block
  end

  # Asks the model, executes any tools it requests EXACTLY ONCE, then makes a final
  # call with tools disabled so the model summarizes the results as text.
  #
  # Tools are executed in a single round on purpose: it guarantees write tools (e.g.
  # create_transactions) run at most once per user message — some models will re-issue
  # the same tool call after seeing its result, which for a write would duplicate data.
  def respond(previous_response_id: nil)
    response = get_llm_response(tool_rounds: [])
    emit_text(response)

    if response.function_requests.empty?
      emit(:response, { id: response.id })
      return
    end

    tool_calls = function_tool_caller.fulfill_requests(response.function_requests)
    emit(:response, { id: response.id, function_tool_calls: tool_calls })

    tool_rounds = [ { requests: response.function_requests, results: tool_calls.map(&:to_result) } ]

    # Final call with tools disabled -> the model must answer with text rather than
    # request (and thus re-run) more tools.
    final = get_llm_response(tool_rounds: tool_rounds, allow_tools: false)
    emit_text(final)
    emit(:response, { id: final.id })
  end

  private
    attr_reader :message, :instructions, :function_tool_caller, :llm

    def emit_text(response)
      response.messages.each do |msg|
        emit(:output_text, msg.output_text) if msg.output_text.present?
      end
    end

    def get_llm_response(tool_rounds:, allow_tools: true)
      response = llm.chat_response(
        message.content,
        model: message.ai_model,
        instructions: instructions,
        functions: allow_tools ? function_tool_caller.function_definitions : [],
        tool_rounds: tool_rounds,
        message_history: message_history
      )

      raise response.error unless response.success?

      response.data
    end

    # Chat Completions is stateless, so the prior conversation is rebuilt and sent
    # on every call. Excludes the current user message and any blank (in-progress)
    # assistant message.
    def message_history
      message.chat.conversation_messages
             .where.not(id: message.id)
             .ordered
             .filter_map do |msg|
               next if msg.content.blank?
               { role: msg.role, content: msg.content }
             end
    end

    def emit(event_name, payload = nil)
      listeners[event_name.to_sym].each { |block| block.call(payload) }
    end

    def listeners
      @listeners ||= Hash.new { |h, k| h[k] = [] }
    end
end
