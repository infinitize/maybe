class Assistant::Function::CreateTransactions < Assistant::Function
  class << self
    def name
      "create_transactions"
    end

    def description
      <<~INSTRUCTIONS
        Create one or more transactions in the user's account(s). Use this when the user
        pastes or describes transactions they want added to their books.

        Rules:
        - Pass ALL transactions in a single call via the `transactions` array (do not call
          this function once per transaction).
        - `amount` must be a POSITIVE number. Use `nature` to indicate direction:
          - "outflow" = money spent / an expense (e.g. a purchase, a bill)
          - "inflow"  = money received / income (e.g. salary, a refund)
        - `account` must be one of the user's existing accounts (see the allowed values).
          If the user does not specify an account and only one exists, it will be used.
        - `category` is optional and must match an existing category name, otherwise the
          transaction is left uncategorized.
        - Dates must be in YYYY-MM-DD format.

        After creating, briefly confirm how many were added (and report any that failed).
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "transactions" ],
      properties: {
        transactions: {
          type: "array",
          description: "The list of transactions to create",
          minItems: 1,
          items: {
            type: "object",
            properties: {
              date: {
                type: "string",
                description: "Transaction date in YYYY-MM-DD format"
              },
              name: {
                type: "string",
                description: "A short description / merchant name for the transaction"
              },
              amount: {
                type: "number",
                description: "The transaction amount as a positive number (direction is set by `nature`)"
              },
              nature: {
                type: "string",
                description: "Whether money left the account (expense) or came in (income)",
                enum: [ "outflow", "inflow" ]
              },
              account: {
                type: "string",
                description: "The account to add the transaction to",
                enum: family_account_names
              },
              category: {
                type: "string",
                description: "Optional category name for the transaction",
                enum: family_category_names
              },
              notes: {
                type: "string",
                description: "Optional free-form notes"
              }
            },
            required: [ "date", "name", "amount", "nature" ]
          }
        }
      }
    )
  end

  def call(params = {})
    rows = params["transactions"] || []
    return { error: "No transactions provided" } if rows.empty?

    Transaction::BulkCreator.new(family, rows).create
  end
end
