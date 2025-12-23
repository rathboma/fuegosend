class Image < ApplicationRecord
  belongs_to :account
  has_one_attached :file

  validates :file, attached: true, content_type: ['image/png', 'image/jpg', 'image/jpeg', 'image/gif', 'image/webp']
  validates :file, size: { less_than: 5.megabytes, message: 'must be less than 5MB' }

  # Generate a public URL for the image
  def url
    # Use configured host or fallback to localhost for development
    host = Rails.application.config.action_mailer.default_url_options[:host] || 'localhost'
    port = Rails.application.config.action_mailer.default_url_options[:port]

    url_options = { host: host, protocol: Rails.env.production? ? 'https' : 'http' }
    url_options[:port] = port if port && !Rails.env.production?

    Rails.application.routes.url_helpers.rails_blob_url(file, **url_options)
  end
end
