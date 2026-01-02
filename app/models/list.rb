class List < ApplicationRecord
  belongs_to :account
  has_many :list_subscriptions, dependent: :destroy
  has_many :subscribers, through: :list_subscriptions
  has_many :segments, dependent: :destroy
  has_many :campaigns, dependent: :destroy

  validates :name, presence: true
  validate :account_can_create_list, on: :create

  # Get active subscribers
  def active_subscribers
    subscribers.where(status: "active")
      .joins(:list_subscriptions)
      .where(list_subscriptions: { status: "active", list_id: id })
  end

  # Update subscriber count
  def refresh_subscribers_count!
    update_column(:subscribers_count, active_subscribers.count)
  end

  # Add a subscriber to this list
  def add_subscriber(subscriber, subscribed_at: Time.current)
    list_subscriptions.find_or_create_by!(subscriber: subscriber) do |subscription|
      subscription.status = "active"
      subscription.subscribed_at = subscribed_at
    end
    refresh_subscribers_count!
  end

  # Remove a subscriber from this list
  def remove_subscriber(subscriber)
    subscription = list_subscriptions.find_by(subscriber: subscriber)
    return unless subscription

    subscription.update!(
      status: "unsubscribed",
      unsubscribed_at: Time.current
    )
    refresh_subscribers_count!
  end

  private

  # Validate that account can create another list (Free plan limited to 1)
  def account_can_create_list
    unless account.can_create_list?
      errors.add(:base, "Your plan allows only #{account.max_lists} list. Upgrade to create more lists.")
    end
  end
end
