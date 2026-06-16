# Shared logic for creating many transactions at once from simple row hashes.
# Used by both the AI assistant (Assistant::Function::CreateTransactions) and the
# `bin/maybe` CLI so the two stay in sync.
#
# Each row (string or symbol keys):
#   account  - account name (optional if the family has exactly one account)
#   date     - "YYYY-MM-DD"
#   name     - description / merchant
#   amount   - number; see `nature` for sign handling
#   nature   - "outflow" (expense) | "inflow" (income).
#              If omitted, the SIGN of `amount` is used: negative => expense,
#              positive => income (matches how people paste bank statements).
#   category - optional, matched to an existing category by name
#   notes    - optional
class Transaction::BulkCreator
  def initialize(family, rows)
    @family = family
    @rows = Array(rows)
  end

  def create
    created = []
    errors = []
    touched_accounts = {}

    @rows.each_with_index do |raw, index|
      row = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
      account = resolve_account(row[:account])

      unless account
        errors << { index: index, name: row[:name], error: account_error_message(row[:account]) }
        next
      end

      entry = account.entries.new(
        name: row[:name],
        date: row[:date],
        amount: internal_amount(row),
        currency: account.currency,
        notes: row[:notes],
        entryable: Transaction.new(category_id: resolve_category_id(row[:category]))
      )

      if entry.save
        entry.lock_saved_attributes!
        touched_accounts[account.id] = account
        created << {
          account: account.name,
          date: entry.date.to_s,
          name: entry.name,
          amount: entry.amount_money.abs.format,
          classification: entry.classification,
          category: entry.transaction.category&.name
        }
      else
        errors << { index: index, name: row[:name], error: entry.errors.full_messages.join(", ") }
      end
    end

    # Recalculate balances once per affected account.
    touched_accounts.each_value(&:sync_later)

    {
      created_count: created.length,
      failed_count: errors.length,
      created: created,
      errors: errors
    }
  end

  private
    attr_reader :family

    # Maybe stores expenses as POSITIVE and income as NEGATIVE amounts.
    def internal_amount(row)
      amount = row[:amount].to_d

      if row[:nature].present?
        row[:nature].to_s == "inflow" ? -amount.abs : amount.abs
      else
        # Infer from the sign the caller provided: a negative number (e.g. -300 on a
        # statement) is an expense, a positive number is income.
        -amount
      end
    end

    def resolve_account(name)
      if name.present?
        family.accounts.find_by("LOWER(name) = ?", name.to_s.downcase)
      elsif family.accounts.visible.count == 1
        family.accounts.visible.first
      end
    end

    def account_error_message(name)
      if name.present?
        "Account '#{name}' not found"
      else
        "No account specified and the family has more than one account"
      end
    end

    def resolve_category_id(name)
      return nil if name.blank? || name == "Uncategorized"

      family.categories.find_by("LOWER(name) = ?", name.to_s.downcase)&.id
    end
end
