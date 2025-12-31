class Image < ApplicationRecord
  belongs_to :account
  has_one_attached :file

  validates :file, attached: true,
                   content_type: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
                   size: { less_than: 5.megabytes, message: 'must be less than 5MB' }
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  # Generate a short URL for the image
  def url
    # Use configured host or fallback to localhost for development
    host = Rails.application.config.action_mailer.default_url_options[:host] || 'localhost'
    port = Rails.application.config.action_mailer.default_url_options[:port]

    url_options = { host: host, protocol: Rails.env.production? ? 'https' : 'http' }
    url_options[:port] = port if port && !Rails.env.production?

    Rails.application.routes.url_helpers.short_image_url(slug, **url_options)
  end

  private

  def generate_slug
    return if slug.present?

    # Get filename and extension
    filename = file.filename.to_s
    extension = File.extname(filename) # e.g., ".png"
    basename = filename.gsub(/\.[^.]+\z/, '') # filename without extension

    # Parameterize and take first 20 characters
    base_slug = basename.parameterize[0, 20]

    # Add random 6-character string
    random_suffix = SecureRandom.alphanumeric(6).downcase

    # Combine with extension
    self.slug = "#{base_slug}-#{random_suffix}#{extension}"

    # Ensure uniqueness (extremely unlikely to collide, but just in case)
    while Image.exists?(slug: self.slug)
      random_suffix = SecureRandom.alphanumeric(6).downcase
      self.slug = "#{base_slug}-#{random_suffix}#{extension}"
    end
  end
end
