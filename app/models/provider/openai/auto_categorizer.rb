class Provider::Openai::AutoCategorizer
  def initialize(client, transactions: [], user_categories: [], model: nil)
    @client = client
    @transactions = transactions
    @user_categories = user_categories
    # Default to the first configured model so this works against any
    # OpenAI-compatible endpoint (e.g. Alibaba DashScope / Qwen).
    @model = model || Provider::Openai::MODELS.first
  end

  # Uses the OpenAI-compatible Chat Completions API (/chat/completions) rather than
  # the OpenAI-proprietary Responses API (/responses), so this works against any
  # OpenAI-compatible endpoint such as Alibaba DashScope / Qwen.
  def auto_categorize
    response = client.chat(parameters: {
      model: model,
      messages: [
        { role: "system", content: instructions },
        { role: "user", content: developer_message }
      ],
      response_format: { type: "json_object" }
    })

    Rails.logger.info("Tokens used to auto-categorize transactions: #{response.dig("usage", "total_tokens")}")

    build_response(extract_categorizations(response))
  end

  private
    attr_reader :client, :transactions, :user_categories, :model

    AutoCategorization = Provider::LlmConcept::AutoCategorization

    def build_response(categorizations)
      categorizations.map do |categorization|
        AutoCategorization.new(
          transaction_id: categorization["transaction_id"],
          category_name: normalize_category_name(categorization["category_name"]),
        )
      end
    end

    def normalize_category_name(category_name)
      return nil if category_name.nil? || category_name == "null"

      category_name
    end

    def extract_categorizations(response)
      content = response.dig("choices", 0, "message", "content")
      return [] if content.blank?

      Array(JSON.parse(content)["categorizations"])
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse auto-categorization response: #{e.message}")
      []
    end

    def developer_message
      <<~MESSAGE
        Here are the user's available categories in JSON format:

        ```json
        #{user_categories.to_json}
        ```

        Use the available categories to auto-categorize the following transactions:

        ```json
        #{transactions.to_json}
        ```
      MESSAGE
    end

    def instructions
      <<~INSTRUCTIONS
        You are an assistant to a consumer personal finance app. You will be provided a list
        of the user's transactions and a list of the user's categories. Your job is to auto-categorize
        each transaction.

        Closely follow ALL the rules below while auto-categorizing:

        - Return 1 result per transaction
        - Correlate each transaction by ID (transaction_id)
        - Each category_name MUST be EXACTLY one of the user's category names listed above, or the string "null"
        - Attempt to match the most specific category possible (i.e. subcategory over parent category)
        - Category and transaction classifications should match (i.e. if transaction is an "expense", the category must have classification of "expense")
        - If you don't know the category, return "null"
          - You should always favor "null" over false positives
          - Be slightly pessimistic. Only match a category if you're 60%+ confident it is the correct one.

        Respond with ONLY a valid JSON object in exactly this shape (no markdown fences, no commentary):

        {
          "categorizations": [
            { "transaction_id": "<the transaction id>", "category_name": "<a category name, or null>" }
          ]
        }
      INSTRUCTIONS
    end
end
