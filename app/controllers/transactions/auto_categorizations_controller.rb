class Transactions::AutoCategorizationsController < ApplicationController
  def create
    unless Provider::Registry.get_provider(:openai)
      redirect_back_or_to transactions_path, alert: "AI categorization isn't available — no AI provider is configured."
      return
    end

    count = Current.family.auto_categorize_uncategorized_transactions_later

    notice = if count.zero?
      "No uncategorized transactions to categorize."
    else
      "Auto-categorizing #{count} #{"transaction".pluralize(count)} with AI. This may take a moment to complete."
    end

    redirect_back_or_to transactions_path, notice: notice
  end
end
