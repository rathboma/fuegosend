class Invitation < ApplicationRecord
  belongs_to :account
  belongs_to :invited_by, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: %w[owner admin member] }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where(accepted_at: nil).where("expires_at <= ?", Time.current) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  # Check if invitation is still valid
  def valid_for_acceptance?
    accepted_at.nil? && expires_at > Time.current
  end

  # Check if invitation has expired
  def expired?
    accepted_at.nil? && expires_at <= Time.current
  end

  # Accept the invitation and create user
  def accept!(user_params = {})
    return false unless valid_for_acceptance?

    # Check if user already exists
    existing_user = User.find_by(email: email, account: account)
    return false if existing_user

    # Create new user
    user = User.new(user_params.merge(
      email: email,
      account: account,
      role: role
    ))

    if user.save
      update!(accepted_at: Time.current)
      user
    else
      false
    end
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiration
    self.expires_at ||= 7.days.from_now
  end
end
