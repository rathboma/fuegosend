require "test_helper"

class ListTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(
      name: "Test Account",
      plan: "free",
      subdomain: "test#{rand(100000)}"
    )
    @list = List.create!(account: @account, name: "Test List")
  end

  test "active_subscribers only includes active subscribers" do
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    assert_equal 1, @list.active_subscribers.count
    assert_includes @list.active_subscribers, active
  end

  test "active_subscribers excludes bounced subscribers" do
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    bounced = Subscriber.create!(
      account: @account,
      email: "bounced@example.com",
      status: "bounced"
    )
    @list.add_subscriber(bounced)

    assert_equal 1, @list.active_subscribers.count
    assert_includes @list.active_subscribers, active
    refute_includes @list.active_subscribers, bounced
  end

  test "active_subscribers excludes complained subscribers" do
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    complained = Subscriber.create!(
      account: @account,
      email: "complained@example.com",
      status: "complained"
    )
    @list.add_subscriber(complained)

    assert_equal 1, @list.active_subscribers.count
    assert_includes @list.active_subscribers, active
    refute_includes @list.active_subscribers, complained
  end

  test "active_subscribers excludes unsubscribed subscribers" do
    active = Subscriber.create!(
      account: @account,
      email: "active@example.com",
      status: "active"
    )
    @list.add_subscriber(active)

    unsubscribed = Subscriber.create!(
      account: @account,
      email: "unsubscribed@example.com",
      status: "active"
    )
    @list.add_subscriber(unsubscribed)
    @list.remove_subscriber(unsubscribed)

    assert_equal 1, @list.active_subscribers.count
    assert_includes @list.active_subscribers, active
    refute_includes @list.active_subscribers, unsubscribed
  end

  test "active_subscribers respects list_subscription status" do
    subscriber = Subscriber.create!(
      account: @account,
      email: "test@example.com",
      status: "active"
    )

    # Add to list then remove (sets list_subscription to unsubscribed)
    @list.add_subscriber(subscriber)
    @list.remove_subscriber(subscriber)

    assert_equal 0, @list.active_subscribers.count
    refute_includes @list.active_subscribers, subscriber
  end

  test "active_subscribers excludes subscriber that is bounced but has active list_subscription" do
    # This is an edge case where data might be inconsistent
    subscriber = Subscriber.create!(
      account: @account,
      email: "edge-case@example.com",
      status: "active"
    )
    @list.add_subscriber(subscriber)

    # Mark as bounced directly (bypassing the normal flow)
    subscriber.mark_bounced!

    # Verify exclusion even if list_subscription is still active
    assert_equal 0, @list.active_subscribers.count
    refute_includes @list.active_subscribers, subscriber
  end
end
