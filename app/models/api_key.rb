class ApiKey < ApplicationRecord
  belongs_to :account
  belongs_to :user

  attr_accessor :token

  before_create :generate_token

  validates :name, presence: true

  # Generate secure random token
  def generate_token
    loop do
      self.token = SecureRandom.base58(32)
      self.token_digest = BCrypt::Password.create(token)
      self.last_4 = token[-4..]
      break unless ApiKey.exists?(token_digest: token_digest)
    end
  end

  # Verify token
  def self.authenticate(token)
    return nil if token.blank?

    api_keys = where(active: true)
    api_keys.find do |api_key|
      begin
        BCrypt::Password.new(api_key.token_digest) == token
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
