require "test_helper"

class Transactions::AutoCategorizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "schedules auto-categorization for uncategorized transactions" do
    Provider::Registry.stubs(:get_provider).with(:openai).returns(Object.new)
    Family.any_instance.expects(:auto_categorize_uncategorized_transactions_later).returns(3)

    post transactions_auto_categorization_url

    assert_redirected_to transactions_url
    assert_match(/Auto-categorizing 3/, flash[:notice])
  end

  test "shows alert when no AI provider is configured" do
    Provider::Registry.stubs(:get_provider).with(:openai).returns(nil)
    Family.any_instance.expects(:auto_categorize_uncategorized_transactions_later).never

    post transactions_auto_categorization_url

    assert_redirected_to transactions_url
    assert flash[:alert].present?
  end
end
