class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  belongs_to :account
  has_many :api_keys, dependent: :destroy

  validates :email, presence: true, uniqueness: { scope: :account_id }
  validates :role, inclusion: { in: %w[owner admin member] }

  # Scoped to account
  def self.in_account(account)
    where(account: account)
  end

  # Role checks
  def owner?
    role == "owner"
  end

  def admin?
    role == "admin"
  end

  def member?
    role == "member"
  end

  # Permission helpers
  def can_manage_team?
    owner? || admin?
  end

  def can_manage_account_settings?
    owner? || admin?
  end

  def can_manage_billing?
    owner?
  end

  def can_delete_resources?
    owner? || admin?
  end
end
