class ListSubscription < ApplicationRecord
  belongs_to :list
  belongs_to :subscriber

  validates :status, inclusion: { in: %w[active unsubscribed] }
  validates :subscriber_id, uniqueness: { scope: :list_id }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :unsubscribed, -> { where(status: "unsubscribed") }

  # Callbacks
  after_create :increment_list_count
  after_update :update_list_count, if: :saved_change_to_status?
  after_destroy :decrement_list_count

  # Unsubscribe from this list
  def unsubscribe!
    update!(
      status: "unsubscribed",
      unsubscribed_at: Time.current
    )
  end

  # Resubscribe to this list
  def resubscribe!
    update!(
      status: "active",
      subscribed_at: Time.current,
      unsubscribed_at: nil
    )
  end

  private

  def increment_list_count
    list.increment!(:subscribers_count) if status == "active"
  end

  def decrement_list_count
    list.decrement!(:subscribers_count) if status == "active"
  end

  def update_list_count
    if status == "active" && status_before_last_save == "unsubscribed"
      list.increment!(:subscribers_count)
    elsif status == "unsubscribed" && status_before_last_save == "active"
      list.decrement!(:subscribers_count)
    end
  end
end
