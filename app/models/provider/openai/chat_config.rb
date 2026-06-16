class Provider::Openai::ChatConfig
  def initialize(functions: [])
    @functions = functions
  end

  # Chat Completions tool format: the function definition is nested under "function".
  def tools
    functions.map do |fn|
      {
        type: "function",
        function: {
          name: fn[:name],
          description: fn[:description],
          parameters: fn[:params_schema],
          strict: fn[:strict]
        }.compact
      }
    end
  end

  # Builds the full (stateless) Chat Completions messages array:
  #   system (instructions) -> prior history -> current user prompt
  #   -> one [assistant tool_calls + tool outputs] block per completed tool round
  #
  # tool_rounds is an ordered array of { requests: [ChatFunctionRequest], results: [{call_id:, output:}] }
  def build_messages(prompt:, instructions: nil, message_history: [], tool_rounds: [])
    messages = []

    messages << { role: "system", content: instructions } if instructions.present?

    Array(message_history).each do |msg|
      messages << { role: msg[:role], content: msg[:content] }
    end

    messages << { role: "user", content: prompt }

    Array(tool_rounds).each do |round|
      messages << {
        role: "assistant",
        content: nil,
        tool_calls: round[:requests].map do |fn_req|
          {
            id: fn_req.call_id,
            type: "function",
            function: {
              name: fn_req.function_name,
              arguments: fn_req.function_args.to_s
            }
          }
        end
      }

      round[:results].each do |fn_result|
        messages << {
          role: "tool",
          tool_call_id: fn_result[:call_id],
          content: fn_result[:output].to_json
        }
      end
    end

    messages
  end

  private
    attr_reader :functions
end
