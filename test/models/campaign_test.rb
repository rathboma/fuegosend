require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(
      name: "Test Account",
      plan: "free",
      subdomain: "test#{rand(100000)}"
    )
    @list = List.create!(account: @account, name: "Test List")
  end

  test "recipients excludes suppressed subscribers" do
    # Create campaign with list
    campaign = Campaign.create!(
      account: @account,
      list: @list,
      name: "Test Campaign",
      subject: "Test",
      from_name: "Test",
      from_email: "test@example.com",
      body_markdown: "Test body",
      status: "draft"
    )

    # Add active subscriber
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    # Add bounced subscriber
    bounced = Subscriber.create!(
      account: @account,
      email: "bounced@example.com",
      status: "bounced"
    )
    @list.add_subscriber(bounced)

    # Add complained subscriber
    complained = Subscriber.create!(
      account: @account,
      email: "complained@example.com",
      status: "complained"
    )
    @list.add_subscriber(complained)

    # Verify only active is in recipients
    recipients = campaign.recipients.to_a
    assert_includes recipients, active
    refute_includes recipients, bounced
    refute_includes recipients, complained
    assert_equal 1, recipients.count
  end

  test "recipients excludes subscribers who were marked bounced after being added to list" do
    # Create campaign with list
    campaign = Campaign.create!(
      account: @account,
      list: @list,
      name: "Test Campaign",
      subject: "Test",
      from_name: "Test",
      from_email: "test@example.com",
      body_markdown: "Test body",
      status: "draft"
    )

    # Add active subscriber
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    # Add another active subscriber
    to_be_bounced = Subscriber.create!(
      account: @account,
      email: "future-bounced@example.com",
      status: "active"
    )
    @list.add_subscriber(to_be_bounced)

    # Now mark second subscriber as bounced (simulating webhook processing)
    to_be_bounced.mark_bounced!

    # Verify only the still-active subscriber is in recipients
    recipients = campaign.recipients.to_a
    assert_includes recipients, active
    refute_includes recipients, to_be_bounced
    assert_equal 1, recipients.count
  end
end
